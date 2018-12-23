// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// Lagrange interpolation
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_lagrange_interpolate
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_multiplier.sv"
`include "prover_adder_tree_pl.sv"
`include "lagrange_coeffs.sv"
module lagrange_interpolate
   #( parameter npoints = 3
   )( input                 clk
    , input                 rstb

    , input                 en

    , input  [`F_NBITS-1:0] yi [npoints-1:0]

    , output                c_wren
    , output [`F_NBITS-1:0] c_data

    , output                ready
    , output                ready_pulse
    );
// sanity check
generate
    if (npoints < 1) begin
        Error_npoints_must_be_at_least_one __error__();
    end
endgenerate

// instantiate coefficients
wire [`F_NBITS-1:0] coeffs [npoints-1:0] [npoints-2:0];
lagrange_coeffs #( .npoints (npoints) ) icoeffs ( .coeffs (coeffs) );

localparam cntbits = $clog2(npoints);
reg [cntbits-1:0] cnt_reg, cnt_next;
reg mul_en_reg, mul_en_next;
reg add_en_reg, add_en_next;
wire [npoints-1:0] mul_ready;
wire all_mul_ready = &(mul_ready);
wire [`F_NBITS-1:0] mul_out [npoints-1:0];

genvar Gate;
generate
for (Gate = 0; Gate < npoints; Gate = Gate + 1) begin: GateGen
    field_multiplier imul
        ( .clk          (clk)
        , .rstb         (rstb)
        , .en           (mul_en_reg)
        , .a            (yi[Gate])
        , .b            (coeffs[Gate][cnt_reg])
        , .ready_pulse  ()
        , .ready        (mul_ready[Gate])
        , .c            (mul_out[Gate])
        );
end
endgenerate

reg zero_wren_reg, zero_wren_next;
wire add_tree_idle;
wire add_in_ready;
wire add_wren;
wire [`F_NBITS-1:0] add_data;
assign c_wren = zero_wren_reg | add_wren;
assign c_data = zero_wren_reg ? yi[0] : add_data;
prover_adder_tree_pl
   #( .ngates           (npoints)
    , .ntagb            (1)
    ) iadd
    ( .clk              (clk)
    , .rstb             (rstb)
    , .en               (add_en_reg)
    , .in               (mul_out)
    , .in_tag           (1'b0)
    , .idle             (add_tree_idle)
    , .in_ready_pulse   ()
    , .in_ready         (add_in_ready)
    , .out_ready_pulse  (add_wren)
    , .out_ready        ()
    , .out              (add_data)
    , .out_tag          ()
    );

reg en_dly;
wire start = en & ~en_dly;
enum { ST_IDLE, ST_CONT, ST_MUL } state_reg, state_next;
wire inST_IDLE = state_reg == ST_IDLE;
assign ready = ~start & inST_IDLE;
reg ready_dly;
assign ready_pulse = ready & ~ready_dly;

`ALWAYS_COMB begin
    cnt_next = cnt_reg;
    mul_en_next = 1'b0;
    add_en_next = 1'b0;
    zero_wren_next = 1'b0;
    state_next = state_reg;

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                state_next = ST_MUL;
                mul_en_next = 1'b1;
                zero_wren_next = 1'b1;
            end
        end

        ST_MUL: begin
            if (~mul_en_reg & all_mul_ready & add_in_ready) begin
                state_next = ST_CONT;
                add_en_next = 1'b1;
                cnt_next = cnt_reg + 1;
            end
        end

        ST_CONT: begin
            if (cnt_reg == npoints - 1) begin
                if (add_tree_idle) begin
                    cnt_next = {(cntbits){1'b0}};
                    state_next = ST_IDLE;
                end
            end else begin
                state_next = ST_MUL;
                mul_en_next = 1'b1;
            end
        end
    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        ready_dly <= 1'b1;
        cnt_reg <= {(cntbits){1'b0}};
        mul_en_reg <= 1'b0;
        add_en_reg <= 1'b0;
        zero_wren_reg <= 1'b0;
        state_reg <= ST_IDLE;
    end else begin
        en_dly <= en;
        ready_dly <= ready;
        cnt_reg <= cnt_next;
        mul_en_reg <= mul_en_next;
        add_en_reg <= add_en_next;
        zero_wren_reg <= zero_wren_next;
        state_reg <= state_next;
    end
end

endmodule
`define __module_lagrange_interpolate
`endif // __module_lagrange_interpolate
