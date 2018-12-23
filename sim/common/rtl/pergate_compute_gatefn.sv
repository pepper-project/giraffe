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

`ifndef __module_pergate_compute_gatefn
`include "simulator.v"
`include "field_arith_defs.v"
`include "gatefn_defs.v"
`include "computation_gatefn.sv"
module pergate_compute_gatefn
   #( parameter [`GATEFN_BITS-1:0] gate_fn = 0
    , parameter             nVals = 4
   )( input                 clk
    , input                 rstb

    , input                 en
    , input                 mux_sel
    , input  [`F_NBITS-1:0] in0 [nVals-1:0]
    , input  [`F_NBITS-1:0] in1 [nVals-1:0]

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] gatefn [nVals-1:0]
    );

// ready wires
wire [nVals-1:0] fn_ready;
assign ready = &(fn_ready);
reg ready_dly;
assign ready_pulse = ready & ~ready_dly;

genvar InstID;
generate
    for (InstID = 0; InstID < nVals; InstID = InstID + 1) begin: GFn
        computation_gatefn
           #( .gate_fn      (gate_fn)
            ) igatefn
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (en)
            , .mux_sel      (mux_sel)
            , .in0          (in0[InstID])
            , .in1          (in1[InstID])
            , .ready_pulse  ()
            , .ready        (fn_ready[InstID])
            , .out          (gatefn[InstID])
            );
    end
endgenerate

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        ready_dly <= 1;
    end else begin
        ready_dly <= ready;
    end
end

endmodule
`define __module_pergate_compute_gatefn
`endif // __module_pergate_compute_gatefn
