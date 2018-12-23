// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// a shift register element with bypass and normal inputs
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_prover_compute_v_srelem
`include "simulator.v"
`include "field_arith_defs.v"
module prover_compute_v_srelem
    ( input                 clk
    , input                 rstb

    , input                 en
    , input                 load
    , input                 bypass
    , input  [`F_NBITS-1:0] in_normal
    , input  [`F_NBITS-1:0] in_load
    , input  [`F_NBITS-1:0] in_bypass

    , output [`F_NBITS-1:0] out
    );

reg [`F_NBITS-1:0] out_reg, out_next;
assign out = out_reg;

`ALWAYS_COMB begin
    out_next = out_reg;

    if (en) begin
        if (load) begin
            out_next = in_load;
        end else if (bypass) begin
            out_next = in_bypass;
        end else begin
            out_next = in_normal;
        end
    end
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        out_reg <= {(`F_NBITS){1'b0}};
    end else begin
        out_reg <= out_next;
    end
end

endmodule
`define __module_prover_compute_v_srelem
`endif // __module_prover_compute_v_srelem
