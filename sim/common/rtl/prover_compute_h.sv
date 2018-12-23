// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// compute h values
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

// (see prover_compute_h_percopy for setup)
//
// After the first b rounds of sumcheck, we have reduced all ncopies * ninputs
// inputs to just ninputs values that are a random linear combination where
// weightings are based on V's first b coins.
//
// We continue...
//
// 3. In the next g rounds, we just record values for w1.
//
// 4. In the next g rounds, we get new values for w2, compute w2-w1, and
//    compute values for h(gamma(t)), t \in {2, ... g}.
//
// NOTE We could get additional time-area tradeoff flexibility by sharing 
//      a compute_h_chi add adder tree among multiple perh computations.

`ifndef __module_prover_compute_h
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
`include "lagrange_interpolate.sv"
`include "ringbuf_simple.sv"
`include "verifier_compute_io_elembank.sv"
module prover_compute_h
    #( parameter                nCopies = 8
     , parameter                nInputs = 8
     , parameter                nParBits = 1
// NOTE do not override parameters below this line //
     , parameter                nCopyBits = $clog2(nCopies)
     , parameter                nInBits = $clog2(nInputs)
    )( input                    clk
     , input                    rstb

     , input                    en
     , input                    restart

     , input  [`F_NBITS-1:0]    tau
     , input  [`F_NBITS-1:0]    m_tau_p1

     , input  [`F_NBITS-1:0]    h0_in
     , input  [`F_NBITS-1:0]    h1_in

     , input  [`F_NBITS-1:0]    chi_early [nInputs-1:0]
     , input                    chi_early_ready

     , output [`F_NBITS-1:0]    h_coeff_out [nInBits:0]

     , output [`F_NBITS-1:0]    w1 [nInBits-1:0]
     , output [`F_NBITS-1:0]    w2_m_w1 [nInBits-1:0]
     , output [`F_NBITS-1:0]    z2 [nCopyBits-1:0]
     , output [`F_NBITS-1:0]    m_z2_p1 [nCopyBits-1:0]

     , output                   ready_pulse
     , output                   ready
     );

// sanity checks
generate
    if (nCopies < 4) begin: IErr1
        Error_nCopies_must_be_at_least_four_in_prover_compute_h __error__();
    end
    if (nInBits < 3) begin: IErr1
        Error_nInBits_must_be_at_least_three_in_prover_compute_h __error__();
    end
    if ($clog2(nCopies) != nCopyBits) begin: IErr3
        Error_do_not_override_nCopyBits_in_prover_compute_h __error__();
    end
    if ($clog2(nInputs) != nInBits) begin: IErr4
        Error_do_not_override_nInBits_in_prover_compute_h __error__();
    end
endgenerate

localparam integer nInputsRnd = 1 << nInBits;
localparam integer nAddInputs = 1 << (nInBits - 1);
localparam integer nCopiesRnd = 1 << nCopyBits;

reg en_w1_r_reg, en_w1_r_next;
reg en_w1_w_reg, en_w1_w_next;
reg en_w2mw1_reg, en_w2mw1_next;
wire [`F_NBITS-1:0] w1_current;
wire [`F_NBITS-1:0] w2mw1_current = w2_m_w1[nInBits-1];

reg restart_reg, restart_next;
wire interp_ready;
reg en_interp_reg, en_interp_next;

wire [`F_NBITS-1:0] h_val [nInBits:2];
reg [nInBits:2] hchi_reg, hchi_next;
wire hchi_done = hchi_reg == {1'b1,{(nInBits-2){1'b0}}};
reg en_hchis_reg, en_hchis_next;

wire [nInBits:2] elm_ready;
wire all_elm_ready = &(elm_ready);

reg [nInBits-1:0] w1cnt_reg, w1cnt_next;
reg [nInBits-1:0] w2cnt_reg, w2cnt_next;

reg en_add_reg, en_add_next;
wire add_ready;
reg [`F_NBITS-1:0] add_in0_reg, add_in0_next, add_in1_reg, add_in1_next;
wire [`F_NBITS-1:0] add_out;
reg [`F_NBITS-1:0] wtmp_reg, wtmp_next;

enum { ST_IDLE, ST_DISPATCH, ST_SAVEZ2, ST_W2MW1, ST_HXPRE, ST_HXINT, ST_HX1M, ST_HCHI, ST_HXPOST, ST_INTRP } state_reg, state_next;

reg en_dly, ready_dly;
wire start = en & ~en_dly;
assign ready = (state_reg == ST_IDLE) & ~start;
assign ready_pulse = ready & ~ready_dly;
wire en_z2 = state_reg == ST_SAVEZ2;

