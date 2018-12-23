// definitions for Icarus verilog simulator
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __include_simulator_v

`define ALWAYS_COMB always @(*)
`define ALWAYS_FF always
`define SIMULATOR_IS_ICARUS
//`define USE_PERGATE_SEQ

`ifdef SIMULATOR_IS_IUS
`undef SIMULATOR_IS_IUS
`endif // SIMULATOR_IS_IUS

`define __include_simulator_v
`endif // __include_simulator_v
