// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// compute per-copy values to be used for computing h values
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

// In Giraffe, each layer's sumcheck has a number of rounds
//     nCopyBits + 2 * nInBits
//   = b         + 2 * g
//
// 1. In first b rounds, each new tau is an element of z2 for next layer.
//    It is also used to compute chi_copy values, which will be used after
//    the first b rounds are done.
//
// 2. Once the first b rounds are finished (thus, all chi_copy values have
//    been computed), this block computes a weighted sum of the inputs to
//    each copy of the circuit whose execution is being verified, where the
//    weight used for copy i is chi_copy[i].
//
//    This weighted sum of the inputs are used in the remaining 2 * g rounds
//    to compute the final h[] evaluations.
//
// NOTE: the compute_h process continues in the prover_compute_h block.
//
// This block has programmable parallelism; for step 2: nSerBits is log(2)
// number of output values computed in series at the end; thus, nSerBits = 0
// gives maximum parallelism, and nSerBits = $clog2(nInputs) gives minimum.

`ifndef __module_prover_compute_h_percopy
`include "simulator.v"
`include "field_arith_defs.v"
`include "prover_compute_h_accum.sv"
`include "prover_compute_h_chi.sv"
`include "prover_compute_h_mulonly.sv"
`include "prover_compute_h_parmux.sv"
`include "prover_adder_tree_pl.sv"
`include "ringbuf_simple.sv"
module prover_compute_h_percopy
    #( parameter                nCopies = 4
     , parameter                nInputs = 2
     , parameter                nSerBits = $clog2(nInputs)
// NOTE do not override parameters below this line //
     , parameter                nCopyBits = $clog2(nCopies)
    )( input                    clk
     , input                    rstb

     , input                    en
     , input                    restart

     , input  [`F_NBITS-1:0]    tau
     , input  [`F_NBITS-1:0]    m_tau_p1

     , input  [`F_NBITS-1:0]    layer_inputs [nCopies-1:0] [nInputs-1:0]

     , output [`F_NBITS-1:0]    z2 [nCopyBits-1:0]
     , output [`F_NBITS-1:0]    m_z2_p1 [nCopyBits-1:0]

     , output [`F_NBITS-1:0]    outputs [nInputs-1:0]

     , output                   ready_pulse
     , output                   ready
     , output                   outputs_ready
     , output                   chi_ready
     );

// sanity checks
generate
    if (nCopies < 4) begin: IErr1
        Error_nCopies_must_be_at_least_four_in_prover_compute_h_percopy __error__();
    end
    if (nInputs < 2) begin: IErr2
        Error_nInputs_must_be_at_least_two_in_prover_compute_h_percopy __error__();
    end
    if ($clog2(nCopies) != nCopyBits) begin: IErr3
        Error_do_not_override_nCopyBits_in_prover_compute_h_percopy __error__();
    end
    if (nSerBits < 0) begin: IErr4
        Error_nSerBits_must_be_nonnegative_in_prover_compute_h_percopy __error__();
    end
    if ($clog2(nInputs) < nSerBits) begin: IErr5
        Error_min_parallelism_limited_by_nInputs_in_prover_compute_h_percopy __error__();
    end
endgenerate

localparam integer nPerPar = (1 << nSerBits);
localparam integer nParallel = (nInputs / nPerPar) + ((nInputs % nPerPar != 0) ? 1 : 0);
localparam integer inCountBitsTmp = $clog2(nPerPar);
localparam integer inCountBits = inCountBitsTmp > 0 ? inCountBitsTmp : 1;
localparam integer nCopiesRnd = 1 << nCopyBits;
localparam integer nAddInputs = 1 << (nCopyBits - 1);

reg [inCountBits-1:0] inCount_reg, inCount_next;
wire [`F_NBITS-1:0] laymul_in [nParallel-1:0] [nCopiesRnd-1:0];
genvar ParNumG;
genvar CopyNumG;
genvar InNumG;
generate
    for (ParNumG = 0; ParNumG < nParallel; ParNumG = ParNumG + 1) begin: ParMux
        localparam integer inputOffset = ParNumG * nPerPar;
        for (CopyNumG = 0; CopyNumG < nCopies; CopyNumG = CopyNumG + 1) begin: ParMuxCopy

            // wire up mux_in
            if (nPerPar > 1) begin: ParMuxMultiple
                wire [`F_NBITS-1:0] mux_in [nPerPar-1:0];
                for (InNumG = 0; InNumG < nPerPar; InNumG = InNumG + 1) begin: ParMuxCopyInputs
                    if (inputOffset + InNumG < nInputs) begin: MuxFromLayIn
                        assign mux_in[InNumG] = layer_inputs[CopyNumG][inputOffset + InNumG];
                    end else begin: MuxZero
                        assign mux_in[InNumG] = {(`F_NBITS){1'b0}};
                    end
                end

                prover_compute_h_parmux
                    #( .nInputs         (nPerPar)
                     ) iParMux
                     ( .vals_in         (mux_in)
                     , .count_in        (inCount_reg[inCountBits-1:0])
                     , .val_out         (laymul_in[ParNumG][CopyNumG])
                     );
             end else begin: ParMuxSingle
                 assign laymul_in[ParNumG][CopyNumG] = layer_inputs[CopyNumG][inputOffset];
             end
        end
        for (CopyNumG = nCopies; CopyNumG < nCopiesRnd; CopyNumG = CopyNumG + 1) begin: ParMuxDummy
            assign laymul_in[ParNumG][CopyNumG] = {(`F_NBITS){1'b0}};
        end
    end
endgenerate

wire [`F_NBITS-1:0] chi_out [nCopiesRnd-1:0];
wire chi_ready_int;
assign chi_ready = chi_ready_int;
reg en_chi_reg, en_chi_next;
reg en_mul_reg, en_mul_next;
reg en_z2_reg, en_z2_next;
reg restart_reg, restart_next;
wire [nParallel-1:0] mul_ready;
wire [nParallel-1:0] par_ready;
wire all_ready = &(par_ready);
wire all_mul_ready = &(mul_ready);

enum { ST_IDLE, ST_WAIT, ST_DOMUL, ST_WAIT2 } state_reg, state_next;

// edge detect for enable, ready
reg en_dly, ready_dly;
wire start = en & ~en_dly;
assign ready = (state_reg == ST_IDLE) & ~start;
assign ready_pulse = ready & ~ready_dly;
assign outputs_ready = ready & chi_ready_int;

`ALWAYS_COMB begin
    en_z2_next = 1'b0;
    en_chi_next = 1'b0;
    en_mul_next = 1'b0;
    restart_next = 1'b0;
    inCount_next = inCount_reg;
    state_next = state_reg;

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                if (restart) begin
                    restart_next = 1'b1;
                end

                en_chi_next = 1'b1;
                if (restart | ~chi_ready_int) begin
                    en_z2_next = 1'b1;
                    state_next = ST_WAIT;
                    inCount_next = {(inCountBits){1'b0}};
                end
            end
        end

        ST_WAIT: begin
            if (all_ready) begin
                if (chi_ready_int) begin
                    en_chi_next = 1'b1;
                    en_mul_next = 1'b1;
                    state_next = ST_DOMUL;
                end else begin
                    state_next = ST_IDLE;
                end
            end
        end

        ST_DOMUL: begin
            if (~(en_chi_reg | en_mul_reg) & all_mul_ready) begin
                if (inCount_reg < (nPerPar - 1)) begin
                    inCount_next = inCount_reg + 1;
                    en_chi_next = 1'b1;
                    en_mul_next = 1'b1;
                end else begin
                    state_next = ST_WAIT2;
                end
            end
        end

        ST_WAIT2: begin
            if (all_ready) begin
                state_next = ST_IDLE;
            end
        end

    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        ready_dly <= 1'b1;
        en_z2_reg <= 1'b0;
        en_chi_reg <= 1'b0;
        en_mul_reg <= 1'b0;
        restart_reg <= 1'b0;
        inCount_reg <= {(inCountBits){1'b0}};
        state_reg <= ST_IDLE;
    end else begin
        en_dly <= en;
        ready_dly <= ready;
        en_z2_reg <= en_z2_next;
        en_chi_reg <= en_chi_next;
        en_mul_reg <= en_mul_next;
        restart_reg <= restart_next;
        inCount_reg <= inCount_next;
        state_reg <= state_next;
    end
end

ringbuf_simple
    #( .nbits       (`F_NBITS)
     , .nwords      (nCopyBits)
     ) z2RingBuf
     ( .clk         (clk)
     , .rstb        (rstb)
     , .en          (en_z2_reg)
     , .wren        (en_z2_reg)
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
     , .en          (en_z2_reg)
     , .wren        (en_z2_reg)
     , .d           (m_tau_p1)
     , .q           ()
     , .q_all       (m_z2_p1)
     );

