// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// mux for inputs to compute_h multipliers
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_prover_compute_h_parmux
`include "simulator.v"
`include "field_arith_defs.v"
module prover_compute_h_parmux
    #( parameter                nInputs = 2
// NOTE do not change parameters below this line! //
     , parameter                nInBits = $clog2(nInputs)
    )( input  [`F_NBITS-1:0]    vals_in [nInputs-1:0]
     , input  [nInBits-1:0]     count_in

     , output [`F_NBITS-1:0]    val_out
     );

// sanity check
generate
    if (nInputs < 2) begin: IErr1
        Error_nInputs_must_be_at_least_2_in_prover_compute_h_parmux __error__();
    end
    if (nInBits != $clog2(nInputs)) begin: IErr3
        Error_do_not_override_nInBits_in_prover_compute_h_parmux __error__();
    end
endgenerate

integer InputNum;
reg [`F_NBITS-1:0] val_out_reg;
assign val_out = val_out_reg;
`ALWAYS_COMB begin
    val_out_reg = {(`F_NBITS){1'bz}};

    for (InputNum = 0; InputNum < nInputs; InputNum = InputNum + 1) begin: MuxGen
        if (count_in == InputNum) begin
            val_out_reg = vals_in[InputNum];
        end
    end
end

endmodule
`define __module_prover_compute_h_parmux
`endif // __module_prover_compute_h_parmux
