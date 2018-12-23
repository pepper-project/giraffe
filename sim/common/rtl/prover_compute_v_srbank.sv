// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// instantiate bank of parallel shift registers for all copies of one input
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_prover_compute_v_srbank
`include "simulator.v"
`include "field_arith_defs.v"
`include "prover_compute_v_sr.sv"
module prover_compute_v_srbank
    #( parameter                nCopyBits = 2
     , parameter                nParBits = 0
// NOTE do not override below this line //
     , parameter                nCopies = 1 << nCopyBits
     , parameter                nParallel = 1 << nParBits
    )( input                    clk
     , input                    rstb

     , input                    en
     , input                    restart

     , input  [`F_NBITS-1:0]    tau
     , input  [`F_NBITS-1:0]    m_tau_p1

     , input  [`F_NBITS-1:0]    in_vals [nCopies-1:0]

     , output [`F_NBITS-1:0]    out [nParallel-1:0] [3:0]

     , output [`F_NBITS-1:0]    final_out
     , output                   final_ready

     , input  [nParallel-1:0]   gates_ready
     , output [nParallel-1:0]   gates_en

     , output                   ready
     , output                   ready_pulse
     );

// sanity check
generate
    if (nCopyBits < 2) begin: IErr1
        Error_nCopyBits_must_be_at_least_two_in_prover_compute_v_srbank __error__();
    end
    if ((nCopyBits - nParBits) < 2) begin: IErr2
        Error_maximum_parallelism_limit_exceeded_in_prover_compute_v_srbank __error__();
    end
    if (nCopies != (1 << nCopyBits)) begin: IErr3
        Error_do_not_override_nCopies_in_prover_compute_v_srbank __error__();
    end
    if (nParallel != (1 << nParBits)) begin: IErr4
        Error_do_not_override_nParallel_in_prover_compute_v_srbank __error__();
    end
endgenerate

localparam perCopyBits = nCopyBits - nParBits;
localparam perCopies = 1 << perCopyBits;

wire [`F_NBITS-1:0] pass_val [nParallel-1:0];
wire [nParallel-1:0] pass_ready;

assign final_out = pass_val[0];
assign final_ready = pass_ready[0];

wire [nParallel-1:0] gate_ready;
assign ready = &(gate_ready);
reg ready_dly;
assign ready_pulse = ready & ~ready_dly;

genvar InstNum;
genvar CopyNum;
generate
    for (InstNum = 0; InstNum < nParallel; InstNum = InstNum + 1) begin: SRInst
        wire [`F_NBITS-1:0] even_in;
        wire [`F_NBITS-1:0] odd_in;
        wire even_in_ready, odd_in_ready;
        if (2 * InstNum + 1 < nParallel) begin
            assign even_in = pass_val[2*InstNum];
            assign odd_in = pass_val[2*InstNum + 1];
            assign even_in_ready = pass_ready[2*InstNum];
            assign odd_in_ready = pass_ready[2*InstNum + 1];
        end else begin
            assign even_in = {(`F_NBITS){1'b0}};
            assign odd_in = {(`F_NBITS){1'b0}};
            assign even_in_ready = 1'b1;
            assign odd_in_ready = 1'b1;
        end

        localparam copyOffset = InstNum * perCopies;
        wire [`F_NBITS-1:0] in_vals_inst [perCopies-1:0];
        for (CopyNum = 0; CopyNum < perCopies; CopyNum = CopyNum + 1) begin: InHookup
            assign in_vals_inst[CopyNum] = in_vals[copyOffset + CopyNum];
        end
        wire [`F_NBITS-1:0] out_inst [3:0];
        for (CopyNum = 0; CopyNum < 4; CopyNum = CopyNum + 1) begin: OutHookup
            assign out[InstNum][CopyNum] = out_inst[CopyNum];
        end

        prover_compute_v_sr
            #( .nCopyBits           (perCopyBits)
             , .posParallel         (InstNum)
             , .totParallel         (nParallel)
             ) iSRv
             ( .clk                 (clk)
             , .rstb                (rstb)
             , .en                  (en)
             , .restart             (restart)
             , .tau                 (tau)
             , .m_tau_p1            (m_tau_p1)
             , .in_vals             (in_vals_inst)
             , .out                 (out_inst)
             , .even_in             (even_in)
             , .even_in_ready       (even_in_ready)
             , .odd_in              (odd_in)
             , .odd_in_ready        (odd_in_ready)
             , .pass_out            (pass_val[InstNum])
             , .pass_out_ready      (pass_ready[InstNum])
             , .gates_ready         (gates_ready[InstNum])
             , .gates_en            (gates_en[InstNum])
             , .ready_pulse         ()
             , .ready               (gate_ready[InstNum])
             );
    end
endgenerate

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        ready_dly <= 1'b1;
    end else begin
        ready_dly <= ready;
    end
end

endmodule
`define __module_prover_compute_v_srbank
`endif // __module_prover_compute_v_srbank
