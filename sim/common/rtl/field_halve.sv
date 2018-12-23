// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// compute a / 2 efficiently
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

// Halving in GF(p) can be done efficiently.
//
// Let b = a / 2
// Then a = (b << 1)  mod p
//
// Two cases:
//
// (1) (b << 1) < p
//
//     In this case, no modular reduction is necessary.
//     In this case, a = b << 1, and so b = a >> 1.
//     In other words: if a is even, a / 2 = a >> 1.
//
// (2) p < (b << 1)
//
//     (note that p is strictly less than (b << 1) because
//     the former is odd, while the latter must be even before modular
//     reduction)
//
//     In this case, a = (b << 1) - p
//     Since p is odd, a must also be odd.
//     In other words: if a is odd, a / 2 = (a + p) >> 1
//
// With Mersenne primes, it's even simpler: halving is just a circular shift.
//
// We implement this in $f_halve in VPI because it can't be done in a black-box
// way with a field adder, but it can be implemented using the add circuit
// inside a field adder.

`ifndef __module_field_halve
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_arith_ns.sv"
module field_halve
    ( input                 clk
    , input                 rstb

    , input                 en
    , input  [`F_NBITS-1:0] a

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] c
    );

field_arith_ns #( .n_cyc        (`F_ADD_CYCLES)
                , .cmdval       (`F_HALVE_CMDVAL)
                , .dfl_out      (0)     // value at reset is 0
                ) ihalve
                ( .clk          (clk)
                , .rstb         (rstb)
                , .en           (en)
                , .a            (a)
                , .b            ({(`F_NBITS){1'b0}})
                , .ready_pulse  (ready_pulse)
                , .ready        (ready)
                , .c            (c)
                );

endmodule
`define __module_field_halve
`endif // __module_field_halve
