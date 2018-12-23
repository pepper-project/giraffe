// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// A bank of banks of chi computation units for V~ in the early rounds
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_prover_compute_v_valsbank
`include "simulator.v"
`include "field_arith_defs.v"
`include "prover_compute_v_encollect.sv"
`include "prover_compute_v_srbank.sv"
module prover_compute_v_valsbank
    #( parameter                nCopyBits = 3
     , parameter                nParBits = 1
     , parameter                ninputs = 8
// NOTE do not override beyond this line //
     , parameter                nCopies = 1 << nCopyBits
     , parameter                nParallel = 1 << nParBits
    )( input                    clk
     , input                    rstb

     , input                    en
     , input                    restart
     , input                    beta_ready

     , input  [`F_NBITS-1:0]    tau
     , input  [`F_NBITS-1:0]    m_tau_p1

     , input  [`F_NBITS-1:0]    v_in [nCopies-1:0] [ninputs-1:0]

     , output [`F_NBITS-1:0]    v_out [nParallel-1:0] [ninputs-1:0] [3:0]

     , output [`F_NBITS-1:0]    final_out [ninputs-1:0]
     , output                   final_ready

     , input  [nParallel-1:0]   gates_ready
     , output [nParallel-1:0]   gates_en

     , output                   ready
     );

// sanity check
generate
    if (nCopies != (1 << nCopyBits)) begin: IErr1
        Error_do_not_override_nCopies_in_prover_compute_v_valsbank __error__();
    end
    if (nParallel != (1 << nParBits)) begin: IErr2
        Error_do_not_override_nParallel_in_prover_compute_v_valsbank __error__();
    end
endgenerate

wire [ninputs-1:0] inp_ready;
assign ready = &(inp_ready);

wire [ninputs-1:0] final_rdy;
assign final_ready = &(final_rdy);

// collect asynchronously-generated en signals
wire [nParallel-1:0] gates_en_collect [ninputs-1:0];
prover_compute_v_encollect
    #( .ninputs     (ninputs)
     , .nParallel   (nParallel)
     ) iCollect
     ( .clk         (clk)
     , .rstb        (rstb)
     , .en_master   (beta_ready)
     , .en_in       (gates_en_collect)
     , .en_out      (gates_en)
     );

genvar InputNum;
genvar ParNum;
genvar ValNum;
generate
    for (InputNum = 0; InputNum < ninputs; InputNum = InputNum + 1) begin: InputGen
        wire [`F_NBITS-1:0] in_vals_inst [nCopies-1:0];
        wire [`F_NBITS-1:0] out_inst [nParallel-1:0] [3:0];

        for (ParNum = 0; ParNum < nCopies; ParNum = ParNum + 1) begin: InHookup
            assign in_vals_inst[ParNum] = v_in[ParNum][InputNum];
        end
        for (ParNum = 0; ParNum < nParallel; ParNum = ParNum + 1) begin: OutHookup
            for (ValNum = 0; ValNum < 4; ValNum = ValNum + 1) begin: OutValHookup
                assign v_out[ParNum][InputNum][ValNum] = out_inst[ParNum][ValNum];
            end
        end

        prover_compute_v_srbank
            #( .nCopyBits   (nCopyBits)
             , .nParBits    (nParBits)
             ) iBank
             ( .clk         (clk)
             , .rstb        (rstb)
             , .en          (en)
             , .restart     (restart)
             , .tau         (tau)
             , .m_tau_p1    (m_tau_p1)
             , .in_vals     (in_vals_inst)
             , .out         (out_inst)
             , .final_out   (final_out[InputNum])
             , .final_ready (final_rdy[InputNum])
             , .gates_ready (gates_ready)
             , .gates_en    (gates_en_collect[InputNum])
             , .ready       (inp_ready[InputNum])
             , .ready_pulse ()
             );
    end
endgenerate

endmodule
`define __module_prover_compute_v_valsbank
`endif // __module_prover_compute_v_valsbank
