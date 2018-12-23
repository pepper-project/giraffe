// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// sum outputs from adder tree
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_prover_compute_h_accum
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
module prover_compute_h_accum
    ( input                 clk
    , input                 rstb

    , input                 en
    , input  [`F_NBITS-1:0] in
    , input                 in_tag

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] out
    );

wire [`F_NBITS-1:0] in0 = in_tag ? out : {(`F_NBITS){1'b0}};
wire [`F_NBITS-1:0] in1 = in;

field_adder iadd
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en)
    , .a            (in0)
    , .b            (in1)
    , .ready_pulse  (ready_pulse)
    , .ready        (ready)
    , .c            (out)
    );

endmodule
`define __module_prover_compute_h_accum
`endif // __module_prover_compute_h_accum
