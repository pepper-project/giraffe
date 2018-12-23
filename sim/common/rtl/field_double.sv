// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// compute 2*a efficiently
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>
//
// must be linked to the "arith" VPI module
// with Icarus, you must compile with arith.sft

// Doubling in GF(p) can be done efficiently when p is a Crandall (or
// Mersenne) prime, i.e., p = 2^k - i.
//
// Define
//   a' = a<<1 truncated to k bits
//   b' = the most significant bit of a
// Then
//   2*a = a' + b' * i (mod p)

`ifndef __module_field_double
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
module field_double
    ( input                 clk
    , input                 rstb

    , input                 en
    , input  [`F_NBITS-1:0] a

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] c
    );

// if b' == 1, `F_I, otherwise 0
wire [`F_NBITS-1:0] addend_wire = a[`F_NBITS-1] ? `F_I : 0;

field_adder iadd
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en)
    , .a            ({a[`F_NBITS-2:0],1'b0})
    , .b            (addend_wire)
    , .ready_pulse  (ready_pulse)
    , .ready        (ready)
    , .c            (c)
    );

endmodule
`define __module_field_double
`endif // __module_field_double