`ALWAYS_COMB begin
    en_add_next = 1'b0;
    en_hchis_next = 1'b0;
    en_w1_r_next = 1'b0;
    en_w1_w_next = 1'b0;
    en_w2mw1_next = 1'b0;
    en_interp_next = 1'b0;
    restart_next = 1'b0;
    add_in0_next = add_in0_reg;
    add_in1_next = add_in1_reg;
    wtmp_next = wtmp_reg;
    hchi_next = hchi_reg;
    w1cnt_next = w1cnt_reg;
    w2cnt_next = w2cnt_reg;
    state_next = state_reg;

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                restart_next = restart;
                state_next = ST_DISPATCH;
            end
        end

        ST_DISPATCH: begin
            if (restart_reg | ~chi_early_ready) begin
                // run percp chi
                state_next = ST_SAVEZ2;
                // w1cnt is 0 at this point
                w1cnt_next = {(nInBits){1'b0}};
            end else if (~w1cnt_reg[nInBits-1]) begin
                // record which w1 count we're on
                w1cnt_next = {w1cnt_reg[nInBits-2:0], 1'b1};
                w2cnt_next = {(nInBits){1'b0}};
                // save the next w1 value
                en_w1_w_next = 1'b1;
                state_next = ST_IDLE;
            end else if (~w2cnt_reg[nInBits-1]) begin
                // save w2
                wtmp_next = tau;
                w2cnt_next = {w2cnt_reg[nInBits-2:0], 1'b1};
                // start computing w2 - w1
                // see field_subtract for how this works!
                add_in0_next = tau;
                add_in1_next = ~w1_current;
                en_add_next = 1'b1;
                state_next = ST_W2MW1;
                // rotate to the next w1
                en_w1_r_next = 1'b1;
            end else begin
                // nothing to do (need a restart!)
                state_next = ST_IDLE;
            end
        end

        ST_SAVEZ2: begin
            // just advance the z2 shiftregs
            state_next = ST_IDLE;
        end

        ST_W2MW1: begin
            if (~en_add_reg & add_ready) begin
                // finish computing w2 - w1
                add_in0_next = add_out;
                add_in1_next = `F_Q_P1_MI;
                en_add_next = 1'b1;
                // about to start computing h[i], i \in {2 ... g}
                state_next = ST_HXPRE;
            end
        end

        ST_HXPRE: begin
            if (~en_add_reg & add_ready) begin
                // save w2-w1 in ringbuf
                en_w2mw1_next = 1'b1;
                // compute w2 + (w2 - w1)
                add_in0_next = add_out;
                add_in1_next = wtmp_reg;
                en_add_next = 1'b1;
                // h[2] is up; compute 1 - (w2 + (w2 - w1))
                hchi_next = {{(nInBits-3){1'b0}},1'b1};
                state_next = ST_HX1M;
            end
        end

        ST_HXINT: begin
            // move to the next hchi
            hchi_next = {hchi_reg[nInBits-1:2], 1'b0};
            state_next = ST_HX1M;
        end

        ST_HX1M: begin
            if (~en_add_reg & add_ready) begin
                // save w2 + k * (w2-w1) in wtmp
                wtmp_next = add_out;
                // compute 1 - (w2 + k * (w2-w1))
                // see field_one_minus for how this works!
                add_in0_next = ~add_out;
                add_in1_next = `F_Q_P2_MI;
                en_add_next = 1'b1;
                state_next = ST_HCHI;
            end
        end

        ST_HCHI: begin
            if (~en_add_reg & add_ready) begin
                if (hchi_done) begin
                    state_next = ST_HXPOST;
                end else begin
                    state_next = ST_HXINT;
                    // start computing next w2 + k * (w2-w1)
                    add_in0_next = w2mw1_current;
                    add_in1_next = wtmp_reg;
                    en_add_next = 1'b1;
                end
                // kick off hchi
                en_hchis_next = 1'b1;
                // first time through, we restart all hchi
                restart_next = w1cnt_reg[0];
            end
        end

        ST_HXPOST: begin
            if (~en_hchis_reg & all_elm_ready) begin
                if (w2cnt_reg[nInBits-1]) begin
                    // run all hchi to compute dot products in parallel
                    en_interp_next = 1'b1;
                    state_next = ST_INTRP;
                end else begin
                    // Still waiting on some w2 values.
                    state_next = ST_IDLE;
                    // we've finished a pass through all h[i]
                    // clear lsbit of w1cnt_reg to indicate no need to reset next time
                    w1cnt_next[0] = 1'b0;
                end
            end
        end

        ST_INTRP: begin
            // wait for interpolator to be done
            if (~en_interp_reg & interp_ready) begin
                state_next = ST_IDLE;
            end
        end
    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        ready_dly <= 1'b1;
        hchi_reg <= {(nInBits-1){1'b0}};
        en_add_reg <= 1'b0;
        en_hchis_reg <= 1'b0;
        en_w1_w_reg <= 1'b0;
        en_w1_r_reg <= 1'b0;
        en_w2mw1_reg <= 1'b0;
        en_interp_reg <= 1'b0;
        restart_reg <= 1'b0;
        add_in0_reg <= {(`F_NBITS){1'b0}};
        add_in1_reg <= {(`F_NBITS){1'b0}};
        wtmp_reg <= {(`F_NBITS){1'b0}};
        w1cnt_reg <= {(nInBits){1'b0}};
        w2cnt_reg <= {(nInBits){1'b0}};
        state_reg <= ST_IDLE;
    end else begin
        en_dly <= en;
        ready_dly <= ready;
        hchi_reg <= hchi_next;
        en_add_reg <= en_add_next;
        en_hchis_reg <= en_hchis_next;
        en_w1_w_reg <= en_w1_w_next;
        en_w1_r_reg <= en_w1_r_next;
        en_w2mw1_reg <= en_w2mw1_next;
        en_interp_reg <= en_interp_next;
        restart_reg <= restart_next;
        add_in0_reg <= add_in0_next;
        add_in1_reg <= add_in1_next;
        wtmp_reg <= wtmp_next;
        w1cnt_reg <= w1cnt_next;
        w2cnt_reg <= w2cnt_next;
        state_reg <= state_next;
    end
end

field_adder iAdd
     ( .clk         (clk)
     , .rstb        (rstb)
     , .en          (en_add_reg)
     , .a           (add_in0_reg)
     , .b           (add_in1_reg)
     , .ready_pulse ()
     , .ready       (add_ready)
     , .c           (add_out)
     );

ringbuf_simple
    #( .nbits   (`F_NBITS)
     , .nwords  (nInBits)
     ) iW1Buf
     ( .clk     (clk)
     , .rstb    (rstb)
     , .en      (en_w1_r_reg | en_w1_w_reg)
     , .wren    (en_w1_w_reg)
     , .d       (tau)
     , .q       (w1_current)
     , .q_all   (w1)
     );

ringbuf_simple
    #( .nbits   (`F_NBITS)
     , .nwords  (nInBits)
     ) iW2mW1Buf
     ( .clk     (clk)
     , .rstb    (rstb)
     , .en      (en_w2mw1_reg)
     , .wren    (en_w2mw1_reg)
     , .d       (add_out)
     , .q       ()
     , .q_all   (w2_m_w1)
     );

ringbuf_simple
    #( .nbits       (`F_NBITS)
     , .nwords      (nCopyBits)
     ) z2RingBuf
     ( .clk         (clk)
     , .rstb        (rstb)
     , .en          (en_z2)
     , .wren        (en_z2)
     , .d           (tau)
     , .q           ()
     , .q_all       (z2)
     );

ringbuf_simple
    #( .nbits       (`F_NBITS)
     , .nwords      (nCopyBits)
     ) mz2p1RingBuf
     ( .clk         (clk)
     , .rstb        (rstb)
     , .en          (en_z2)
     , .wren        (en_z2)
     , .d           (m_tau_p1)
     , .q           ()
     , .q_all       (m_z2_p1)
     );

wire [`F_NBITS-1:0] lagrange_in [nInBits:0];
assign lagrange_in[0] = h0_in;
assign lagrange_in[1] = h1_in;
wire cbuf_en;
wire [`F_NBITS-1:0] cbuf_data;
lagrange_interpolate
    #( .npoints     (nInBits + 1)
     ) iLagrange
     ( .clk         (clk)
     , .rstb        (rstb)
     , .en          (en_interp_reg)
     , .yi          (lagrange_in)
     , .c_wren      (cbuf_en)
     , .c_data      (cbuf_data)
     , .ready       (interp_ready)
     , .ready_pulse ()
     );

ringbuf_simple
    #( .nbits   (`F_NBITS)
     , .nwords  (nInBits + 1)
     ) iCoeffBuf
     ( .clk     (clk)
     , .rstb    (rstb)
     , .en      (cbuf_en)
     , .wren    (cbuf_en)
     , .d       (cbuf_data)
     , .q       ()
     , .q_all   (h_coeff_out)
     );

wire [`F_NBITS-1:0] mvals_in [nInputsRnd-1:0];
genvar HNum;
genvar InNum;
generate
    for (InNum = 0; InNum < nInputs; InNum = InNum + 1) begin: MValsHookup
        assign mvals_in[InNum] = chi_early[InNum];
    end
    for (InNum = nInputs; InNum < nInputsRnd; InNum = InNum + 1) begin: MValsDummy
        assign mvals_in[InNum] = {(`F_NBITS){1'b0}};
    end
    for (HNum = 2; HNum < nInBits + 1; HNum = HNum + 1) begin: HInsts
        verifier_compute_io_elembank
           #( .nCopyBits    (nInBits)
            , .nParBits     (nParBits)
            ) iElem
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (hchi_reg[HNum] & en_hchis_reg)
            , .restart      (restart_reg)
            , .tau          (wtmp_reg)
            , .m_tau_p1     (add_out)
            , .in_vals      (mvals_in)
            , .final_out    (lagrange_in[HNum])
            , .ready        (elm_ready[HNum])
            , .ready_pulse  ()
            );
    end
endgenerate

endmodule
`define __module_prover_compute_h
`endif // __module_prover_compute_h
