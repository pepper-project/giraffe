// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// early rounds of protocol
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_prover_compute_v_early
`include "simulator.v"
`include "field_arith_defs.v"
`include "gatefn_defs.v"
`include "prover_compute_chi.sv"
`include "prover_compute_v_early_gatesbank.sv"
`include "prover_compute_v_valsbank.sv"
`include "prover_shuffle_early.sv"
module prover_compute_v_early
    #( parameter                ngates = 8
     , parameter                ninputs = 8
     , parameter                nmuxsels = 1

     , parameter                nCopyBits = 3
     , parameter                nParBits = 1

     , parameter [`GATEFN_BITS*ngates-1:0] gates_fn = 0

     , parameter                ninbits = $clog2(ninputs)   // do not override
     , parameter                nmuxbits = $clog2(nmuxsels < 2 ? 2 : nmuxsels) // do not override

     , parameter [(ninbits*ngates)-1:0] gates_in0 = 0
     , parameter [(ninbits*ngates)-1:0] gates_in1 = 0
     , parameter [(ngates*nmuxbits)-1:0] gates_mux = 0
// NOTE do not override below this line //
     , parameter                nCopies = 1 << nCopyBits
    )( input                    clk
     , input                    rstb

     , input                    en
     , input                    restart

     , input  [`F_NBITS-1:0]    tau
     , input  [`F_NBITS-1:0]    m_tau_p1

     , input  [`F_NBITS-1:0]    z2 [nCopyBits-1:0]
     , input  [`F_NBITS-1:0]    m_z2_p1 [nCopyBits-1:0]

     , input  [`F_NBITS-1:0]    v_in [nCopies-1:0] [ninputs-1:0]
     , input  [`F_NBITS-1:0]    z1_chi [ngates-1:0]
     , input                    z1_chi_ready

     , input  [nmuxsels-1:0]    mux_sel

     , output [`F_NBITS-1:0]    chi_out [ninputs-1:0]
     , output [`F_NBITS-1:0]    beta_out

     , output                   ready
     , output                   ready_pulse

     , output [`F_NBITS-1:0]    c_out [3:0]
     );

// sanity check
generate
    if (nCopies != (1 << nCopyBits)) begin: IErr1
        Error_do_not_override_nCopies_in_prover_compute_v_early __error__();
    end
endgenerate

localparam nParallel = 1 << nParBits;
localparam nCopiesH = 1 << (nCopyBits - 1);
localparam ncountbits = $clog2(2 * nCopyBits + 1);

reg [ncountbits-1:0] count_reg, count_next;
wire penult_preload_round = count_reg == (nCopyBits - 2);
wire last_preload_round = count_reg == (nCopyBits - 1);
wire last_execution_round = count_reg == (2 * nCopyBits - 1);
wire execution_finished = count_reg == (2 * nCopyBits);
reg restart_beta_reg, restart_beta_next, restart_vals_reg, restart_vals_next;
wire [`F_NBITS-1:0] vals_out [nParallel-1:0] [ninputs-1:0] [3:0];
wire vals_final_ready, vals_ready;
wire [nParallel-1:0] gates_ready, gates_en;

wire beta_ready, gates_out_ready;
wire [3:0] shuffle_ready_pulse;
wire [3:0] shuffle_ready;
wire all_shuffle_ready = &(shuffle_ready);
reg shuffmask_reg, shuffmask_next;

enum { ST_IDLE, ST_BETA_ST, ST_BETA, ST_VALS_PRE, ST_VALS_ST, ST_VALS, ST_INTERP_ST, ST_INTERP } state_reg, state_next;
reg en_dly, ready_dly;
wire start = en & ~en_dly;
assign ready = (state_reg == ST_IDLE) & ~start;
assign ready_pulse = ready & ~ready_dly;

wire inST_BETA = state_reg == ST_BETA;
wire en_beta = (state_reg == ST_BETA_ST) | (state_reg == ST_VALS_ST);
wire en_vals = (state_reg == ST_VALS_ST) | ((state_reg == ST_BETA_ST) & last_preload_round);
wire en_interp = state_reg == ST_INTERP_ST;

wire select_z2 = (state_reg == ST_BETA_ST) | (state_reg == ST_BETA);
reg [`F_NBITS-1:0] tau_z2, m_tau_p1_z2;
wire [`F_NBITS-1:0] tau_sel = select_z2 ? tau_z2 : tau;
wire [`F_NBITS-1:0] m_tau_p1_sel = select_z2 ? m_tau_p1_z2 : m_tau_p1;

integer GNumC;
`ALWAYS_COMB begin
    state_next = state_reg;
    count_next = count_reg;
    restart_beta_next = restart_beta_reg;
    restart_vals_next = restart_vals_reg;
    shuffmask_next = shuffmask_reg;
    tau_z2 = {(`F_NBITS){1'bX}};
    m_tau_p1_z2 = {(`F_NBITS){1'bX}};

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                if (restart) begin
                    restart_beta_next = 1'b1;
                    restart_vals_next = 1'b0;
                    count_next = {(ncountbits){1'b0}};
                    state_next = ST_BETA_ST;
                    shuffmask_next = 1'b0;
                end else begin
                    restart_beta_next = 1'b0;
                    restart_vals_next = 1'b0;
                    state_next = ST_VALS_ST;
                end
            end
        end

        ST_BETA_ST, ST_BETA: begin
            for (GNumC = 0; GNumC < nCopyBits; GNumC = GNumC + 1) begin
                if (count_reg == GNumC) begin
                    tau_z2 = z2[nCopyBits - GNumC - 1];
                    m_tau_p1_z2 = m_z2_p1[nCopyBits - GNumC - 1];
                end
            end
            if (all_shuffle_ready & beta_ready & vals_ready & gates_out_ready) begin
                count_next = count_reg + 1;
                restart_beta_next = 1'b0;
                if (last_preload_round) begin
                    restart_vals_next = 1'b0;
                    state_next = ST_INTERP_ST;
                end else if (penult_preload_round) begin
                    restart_vals_next = 1'b1;
                    state_next = ST_VALS_PRE;
                end else begin
                    state_next = ST_BETA_ST;
                end
            end else begin
                state_next = ST_BETA;
            end
        end

        ST_VALS_PRE: begin
            if (z1_chi_ready) begin
                state_next = ST_BETA_ST;
                shuffmask_next = 1'b1;
            end
        end

        ST_VALS_ST, ST_VALS: begin
            if (all_shuffle_ready & beta_ready & vals_ready & gates_out_ready) begin
                count_next = count_reg + 1;
                if (last_execution_round) begin
                    state_next = ST_IDLE;
                end else begin
                    state_next = ST_INTERP_ST;
                end
            end else begin
                state_next = ST_VALS;
            end
        end

        ST_INTERP_ST, ST_INTERP: begin
            if (gates_out_ready) begin
                state_next = ST_IDLE;
            end else begin
                state_next = ST_INTERP;
            end
        end
    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        ready_dly <= 1'b1;
        state_reg <= ST_IDLE;
        restart_beta_reg <= 1'b0;
        restart_vals_reg <= 1'b0;
        shuffmask_reg <= 1'b0;
        count_reg <= {(ncountbits){1'b0}};
    end else begin
        en_dly <= en;
        ready_dly <= ready;
        state_reg <= state_next;
        restart_beta_reg <= restart_beta_next;
        restart_vals_reg <= restart_vals_next;
        shuffmask_reg <= shuffmask_next;
        count_reg <= count_next;
    end
end

wire beta_ready_pulse;
wire [`F_NBITS-1:0] beta_vals [nCopies-1:0];
wire [`F_NBITS-1:0] point3_vals [nCopiesH-1:0];
wire [`F_NBITS-1:0] point4_vals [nCopiesH-1:0];
assign beta_out = beta_vals[0];
wire [`F_NBITS-1:0] chi_in_0 [nCopies-1:0], beta_even_vals [nCopiesH-1:0], beta_odd_vals [nCopiesH-1:0];
genvar GateNum;
generate
    for (GateNum = 0; GateNum < nCopies; GateNum = GateNum + 1) begin: ChiInHookup
        assign chi_in_0[GateNum] = {(`F_NBITS){1'b0}};
        if (GateNum < nCopies / 2) begin: EvenOddHookup
            assign beta_even_vals[GateNum] = beta_vals[2*GateNum];
            assign beta_odd_vals[GateNum] = beta_vals[2*GateNum + 1];
        end
    end
endgenerate
prover_compute_chi
    #( .npoints         (nCopyBits)
     ) iBeta
     ( .clk             (clk)
     , .rstb            (rstb)
     , .en              (en_beta)
     , .restart         (restart_beta_reg)
     , .preload         (1'b0)
     , .skip_pt4        (1'b0)
     , .skip_pt3        (1'b0)
     , .tau             (tau_sel)
     , .m_tau_p1        (m_tau_p1_sel)
     , .chi_in          (chi_in_0)
     , .ready_pulse     (beta_ready_pulse)
     , .ready           (beta_ready)
     , .chi_out         (beta_vals)
     , .point3_out      (point3_vals)
     , .point4_out      (point4_vals)
     );

wire [`F_NBITS-1:0] beta_even_shuff [nCopiesH-1:0];
wire [`F_NBITS-1:0] beta_odd_shuff [nCopiesH-1:0];
wire [`F_NBITS-1:0] point3_shuff [nCopiesH-1:0];
wire [`F_NBITS-1:0] point4_shuff [nCopiesH-1:0];
prover_shuffle_early
    #( .nValBits        (nCopyBits - 1)
     , .nParBits        (nParBits)
     ) iShuffleEven
     ( .clk             (clk)
     , .rstb            (rstb)
     , .en              (beta_ready_pulse)
     , .restart         (beta_ready_pulse & inST_BETA)
     , .vals_in         (beta_even_vals)
     , .ready_pulse     (shuffle_ready_pulse[0])
     , .ready           (shuffle_ready[0])
     , .vals_out        (beta_even_shuff)
     );
prover_shuffle_early
    #( .nValBits        (nCopyBits - 1)
     , .nParBits        (nParBits)
     ) iShuffleOdd
     ( .clk             (clk)
     , .rstb            (rstb)
     , .en              (beta_ready_pulse)
     , .restart         (beta_ready_pulse & inST_BETA)
     , .vals_in         (beta_odd_vals)
     , .ready_pulse     (shuffle_ready_pulse[1])
     , .ready           (shuffle_ready[1])
     , .vals_out        (beta_odd_shuff)
     );
prover_shuffle_early
    #( .nValBits        (nCopyBits - 1)
     , .nParBits        (nParBits)
     ) iShufflePoint3
     ( .clk             (clk)
     , .rstb            (rstb)
     , .en              (beta_ready_pulse)
     , .restart         (beta_ready_pulse & inST_BETA)
     , .vals_in         (point3_vals)
     , .ready_pulse     (shuffle_ready_pulse[2])
     , .ready           (shuffle_ready[2])
     , .vals_out        (point3_shuff)
     );
prover_shuffle_early
    #( .nValBits        (nCopyBits - 1)
     , .nParBits        (nParBits)
     ) iShufflePoint4
     ( .clk             (clk)
     , .rstb            (rstb)
     , .en              (beta_ready_pulse)
     , .restart         (beta_ready_pulse & inST_BETA)
     , .vals_in         (point4_vals)
     , .ready_pulse     (shuffle_ready_pulse[3])
     , .ready           (shuffle_ready[3])
     , .vals_out        (point4_shuff)
     );

prover_compute_v_valsbank
    #( .nCopyBits       (nCopyBits)
     , .nParBits        (nParBits)
     , .ninputs         (ninputs)
     ) iValsBank
     ( .clk             (clk)
     , .rstb            (rstb)
     , .en              (en_vals)
     , .restart         (restart_vals_reg)
     , .beta_ready      (all_shuffle_ready & shuffmask_reg & beta_ready)
     , .tau             (tau)
     , .m_tau_p1        (m_tau_p1)
     , .v_in            (v_in)
     , .v_out           (vals_out)
     , .final_out       (chi_out)
     , .final_ready     (vals_final_ready)
     , .gates_ready     (gates_ready)
     , .gates_en        (gates_en)
     , .ready           (vals_ready)
     );

prover_compute_v_early_gatesbank
    #( .nCopyBits       (nCopyBits)
     , .nParBits        (nParBits)
     , .ngates          (ngates)
     , .ninputs         (ninputs)
     , .nmuxsels        (nmuxsels)
     , .gates_fn        (gates_fn)
     , .gates_in0       (gates_in0)
     , .gates_in1       (gates_in1)
     , .gates_mux       (gates_mux)
     ) iGatesBank
     ( .clk             (clk)
     , .rstb            (rstb)
     , .beta_en         (shuffle_ready_pulse)
     , .en              (gates_en)
     , .interp_en       (en_interp)
     , .v_in            (vals_out)
     , .z1_chi          (z1_chi)
     , .beta_in_even    (beta_even_shuff)
     , .beta_in_odd     (beta_odd_shuff)
     , .point3_in       (point3_shuff)
     , .point4_in       (point4_shuff)
     , .mux_sel         (mux_sel)
     , .in_ready        (gates_ready)
     , .out_ready       (gates_out_ready)
     , .out_ready_pulse ()
     , .c_out           (c_out)
     );

endmodule
`define __module_prover_compute_v_early
`endif // __module_prover_compute_v_early
