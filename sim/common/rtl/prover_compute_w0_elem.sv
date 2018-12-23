// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// compute element of w0 for next round of sumcheck from tau
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// After the sumcheck is finished, V sends one more value, tau.
// P must evaluate gamma(tau) in order to get w0 for the next round,
// where gamma(t) = (w2 - w1)*t + w1. This module computes one element of the
// vector w0.

`ifndef __module_prover_compute_w0_elem
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
`include "field_multiplier.sv"
module prover_compute_w0_elem
    ( input                 clk
    , input                 rstb

    , input                 en
    , input  [`F_NBITS-1:0] w1
    , input  [`F_NBITS-1:0] w2_m_w1
    , input  [`F_NBITS-1:0] tau

    , output                ready
    , output [`F_NBITS-1:0] w0
    , output [`F_NBITS-1:0] m_w0_p1
    );

enum { ST_IDLE, ST_ADD1_ST, ST_ADD1, ST_ADD2_ST, ST_ADD2 } state_reg, state_next;

wire first_sel = (state_reg == ST_ADD1_ST) | (state_reg == ST_ADD1);
wire start, mul_ready, add_ready;
wire [`F_NBITS-1:0] mul_out, add_out;
reg [`F_NBITS-1:0] add_out_reg, add_out_next;
assign w0 = add_out_reg;
assign m_w0_p1 = add_out;
wire [`F_NBITS-1:0] add_in0 = first_sel ? mul_out : ~add_out;
wire [`F_NBITS-1:0] add_in1 = first_sel ? w1 : `F_Q_P2_MI;
wire add_en = (state_reg == ST_ADD1_ST) | (state_reg == ST_ADD2_ST);
assign ready = mul_ready & ~start & (state_reg == ST_IDLE);

`ALWAYS_COMB begin
    state_next = state_reg;
    add_out_next = add_out_reg;

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                state_next = ST_ADD1_ST;
            end
        end

        ST_ADD1_ST, ST_ADD1: begin
            if (add_ready) begin
                add_out_next = add_out;
                state_next = ST_ADD2_ST;
            end else begin
                state_next = ST_ADD1;
            end
        end

        ST_ADD2_ST, ST_ADD2: begin
            if (add_ready) begin
                state_next = ST_IDLE;
            end else begin
                state_next = ST_ADD2;
            end
        end
    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        add_out_reg <= {(`F_NBITS){1'b0}};
        state_reg <= ST_IDLE;
    end else begin
        add_out_reg <= add_out_next;
        state_reg <= state_next;
    end
end

field_multiplier imul
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en)
    , .a            (w2_m_w1)
    , .b            (tau)
    , .ready_pulse  (start)
    , .ready        (mul_ready)
    , .c            (mul_out)
    );

field_adder iadd
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (add_en)
    , .a            (add_in0)
    , .b            (add_in1)
    , .ready_pulse  ()
    , .ready        (add_ready)
    , .c            (add_out)
    );

endmodule
`define __module_prover_compute_w0_elem
`endif // __module_prover_compute_w0_elem
