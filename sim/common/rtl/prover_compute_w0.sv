// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// Compute w0 from tau, w2-w1, and w1
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// After the sumcheck is finished, V sends one more value, tau.
// P must evaluate gamma(tau) in order to get w0 for the next round,
// where gamma(t) = (w2 - w1)*t + w1.
//
// The prover layer stores up evaluations of w2-w1 and w1 during
// the protocol, so these inputs are available at the end.

`ifndef __module_prover_compute_w0
`include "simulator.v"
`include "field_arith_defs.v"
`include "prover_compute_w0_elem.sv"
module prover_compute_w0
   #( parameter ninbits = 3
   )( input                 clk
    , input                 rstb

    , input                 en
    , input                 cont

    , input  [`F_NBITS-1:0] w1 [ninbits-1:0]
    , input  [`F_NBITS-1:0] w2_m_w1 [ninbits-1:0]
    , input  [`F_NBITS-1:0] tau

    , output                ready
    , output                w0_ready
    , output [`F_NBITS-1:0] w0
    , output [`F_NBITS-1:0] m_w0_p1
    );

localparam nCountBits = $clog2(ninbits);
reg [nCountBits-1:0] count_reg, count_next;

enum { ST_IDLE, ST_ELEM_ST, ST_ELEM, ST_WAIT } state_reg, state_next;
reg en_dly;
wire start = en & ~en_dly;
assign ready = (state_reg == ST_IDLE) & ~start;
wire elem_ready;
wire elem_en = state_reg == ST_ELEM_ST;
assign w0_ready = ((state_reg == ST_ELEM) & elem_ready) | state_reg == ST_WAIT;

reg [`F_NBITS-1:0] w1_reg, w2_m_w1_reg;

integer GNumC;
`ALWAYS_COMB begin
    state_next = state_reg;
    count_next = count_reg;
    w1_reg = {(`F_NBITS){1'bX}};
    w2_m_w1_reg = {(`F_NBITS){1'bX}};
    for (GNumC = 0; GNumC < ninbits; GNumC = GNumC + 1) begin
        if (GNumC == count_reg) begin
            w1_reg = w1[GNumC];
            w2_m_w1_reg = w2_m_w1[GNumC];
        end
    end

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                count_next = ninbits - 1;
                state_next = ST_ELEM_ST;
            end
        end

        ST_ELEM_ST, ST_ELEM: begin
            if (elem_ready) begin
                state_next = ST_WAIT;
            end else begin
                state_next = ST_ELEM;
            end
        end

        ST_WAIT: begin
            if (cont) begin
                if (count_reg == {(nCountBits){1'b0}}) begin
                    state_next = ST_IDLE;
                end else begin
                    count_next = count_reg - 1;
                    state_next = ST_ELEM_ST;
                end
            end
        end
    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        state_reg <= ST_IDLE;
        count_reg <= {(nCountBits){1'b0}};
    end else begin
        en_dly <= en;
        state_reg <= state_next;
        count_reg <= count_next;
    end
end

prover_compute_w0_elem iw0elem
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (elem_en)
    , .w1           (w1_reg)
    , .w2_m_w1      (w2_m_w1_reg)
    , .tau          (tau)
    , .ready        (elem_ready)
    , .w0           (w0)
    , .m_w0_p1      (m_w0_p1)
    );

endmodule
`define __module_prover_compute_w0
`endif // __module_prover_compute_w0
