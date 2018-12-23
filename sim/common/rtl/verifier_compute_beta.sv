// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// compute beta(z2, w3) - outer state machine
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_verifier_compute_beta
`include "simulator.v"
`include "field_arith_defs.v"
`include "verifier_compute_beta_elem.sv"
module verifier_compute_beta
   #( parameter             nCopyBits = 3
    // TODO support parallel copies running at the same time?
   )( input                 clk
    , input                 rstb

    , input                 en

    , input  [`F_NBITS-1:0] w_vals [nCopyBits-1:0]
    , input  [`F_NBITS-1:0] z_vals [nCopyBits-1:0]

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

// sanity check
generate
    if (nCopyBits < 2) begin: IErr1
        Error_nCopyBits_must_be_at_least_two_in_verifier_compute_beta __error__();
    end
endgenerate

localparam nCountBits = $clog2(nCopyBits + 1);
reg [nCountBits-1:0] count_reg, count_next;

enum { ST_IDLE, ST_RUN0_ST, ST_RUN0, ST_RUN1_ST, ST_RUN1 } state_reg, state_next;

reg en_dly;
wire start = en & ~en_dly;
assign ready = (state_reg == ST_IDLE) & ~start;

wire beta_ready;
wire beta_en = (state_reg == ST_RUN0_ST) | (state_reg == ST_RUN1_ST);
wire beta_restart = (state_reg == ST_RUN0_ST) | (state_reg == ST_RUN0);

reg [`F_NBITS-1:0] w_val_sel, z_val_sel;

integer GNumC;
`ALWAYS_COMB begin
    count_next = count_reg;
    state_next = state_reg;
    w_val_sel = {(`F_NBITS){1'bX}};
    z_val_sel = {(`F_NBITS){1'bX}};
    for (GNumC = 0; GNumC < nCopyBits; GNumC = GNumC + 1) begin
        if (count_reg == GNumC) begin
            w_val_sel = w_vals[GNumC];
            z_val_sel = z_vals[GNumC];
        end
    end

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                count_next = {(nCountBits){1'b0}};
                state_next = ST_RUN0_ST;
            end
        end

        ST_RUN0_ST, ST_RUN0: begin
            if (beta_ready) begin
                count_next = count_reg + 1'b1;
                state_next = ST_RUN1_ST;
            end else begin
                state_next = ST_RUN0;
            end
        end

        ST_RUN1_ST, ST_RUN1: begin
            if (beta_ready) begin
                count_next = count_reg + 1'b1;
                if (count_reg == nCopyBits - 1) begin
                    state_next = ST_IDLE;
                end else begin
                    state_next = ST_RUN1_ST;
                end
            end else begin
                state_next = ST_RUN1;
            end
        end
    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        count_reg <= {(nCountBits){1'b0}};
        state_reg <= ST_IDLE;
    end else begin
        en_dly <= en;
        count_reg <= count_next;
        state_reg <= state_next;
    end
end

wire [`F_NBITS-1:0] mul_beta_zeros [1:0];
assign mul_beta_zeros[0] = {(`F_NBITS){1'b0}};
assign mul_beta_zeros[1] = {(`F_NBITS){1'b0}};
verifier_compute_beta_elem iBeta
    ( .clk              (clk)
    , .rstb             (rstb)
    , .en               (beta_en)
    , .restart          (beta_restart)
    , .mul_beta         (1'b0)
    , .w_val            (w_val_sel)
    , .z_val            (z_val_sel)
    , .mul_beta_in      (mul_beta_zeros)
    , .add_en_ext       (add_en_ext)
    , .add_in_ext       (add_in_ext)
    , .add_out_ext      (add_out_ext)
    , .add_ready_ext    (add_ready_ext)
    , .mul_en_ext       (mul_en_ext)
    , .mul_in_ext       (mul_in_ext)
    , .mul_out_ext      (mul_out_ext)
    , .mul_ready_ext    (mul_ready_ext)
    , .ready            (beta_ready)
    , .beta_out         (beta_out)
    );

endmodule
`define __module_verifier_compute_beta
`endif // __module_verifier_compute_beta
