// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// shuffle element for prover_shuffle_v
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_prover_shuffle_v_elem
`include "simulator.v"
`include "field_arith_defs.v"
module prover_shuffle_v_elem
    ( input  [`F_NBITS-1:0] in_act
    , input  [`F_NBITS-1:0] in_nact_0
    , input  [`F_NBITS-1:0] in_nact_1

    , input                 act

    , output [`F_NBITS-1:0] out_0
    , output [`F_NBITS-1:0] out_1
    );

assign out_0 = act ? in_act : in_nact_0;
assign out_1 = act ? in_act : in_nact_1;

endmodule
`define __module_prover_shuffle_v_elem
`endif // __module_prover_shuffle_v_elem
