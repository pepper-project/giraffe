// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// field subtraction: first negate, then add
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// This module combines the functionality of field_negate
// and field_add, reusing the same adder to do both functions.

`ifndef __module_field_subtract
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
module field_subtract
    ( input                 clk
    , input                 rstb

    , input                 en
    , input  [`F_NBITS-1:0] a
    , input  [`F_NBITS-1:0] b

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] c
    );

// edge detect for enable
reg en_dly;
wire start = en & ~en_dly;

// start the second adder cycle
wire add_ready_pulse;
wire add_ready;
reg add_ready_pulse_dly;

// where are we in the computation?
reg state_reg;

// wires for adder
wire en_add = state_reg ? add_ready_pulse_dly : start;

// ready wires
assign ready = ~state_reg & add_ready;
reg ready_dly;
assign ready_pulse = ready & ~ready_dly;

// next up?
wire state_next = state_reg ? (add_ready_pulse_dly ? 0 : 1) : (start ? 1 : 0);

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1;
        add_ready_pulse_dly <= 0;
        ready_dly <= 1;
        state_reg <= 0;
    end else begin
        en_dly <= en;
        add_ready_pulse_dly <= add_ready_pulse;
        ready_dly <= ready;
        state_reg <= state_next;
    end
end

wire [`F_NBITS-1:0] addend_a = state_reg ? `F_Q_P1_MI : a;
wire [`F_NBITS-1:0] addend_b = state_reg ? c : (~b);

field_adder iadd
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en_add)
    , .a            (addend_a)
    , .b            (addend_b)
    , .ready_pulse  (add_ready_pulse)
    , .ready        (add_ready)
    , .c            (c)
    );

endmodule
`define __module_field_subtract
`endif // __module_field_subtract
