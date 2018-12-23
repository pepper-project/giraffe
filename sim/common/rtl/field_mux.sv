// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// a mux
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_field_mux
`include "simulator.v"
`include "field_arith_defs.v"
module field_mux
    ( input                 clk
    , input                 rstb

    , input                 en
    , input                 sel
    , input  [`F_NBITS-1:0] a       // selected when ~sel
    , input  [`F_NBITS-1:0] b       // selected when sel


    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] c
    );

// needs to be edge triggered like add, sub, mul
reg en_dly;
wire start = en & ~en_dly;

// ready wires
assign ready = ~start;
reg ready_dly;
assign ready_pulse = ready & ~ready_dly;

// output register
reg [`F_NBITS-1:0] c_reg;
assign c = c_reg;

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1;
        ready_dly <= 1;
        c_reg <= 0;
    end else begin
        en_dly <= en;
        ready_dly <= ready;
        if (start) begin
            c_reg <= sel ? b : a;
        end
    end
end

endmodule
`define __module_field_mux
`endif // __module_field_mux
