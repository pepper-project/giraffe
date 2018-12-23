// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// compute 1-a efficiently
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>
//
// must be linked to the "arith" VPI module
// with Icarus, you must compile with arith.sft

// Subtraction in GF(p) is slightly weird, because we have to be sure
// to prevent 2's complement wrapping. Consider the case where we want
// to compute
//   1 - x = p + 1 - x (mod p)
//
// If p is Mersenne, i.e., p = 2^k - 1, then p + 1 = 2^k.  Thus (assuming
// that x is reduced mod p),
//   1 - x = p + 1 - x (mod p)
//         = 2^k - 1 + 1 - x
//         = -x (mod 2^k)
//         = x\ + 1
// where x\ is the bitwise inverse of x (when x is represented in k bits).
//
// For example, when p = 2^3 - 1 = 7,
//   1 - 3 = -2 = 5 mod 7
//   3 = 3'b011     --> note 3 bit representation because k=3
//   3\ = 3'b100
//   3'b100 + 1 = 3'b101 = 5.
//
// This can be generalized to Crandall primes (i.e., of the form 2^k - i).
//   1 - x = p + 1 - x (mod p)
//         = 2^k - i + 1 - x
//         = -x (mod 2^k) + 1 - i
//         = x\ + 2 - i
// (This is because x\ = -x - 1 (mod 2^k).) Since we know that i > 2,
//         = x\ + p + 2 - i
// Note that p + 2 - 1 = p + 1 = 1 (mod p), so this agrees with the above
// when i=1.
//
// For example, when p = 2^4 - 3 = 13,
//   1 - 4 = -3 = 10 mod 13
//   4 = 4'b0100    --> note 4 bit representation because k=4
//   4\ = 4'b1011 = 11
//   11 + 13 + 2 - 3 = 11 + 12 = 23 = 10 mod 13
//
// The constant `F_Q_P2_MI should be set to p + 2 - i (mod p). By default,
// our prime is 2^61 - 1, so `F_Q_P2_MI = p + 1 = 1 (mod p).

`ifndef __module_field_one_minus
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
module field_one_minus
    ( input                 clk
    , input                 rstb

    , input                 en
    , input  [`F_NBITS-1:0] a

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] c
    );

wire [`F_NBITS-1:0] addend_wire = `F_Q_P2_MI;

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
`define __module_field_one_minus
`endif // __module_field_one_minus