generate
    for (ParNumG = 0; ParNumG < nParallel; ParNumG = ParNumG + 1) begin: ParCh
        localparam integer inputOffset = ParNumG * nPerPar;
        wire addt_ready, addt_en, addt_tag, elem_ready, addt_idle;
        wire accum_ready, accum_en, accum_tag, shiftreg_en_pre;
        wire shiftreg_en = shiftreg_en_pre & accum_tag;
        wire [`F_NBITS-1:0] addt_in [nAddInputs-1:0];
        wire [`F_NBITS-1:0] addt_out, accum_out;
        wire [`F_NBITS-1:0] shiftreg_out [nPerPar-1:0];

        for (InNumG = 0; InNumG < nPerPar; InNumG = InNumG + 1) begin: ParOutHookup
            if (inputOffset + InNumG < nInputs) begin
                assign outputs[inputOffset + InNumG] = shiftreg_out[InNumG];
            end
        end

        assign mul_ready[ParNumG] = elem_ready;
        assign par_ready[ParNumG] = addt_idle & elem_ready & accum_ready;

        wire [`F_NBITS-1:0] mvals_in [nCopiesRnd-1:0];
        for (CopyNumG = 0; CopyNumG < nCopiesRnd; CopyNumG = CopyNumG + 1) begin: MValsHookup
            assign mvals_in[CopyNumG] = laymul_in[ParNumG][CopyNumG];
        end

        if (ParNumG == 0) begin: ParElemChi
            prover_compute_h_chi
                #( .npoints         (nCopyBits)
                 ) iComputeChi
                 ( .clk             (clk)
                 , .rstb            (rstb)
                 , .en              (en_chi_reg)
                 , .restart         (restart_reg)
                 , .tau             (tau)
                 , .m_tau_p1        (m_tau_p1)
                 , .addt_ready      (addt_ready)
                 , .mvals_in        (mvals_in)
                 , .addt_en         (addt_en)
                 , .addt_tag        (addt_tag)
                 , .mvals_out       (addt_in)
                 , .chi_ready       (chi_ready_int)
                 , .ready_pulse     ()
                 , .ready           (elem_ready)
                 , .chi_out         (chi_out)
                 );
        end else begin: ParMulOnly
            prover_compute_h_mulonly
                #( .npoints         (nCopyBits)
                 ) iMulOnly
                 ( .clk             (clk)
                 , .rstb            (rstb)
                 , .en              (en_mul_reg)
                 , .addt_ready      (addt_ready)
                 , .chi_in          (chi_out)
                 , .mvals_in        (mvals_in)
                 , .addt_en         (addt_en)
                 , .addt_tag        (addt_tag)
                 , .mvals_out       (addt_in)
                 , .ready_pulse     ()
                 , .ready           (elem_ready)
                 );
        end

        prover_adder_tree_pl
            #( .ngates          (nAddInputs)
             , .ntagb           (1)
             ) iAddTree
             ( .clk             (clk)
             , .rstb            (rstb)
             , .en              (addt_en)
             , .in              (addt_in)
             , .in_tag          (addt_tag)
             , .idle            (addt_idle)
             , .in_ready_pulse  ()
             , .in_ready        (addt_ready)
             , .out_ready_pulse (accum_en)
             , .out_ready       ()
             , .out             (addt_out)
             , .out_tag         (accum_tag)
             );

        prover_compute_h_accum iaccum
             ( .clk         (clk)
             , .rstb        (rstb)
             , .en          (accum_en)
             , .in          (addt_out)
             , .in_tag      (accum_tag)
             , .ready_pulse (shiftreg_en_pre)
             , .ready       (accum_ready)
             , .out         (accum_out)
             );

        if (nPerPar > 1) begin: ParRingBuf
            ringbuf_simple
                #( .nbits       (`F_NBITS)
                 , .nwords      (nPerPar)
                 ) iRingBuf
                 ( .clk         (clk)
                 , .rstb        (rstb)
                 , .en          (shiftreg_en)
                 , .wren        (shiftreg_en)
                 , .d           (accum_out)
                 , .q           ()
                 , .q_all       (shiftreg_out)
                 );
        end else begin
            assign shiftreg_out[0] = accum_out;
        end
    end
endgenerate

endmodule
`define __module_prover_compute_h_percopy
`endif // __module_prover_compute_h_percopy
