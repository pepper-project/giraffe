// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// element of computing beta(z2, w3) (minimum parallelism)
// (C) Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_verifier_compute_beta_elem
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
`include "field_multiplier.sv"
module verifier_compute_beta_elem
    ( input                 clk
    , input                 rstb

    , input                 en
    , input                 restart
    , input                 mul_beta

    , input  [`F_NBITS-1:0] w_val
    , input  [`F_NBITS-1:0] z_val

    , input  [`F_NBITS-1:0] mul_beta_in [1:0]

    , input                 add_en_ext
    , input  [`F_NBITS-1:0] add_in_ext [1:0]
    , output [`F_NBITS-1:0] add_out_ext
    , output                add_ready_ext

    , input                 mul_en_ext
    , input  [`F_NBITS-1:0] mul_in_ext [1:0]
    , output [`F_NBITS-1:0] mul_out_ext
    , output                mul_ready_ext

    , output                ready
    , output [`F_NBITS-1:0] beta_out
    );

reg [`F_NBITS-1:0] add_in0, add_in1, mul_in0, mul_in1;
wire [`F_NBITS-1:0] add_out, mul_out;
wire add_ready, mul_ready;
reg [`F_NBITS-1:0] beta_reg, beta_next;
assign beta_out = beta_reg;

assign mul_out_ext = mul_out;
assign mul_ready_ext = mul_ready;
assign add_out_ext = add_out;
assign add_ready_ext = add_ready;

enum { ST_IDLE, ST_DBL_ST, ST_DBL, ST_MULADD_ST, ST_MULADD, ST_1M_ST, ST_1M, ST_ADD_ST, ST_ADD, ST_MUL_ST, ST_MUL, ST_MULBETA_ST, ST_MULBETA } state_reg, state_next;
reg en_dly;
wire start = en & ~en_dly;
assign ready = (state_reg == ST_IDLE) & ~start;

wire inST_DBL_ST = state_reg == ST_DBL_ST;
wire inST_MULADD_ST = state_reg == ST_MULADD_ST;
wire inST_1M_ST = state_reg == ST_1M_ST;
wire inST_ADD_ST = state_reg == ST_ADD_ST;
wire inST_MUL_ST = state_reg == ST_MUL_ST;
wire inST_MULBETA_ST = state_reg == ST_MULBETA_ST;

wire add_en = inST_DBL_ST | inST_MULADD_ST | inST_1M_ST | inST_ADD_ST | add_en_ext;
wire mul_en = inST_MULADD_ST | inST_MUL_ST | inST_MULBETA_ST | mul_en_ext;

`ALWAYS_COMB begin
    state_next = state_reg;
    beta_next = beta_reg;
    add_in0 = add_in_ext[0];
    add_in1 = add_in_ext[1];
    mul_in0 = mul_in_ext[0];
    mul_in1 = mul_in_ext[1];

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                if (restart) begin
                    beta_next = {{(`F_NBITS-1){1'b0}},1'b1};
                end
                if (mul_beta) begin
                    state_next = ST_MULBETA_ST;
                end else if (w_val[`F_NBITS-1]) begin
                    state_next = ST_DBL_ST;
                end else begin
                    // if the MSB of w_val is 0, we can double it for free
                    state_next = ST_MULADD_ST;
                end
            end
        end

        ST_DBL_ST, ST_DBL: begin
            // don't need to check MSB because we would've skipped this state if it weren't set
            add_in0 = {w_val[`F_NBITS-2:0],1'b0};       // 2 * w
            add_in1 = `F_I;
            if (add_ready) begin
                state_next = ST_MULADD_ST;
            end else begin
                state_next = ST_DBL;
            end
        end

        ST_MULADD_ST, ST_MULADD: begin
            mul_in0 = z_val;                            // 2 * w * z
            mul_in1 = w_val[`F_NBITS-1] ? add_out : {w_val[`F_NBITS-2:0],1'b0};
            add_in0 = w_val;                            // w + z
            add_in1 = z_val;
            if (add_ready) begin
                // don't wait for mul here because we don't need result until after next computation
                state_next = ST_1M_ST;
            end else begin
                state_next = ST_MULADD;
            end
        end

        ST_1M_ST, ST_1M: begin
            add_in0 = ~add_out;                         // 1 - (w + z)
            add_in1 = `F_Q_P2_MI;
            if (mul_ready & add_ready) begin
                state_next = ST_ADD_ST;
            end else begin
                state_next = ST_1M;
            end
        end

        ST_ADD_ST, ST_ADD: begin
            add_in0 = add_out;                          // 2 * w * z + 1 - (w + z)
            add_in1 = mul_out;
            if (add_ready) begin
                if (beta_reg == {{(`F_NBITS-1){1'b0}},1'b1}) begin
                    // no need to multiply if beta_reg == 1
                    beta_next = add_out;
                    state_next = ST_IDLE;
                end else begin
                    state_next = ST_MUL_ST;
                end
            end else begin
                state_next = ST_ADD;
            end
        end

        ST_MUL_ST, ST_MUL: begin
            mul_in0 = beta_reg;
            mul_in1 = add_out;
            if (mul_ready) begin
                beta_next = mul_out;
                state_next = ST_IDLE;
            end else begin
                state_next = ST_MUL;
            end
        end

        ST_MULBETA_ST, ST_MULBETA: begin
            mul_in0 = mul_beta_in[0];
            mul_in1 = mul_beta_in[1];
            if (mul_ready) begin
                beta_next = mul_out;
                state_next = ST_IDLE;
            end else begin
                state_next = ST_MULBETA;
            end
        end
    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        state_reg <= ST_IDLE;
        beta_reg <= {(`F_NBITS){1'b0}};
    end else begin
        en_dly <= en;
        state_reg <= state_next;
        beta_reg <= beta_next;
    end
end

field_adder iAdd
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (add_en)
    , .a            (add_in0)
    , .b            (add_in1)
    , .ready_pulse  ()
    , .ready        (add_ready)
    , .c            (add_out)
    );

field_multiplier iMul
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (mul_en)
    , .a            (mul_in0)
    , .b            (mul_in1)
    , .ready_pulse  ()
    , .ready        (mul_ready)
    , .c            (mul_out)
    );

endmodule
`define __module_verifier_compute_beta_elem
`endif // __module_verifier_compute_beta_elem
