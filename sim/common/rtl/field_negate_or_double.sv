// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// compute either -a or 2*a efficiently
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// When computing per-gate values of V for the sumcheck, we need V(2).
// Because of the expression for V, V(2) is either -1 * V or 2 * V. Thus,
// in each round we need to either double or negate some value.
//
// This block combines the functionality of field_negate and field_two_times
// into a single block such that it takes only one adder to perform this
// function.

`ifndef __module_field_negate_or_double
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
module field_negate_or_double
    ( input                 clk
    , input                 rstb

    , input                 en
    , input                 double
    , input  [`F_NBITS-1:0] a

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] c
    );

wire [`F_NBITS-1:0] input_a = double ? {a[`F_NBITS-2:0],1'b0} : ~a;
wire [`F_NBITS-1:0] input_b = double ? (a[`F_NBITS-1] ? `F_I : 0) : `F_Q_P1_MI;

field_adder iadd
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en)
    , .a            (input_a)
    , .b            (input_b)
    , .ready_pulse  (ready_pulse)
    , .ready        (ready)
    , .c            (c)
    );

endmodule
`define __module_field_negate_or_double
`endif // __module_field_negate_or_double
