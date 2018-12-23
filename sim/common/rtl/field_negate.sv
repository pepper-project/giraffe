// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// compute -a efficiently
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>
//
// must be linked to the "arith" VPI module
// with Icarus, you must compile with arith.sft

// Negation in GF(p) can be computed efficiently.
//
// We know that
//   -x = p - x (mod p)
// If p is a Crandall prime, i.e., p = 2^k - i, then
//   -x = 2^k - i - x (mod p)
//      = -x (mod 2^k) - i
//      = x\ + 1 - i
// Where x\ is the bitwise inverse of x. (This is because
// x\ = -x - 1 (mod 2^k).)
//
// Thus, when p is Mersenne (i.e., i = 1), -x is just x\ (mod p).
// When i > 2, -x = x\ + 1 + p - i.
//
// Thus, for Mersenne primes, this can be even simpler:
// Check for a == p or a == 0, and output 0; otherwise,
// output the bitwise inverse of a. (In that case, don't
// forget to generate ready and ready_pulse!)

`ifndef __module_field_negate
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
module field_negate
    ( input                 clk
    , input                 rstb

    , input                 en
    , input  [`F_NBITS-1:0] a

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] c
    );

wire [`F_NBITS-1:0] addend_wire = `F_Q_P1_MI;

field_adder iadd
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en)
    , .a            (~a)
    , .b            (addend_wire)
    , .ready_pulse  (ready_pulse)
    , .ready        (ready)
    , .c            (c)
    );

endmodule
`define __module_field_negate
`endif // __module_field_negate
