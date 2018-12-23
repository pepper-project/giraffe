// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// per-round computation for Verifier
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

// Horner's rule evaluator for Verifier and simultaneously sums up coeffs.
//
// In "round" mode, computes f(0) + f(1) = 2*c0 + c1 + c2 (+ c3 if cubic) and
// compares to val_reg, which was the previous round's evaluation.
//
// In "layer" mode, computes v2 = sum(c_i) and H(gamma(tau)).

`ifndef __module_verifier_compute_horner
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
`include "field_multiplier.sv"
module verifier_compute_horner
   #( parameter             maxDegree = 8
// NOTE do not override below this line //
    , parameter             cBits = $clog2(maxDegree + 1)
   )( input                 clk
    , input                 rstb

    , input                 en
    , input                 restart
    , input                 cubic   // else quadratic
    , input                 round   // else layer
    , input                 next_lay    // transfer lay_out to val_reg without resetting "OK" val
    , input  [cBits-1:0]    ncoeff  // number of coeffs at this layer (ignored for round computations)

    , input  [`F_NBITS-1:0] tau
    , input  [`F_NBITS-1:0] c_in [maxDegree:0]

    , input  [`F_NBITS-1:0] val_in
    , output [`F_NBITS-1:0] val_out
    , output                ok

    , output [`F_NBITS-1:0] lay_out // only guaranteed to give useful output when round is deasserted
    , output [`F_NBITS-1:0] v2_out  // ^ ditto

    , output                ready
    );

// sanity check
generate
    if (maxDegree < 3) begin: IErr1
        Error_maxDegree_must_be_at_least_four_in_verifier_compute_horner __error__();
    end
    if (cBits != $clog2(maxDegree + 1)) begin: IErr2
        Error_do_not_override_cBits_in_verifier_compute_horner __error__();
    end
endgenerate

enum { ST_IDLE, ST_RND0_ST, ST_RND0, ST_RND1_ST, ST_RND1, ST_RND2_ST, ST_RND2, ST_FINDBL_ST, ST_FINDBL, ST_LAY0_ST, ST_LAY0, ST_LAY1_ST, ST_LAY1, ST_LAY2_ST, ST_LAY2 } state_reg, state_next;

reg en_dly;
wire start = en & ~en_dly;
assign ready = (state_reg == ST_IDLE) & ~start;

