// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// generate pipelined adder tree
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// Since each adder has a registered inputs and outputs, a tree of these
// adders can be pumped each clock cycle. This saves substantially on
// hardware while increasing delay only slightly (2x at worst when the
// number of sums to compute is O(lg(n)), for n inputs to the adder tree.

`ifndef __module_prover_adder_tree_pl
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
module prover_adder_tree_pl
   #( parameter ngates = 8      // number of gates
    , parameter ntagb = 8
   )( input                 clk
    , input                 rstb

    , input                 en
    , input  [`F_NBITS-1:0] in [ngates-1:0]
    , input     [ntagb-1:0] in_tag

    , output                idle
    , output                in_ready_pulse
    , output                in_ready
    , output                out_ready_pulse
    , output                out_ready
    , output [`F_NBITS-1:0] out
    , output    [ntagb-1:0] out_tag
    );
`include "func_lvlNumInputs.sv"

// sanity check
generate
    if (ngates < 2) begin: IErr1
        Error_ngates_must_be_at_least_two_in_prover_adder_tree_pl __error__();
    end
    if (ntagb < 1) begin: IErr2
        Error_ntagb_must_be_at_least_one_in_prover_adder_tree_pl __error__();
    end
endgenerate

localparam nlevels = $clog2(ngates);    // number of levels of adders in the tree

// ready signals per-level
wire [nlevels-1:0] lvl_ready;
assign idle = &(lvl_ready);
// generate pulses using delayed version of ready signals
reg [nlevels-1:0] lvl_ready_dly;
wire [nlevels-1:0] lvl_ready_pulse = lvl_ready & ~lvl_ready_dly;
// input layer is ready for a new value
assign in_ready_pulse = lvl_ready_pulse[0];
assign in_ready = lvl_ready[0];
// output layer has just put out a valid value
assign out_ready_pulse = lvl_ready_pulse[nlevels-1];
assign out_ready = lvl_ready[nlevels-1];

// enable signals for the adders
wire [nlevels-1:0] lvl_en;
// each level enables the level after it with its pulse
generate
    if (nlevels > 1) begin
        assign lvl_en = {lvl_ready_pulse[nlevels-2:0],en};
    end else begin
        assign lvl_en[0] = en;
    end
endgenerate

// add_out holds outputs for each level
wire [`F_NBITS-1:0] add_out [nlevels-1:-1] [ngates-1:0];
wire [ntagb-1:0] lvl_tag [nlevels-1:-1];
// output of last level is output of the whole tree
assign out = add_out[nlevels-1][0];
assign out_tag = lvl_tag[nlevels-1];
assign lvl_tag[-1] = in_tag;

// we assign each element of the input array to an element of the add_out
// array (this lets us get away without special casing in the next generate)
genvar GateNum;
generate
    for (GateNum = 0; GateNum < ngates; GateNum = GateNum + 1) begin: AInputs
        assign add_out[-1][GateNum] = in[GateNum];
    end
endgenerate

// generate instances of the adders for the tree.
genvar Level;
generate
    for (Level = 0; Level < nlevels; Level = Level + 1) begin: TLev
        // using a constant function might seem dumb until you realize that
        // SystemVerilog does not provide for assignment to genvars except
        // in the generate looping constructs, and does not allow assignment
        // to variables at elaboration time. D'oh.
        localparam integer ni = lvlNumInputs(Level);

        // this level is ready when all gates at this level indicate ready
        wire [(ni/2)-1:0] thisl_ready;
        assign lvl_ready[Level] = &thisl_ready;

        // instances of field adders, one per pair of inputs to this level of the tree
        for (GateNum = 0; GateNum < ni / 2; GateNum = GateNum + 1) begin: TGate
            field_adder iadd
                ( .clk          (clk)
                , .rstb         (rstb)
                , .en           (lvl_en[Level])
                , .a            (add_out[Level-1][2*GateNum])
                , .b            (add_out[Level-1][2*GateNum + 1])
                , .ready_pulse  ()
                , .ready        (thisl_ready[GateNum])
                , .c            (add_out[Level][GateNum])
                );
        end

        // if this level has an odd number of inputs, add a pipeline register for the odd one
        if (ni % 2 == 1) begin: TGateOdd
            reg [`F_NBITS-1:0] thisl_oddout;
            assign add_out[Level][ni/2] = thisl_oddout;
            `ALWAYS_FF @(posedge clk or negedge rstb) begin
                if (~rstb) begin
                    thisl_oddout <= 0;
                end else begin
                    if (lvl_en[Level]) begin
                        thisl_oddout <= add_out[Level-1][ni-1];
                    end
                end
            end
        end

        // The other outputs of this level should never be used in the rest of the tree.
        // Assigning to X makes errors more obvious because Xs will propagate if referenced.
        for (GateNum = (ni / 2) + (ni % 2); GateNum < ngates; GateNum = GateNum + 1) begin: TDfl
            assign add_out[Level][GateNum] = {{(`F_NBITS){1'bX}}};
        end

        reg [ntagb-1:0] thisl_tag;
        assign lvl_tag[Level] = thisl_tag;
        `ALWAYS_FF @(posedge clk or negedge rstb) begin
            if (~rstb) begin
                thisl_tag <= 0;
            end else begin
                if (lvl_en[Level]) begin
                    thisl_tag <= lvl_tag[Level-1];
                end/* else begin
                    thisl_tag <= thisl_tag;
                end*/
            end
        end
    end
endgenerate

// generate delayed lvl_ready signals to make ready pulses
`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        lvl_ready_dly <= {(nlevels){1'b1}};
    end else begin
        lvl_ready_dly <= lvl_ready;
    end
end

endmodule
`define __module_prover_adder_tree_pl
`endif // __module_prover_adder_tree_pl
