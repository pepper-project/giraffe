// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// field arithmetic module (non-synthesizable)
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>
//
// must be linked to the "arith" VPI module
// with Icarus, you must compile with arith.sft

`ifndef __module_field_arith_ns
`include "simulator.v"
`include "field_arith_defs.v"
module field_arith_ns
   #( parameter n_cyc = 3
    , parameter cmdval = `F_MUL_CMDVAL
    , parameter dfl_out = 0
   )( input                 clk
    , input                 rstb

    , input                 en
    , input  [`F_NBITS-1:0] a
    , input  [`F_NBITS-1:0] b

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] c
    );

localparam nbits = `F_NBITS;

// this is a slightly ugly hack to enforce minimum n_cyc of 1
generate
if (n_cyc < 1) begin: IErr1
    Illegal_parameter_n_cyc_must_be_nonzero_in_field_arith __error__();
end
endgenerate
localparam dbits = $clog2(n_cyc + 1);   // need + 1 for case when dly is power of 2

// registers for sampling input values when enable is asserted
reg [nbits-1:0] a_reg;
reg [nbits-1:0] a_reg_next;
reg [nbits-1:0] b_reg;
reg [nbits-1:0] b_reg_next;
// register for output value
reg [nbits-1:0] c_reg;
reg [nbits-1:0] c_reg_next;
assign          c = c_reg;

// edge trigger for enable signal
reg             en_dly;
wire            start = en & ~en_dly;

// register for tracking number of delay cycles
reg [dbits-1:0] dly;
reg [dbits-1:0] dly_next;
wire            rdy = (dly == n_cyc) & ~start;    // we indicate ready after `n_cyc` cycles
wire            ardy = dly == (n_cyc - 1);      // almost ready triggers update of c_reg

// edge trigger for rdy_pulse signal
reg             rdy_dly;
assign          ready_pulse = rdy & ~rdy_dly;
assign          ready = rdy;

// combinational always
`ALWAYS_COMB begin
    // by default, things stay as they are
    dly_next = dly;
    a_reg_next = a_reg;
    b_reg_next = b_reg;
    c_reg_next = c_reg;

    if (start) begin    // start interrupts a previous computation
        dly_next = 0;
        a_reg_next = a;
        b_reg_next = b;
    end else if (~rdy) begin
        dly_next = dly + 1;
    end
end

// sequential always
generate
`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        dly <= n_cyc;
        a_reg <= 0;
        b_reg <= 0;
        c_reg <= dfl_out;
        en_dly <= 1;    // after reset, no add will begin until en goes low -> high
        rdy_dly <= 1;
    end else begin
        dly <= dly_next;
        a_reg <= a_reg_next;
        b_reg <= b_reg_next;
        if (cmdval == `F_MUL_CMDVAL) begin: MulInst
            c_reg <= ardy ? $f_mul(a_reg, b_reg) : c_reg;
        end else if (cmdval == `F_ADD_CMDVAL) begin: AddInst
            c_reg <= ardy ? $f_add(a_reg, b_reg) : c_reg;
        end else if (cmdval == `F_SUB_CMDVAL) begin: SubInst
            c_reg <= ardy ? $f_sub(a_reg, b_reg) : c_reg;
        end else if (cmdval == `F_HALVE_CMDVAL) begin: HalveInst
            c_reg <= ardy ? $f_halve(a_reg, b_reg) : c_reg;
        end
        en_dly <= en;
        rdy_dly <= rdy;
    end
end
endgenerate

endmodule
`define __module_field_arith_ns
`endif // __module_field_arith_ns