reg [cBits-1:0] count_reg, count_next;
wire [cBits-1:0] count_m1 = count_reg - 1;
wire [cBits-1:0] count_three, count_two;
generate
    if (cBits < 3) begin: CountHookupShort
        assign count_three = 2'b11;
        assign count_two = 2'b10;
    end else begin: CountHookup
        assign count_three = {{(cBits-2){1'b0}},2'b11};
        assign count_two = {{(cBits-2){1'b0}},2'b10};
    end
endgenerate

reg [`F_NBITS-1:0] val_reg, val_next, tmp_reg, tmp_next;
reg ok_reg, ok_next;
assign val_out = val_reg;
assign v2_out = tmp_reg;
assign ok = ok_reg;

wire inST_RND0_ST = state_reg == ST_RND0_ST;
wire inST_RND0 = state_reg == ST_RND0;
wire inST_RND1_ST = state_reg == ST_RND1_ST;
wire inST_RND2_ST = state_reg == ST_RND2_ST;
wire inST_FINDBL_ST = state_reg == ST_FINDBL_ST;
wire inST_LAY0_ST = state_reg == ST_LAY0_ST;
wire inST_LAY0 = state_reg == ST_LAY0;
wire inST_LAY1_ST = state_reg == ST_LAY1_ST;
wire inST_LAY2_ST = state_reg == ST_LAY2_ST;

wire add_en = inST_RND0_ST | inST_RND1_ST | inST_RND2_ST | inST_FINDBL_ST | inST_LAY0_ST | inST_LAY1_ST | inST_LAY2_ST;
wire add_ready;
reg [`F_NBITS-1:0] add_in0, add_in1;
wire [`F_NBITS-1:0] add_out;
assign lay_out = add_out;

wire mul_en = inST_RND0_ST | inST_RND1_ST | inST_LAY0_ST | inST_LAY1_ST;
wire mul_ready;
reg [`F_NBITS-1:0] mul_in0, mul_in1;
wire [`F_NBITS-1:0] mul_out;

wire lay_start = inST_LAY0 | inST_LAY0_ST;
wire rnd_start = inST_RND0 | inST_RND0_ST;

integer GNumC;
`ALWAYS_COMB begin
    state_next = state_reg;
    val_next = val_reg;
    tmp_next = tmp_reg;
    ok_next = ok_reg;
    count_next = count_reg;
    add_in0 = {(`F_NBITS){1'bX}};
    add_in1 = {(`F_NBITS){1'bX}};
    mul_in0 = {(`F_NBITS){1'bX}};
    mul_in1 = {(`F_NBITS){1'bX}};

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                if (restart) begin
                    val_next = val_in;
                    ok_next = 1'b1;
                end
                if (round) begin
                    if (next_lay) begin
                        val_next = lay_out;
                    end
                    // per-round computations
                    if (cubic) begin
                        count_next = count_three;
                    end else begin
                        count_next = count_two;
                    end
                    state_next = ST_RND0_ST;
                end else begin
                    // per-layer computations
                    count_next = ncoeff;
                    state_next = ST_LAY0_ST;
                end
            end
        end

        ST_LAY0_ST, ST_LAY0, ST_LAY1_ST, ST_LAY1: begin
            if (lay_start) begin
                add_in0 = c_in[count_reg];
                mul_in0 = c_in[count_reg];
            end else begin
                add_in0 = tmp_reg;
                mul_in0 = add_out;
            end
            add_in1 = c_in[count_m1];
            mul_in1 = tau;
            if (add_ready & mul_ready) begin
                count_next = count_m1;
                tmp_next = add_out;
                state_next = ST_LAY2_ST;
            end else begin
                if (lay_start) begin
                    state_next = ST_LAY0;
                end else begin
                    state_next = ST_LAY1;
                end
            end
        end

        ST_LAY2_ST, ST_LAY2: begin
            add_in0 = mul_out;
            add_in1 = c_in[count_reg];
            if (add_ready) begin
                if (count_reg == {(cBits){1'b0}}) begin
                    state_next = ST_IDLE;
                end else begin
                    state_next = ST_LAY1_ST;
                end
            end else begin
                state_next = ST_LAY2;
            end
        end

        ST_RND0_ST, ST_RND0, ST_RND1_ST, ST_RND1: begin
            if (rnd_start) begin
                add_in0 = c_in[count_reg];
                mul_in0 = c_in[count_reg];
            end else begin
                add_in0 = tmp_reg;
                mul_in0 = add_out;
            end
            add_in1 = (count_m1 == {(cBits){1'b0}}) ? {c_in[0][`F_NBITS-2:0],1'b0} : c_in[count_m1];
            mul_in1 = tau;
            if (add_ready & mul_ready) begin
                count_next = count_m1;
                if ((count_m1 == {(cBits){1'b0}}) & c_in[0][`F_NBITS-1]) begin
                    state_next = ST_FINDBL_ST;
                end else begin
                    tmp_next = add_out;
                    state_next = ST_RND2_ST;
                end
            end else begin
                if (rnd_start) begin
                    state_next = ST_RND0;
                end else begin
                    state_next = ST_RND1;
                end
            end
        end

        ST_RND2_ST, ST_RND2: begin
            add_in0 = mul_out;
            add_in1 = c_in[count_reg];
            if (add_ready) begin
                if (count_reg == {(cBits){1'b0}}) begin
                    if (tmp_reg != val_reg) begin
                        ok_next = 1'b0;
                    end
                    val_next = add_out;
                    state_next = ST_IDLE;
                end else begin
                    state_next = ST_RND1_ST;
                end
            end else begin
                state_next = ST_RND2;
            end
        end

        ST_FINDBL_ST, ST_FINDBL: begin
            add_in0 = add_out;
            add_in1 = `F_I;
            if (add_ready) begin
                tmp_next = add_out;
                state_next = ST_RND2_ST;
            end else begin
                state_next = ST_FINDBL;
            end
        end
    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        state_reg <= ST_IDLE;
        tmp_reg <= {(`F_NBITS){1'b0}};
        val_reg <= {(`F_NBITS){1'b0}};
        ok_reg <= 1'b0;
        count_reg <= {(cBits){1'b0}};
    end else begin
        en_dly <= en;
        state_reg <= state_next;
        tmp_reg <= tmp_next;
        val_reg <= val_next;
        ok_reg <= ok_next;
        count_reg <= count_next;
    end
end

field_multiplier iMul
    ( .clk      (clk)
    , .rstb     (rstb)
    , .en       (mul_en)
    , .a        (mul_in0)
    , .b        (mul_in1)
    , .ready_pulse ()
    , .ready    (mul_ready)
    , .c        (mul_out)
    );

field_adder iAdd
    ( .clk      (clk)
    , .rstb     (rstb)
    , .en       (add_en)
    , .a        (add_in0)
    , .b        (add_in1)
    , .ready_pulse ()
    , .ready    (add_ready)
    , .c        (add_out)
    );

endmodule
`define __module_verifier_compute_horner
`endif // __module_verifier_compute_horner
