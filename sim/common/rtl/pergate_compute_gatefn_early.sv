// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// compute a given gate's function (add or mul)
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// Each gate is either an add or a multiply.
//
// This module is a common interface; add or mul is selected by a parameter.
//
// For the sake of simplicity elsewhere, we use a separate gate for each
// evaluation (V(0), V(1), and V(2)). For space savings, this could be done
// sequentially instead, with an obvious speed penalty.

`ifndef __module_pergate_compute_gatefn_early
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_multiplier.sv"
`include "gatefn_defs.v"
`include "computation_gatefn.sv"
module pergate_compute_gatefn_early
   #( parameter [`GATEFN_BITS-1:0] gate_fn = 0
   )( input                 clk
    , input                 rstb

    , input                 en
    , input                 mux_sel

    , input  [`F_NBITS-1:0] z1_chi

    , input  [`F_NBITS-1:0] in0 [3:0]
    , input  [`F_NBITS-1:0] in1 [3:0]

    , output                ready
    , output [`F_NBITS-1:0] gatefn [3:0]
    );

// control bits for shared gatefn
reg [`F_NBITS-1:0] fn_a [1:0], fn_b [1:0];
wire [`F_NBITS-1:0] mul_out [1:0];
reg [`F_NBITS-1:0] mul_reg_out[1:0];

reg [`F_NBITS-1:0] gatefn_reg [1:0], gatefn_next [1:0];
assign gatefn[0] = gatefn_reg[0];
assign gatefn[1] = gatefn_reg[1];
assign gatefn[2] = mul_out[0];
assign gatefn[3] = mul_out[1];

reg en_fn, en_fn_next;
wire [1:0] fn_ready;
wire all_fn_ready = &(fn_ready);

reg en_mul, en_mul_next;
wire [1:0] mul_ready;
wire all_mul_ready = &(mul_ready);

genvar GateNum;
generate
    for (GateNum = 0; GateNum < 2; GateNum = GateNum + 1) begin: GateFnInst
        wire [`F_NBITS-1:0] fn_out;
        computation_gatefn
           #( .gate_fn      (gate_fn)
            ) iGateFn
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (en_fn)
            , .mux_sel      (mux_sel)
            , .in0          (fn_a[GateNum])
            , .in1          (fn_b[GateNum])
            , .ready_pulse  ()
            , .ready        (fn_ready[GateNum])
            , .out          (fn_out)
            );
        field_multiplier iMul
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (en_mul)
            , .a            (fn_out)
            , .b            (z1_chi)
            , .ready_pulse  ()
            , .ready        (mul_ready[GateNum])
            , .c            (mul_out[GateNum])
            );
    end
endgenerate

// state machine
enum { ST_IDLE, ST_FN0, ST_FN1, ST_FN2 } state_reg, state_next;
wire inST_IDLE = state_reg == ST_IDLE;
assign ready = inST_IDLE & ~en;

integer InstNumC;
`ALWAYS_COMB begin
    en_fn_next = 1'b0;
    en_mul_next = 1'b0;
    gatefn_next[0] = gatefn_reg[0];
    gatefn_next[1] = gatefn_reg[1];
    state_next = state_reg;
    fn_a[0] = {(`F_NBITS){1'bX}};
    fn_a[1] = {(`F_NBITS){1'bX}};
    fn_b[0] = {(`F_NBITS){1'bX}};
    fn_b[1] = {(`F_NBITS){1'bX}};

    case (state_reg)
        ST_IDLE: begin
            if (en) begin
                en_fn_next = 1;
                state_next = ST_FN0;
            end
        end

        ST_FN0: begin
            fn_a[0] = in0[0];
            fn_b[0] = in1[0];
            fn_a[1] = in0[1];
            fn_b[1] = in1[1];
            if (all_fn_ready) begin
                en_fn_next = 1'b1;
                en_mul_next = 1'b1;
                state_next = ST_FN1;
            end
        end

        ST_FN1: begin
            fn_a[0] = in0[2];
            fn_b[0] = in1[2];
            fn_a[1] = in0[3];
            fn_b[1] = in1[3];
            if (all_fn_ready & all_mul_ready) begin
                gatefn_next[0] = mul_out[0];
                gatefn_next[1] = mul_out[1];
                en_mul_next = 1'b1;
                state_next = ST_FN2;
            end
        end

        ST_FN2: begin
            fn_a[0] = {(`F_NBITS){1'bX}};
            fn_a[1] = {(`F_NBITS){1'bX}};
            fn_b[0] = {(`F_NBITS){1'bX}};
            fn_b[1] = {(`F_NBITS){1'bX}};
            if (all_mul_ready) begin
                state_next = ST_IDLE;
            end
        end

        default: begin
            state_next = ST_IDLE;
        end
    endcase
end

integer InstNumF;
`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_fn <= 1'b0;
        en_mul <= 1'b0;
        gatefn_reg[0] <= {(`F_NBITS){1'b0}};
        gatefn_reg[1] <= {(`F_NBITS){1'b0}};
        state_reg <= ST_IDLE;
    end else begin
        en_fn <= en_fn_next;
        en_mul <= en_mul_next;
        gatefn_reg[0] <= gatefn_next[0];
        gatefn_reg[1] <= gatefn_next[1];
        state_reg <= state_next;
    end
end

endmodule
`define __module_pergate_compute_gatefn_early
`endif // __module_pergate_compute_gatefn_early
