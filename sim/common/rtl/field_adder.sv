// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// field adder module
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>
//
// must be linked to the "arith" VPI module
// with Icarus, you must compile with arith.sft

`ifndef __module_field_adder
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_arith_ns.sv"
module field_adder
    ( input                 clk
    , input                 rstb

    , input                 en
    , input  [`F_NBITS-1:0] a
    , input  [`F_NBITS-1:0] b

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] c
    );

field_arith_ns #( .n_cyc        (`F_ADD_CYCLES)
                , .cmdval       (`F_ADD_CMDVAL)
                , .dfl_out      (0)     // value at reset is 0
                ) iadd
                ( .clk          (clk)
                , .rstb         (rstb)
                , .en           (en)
                , .a            (a)
                , .b            (b)
                , .ready_pulse  (ready_pulse)
                , .ready        (ready)
                , .c            (c)
                );

endmodule
`define __module_field_adder
`endif // __module_field_adder
