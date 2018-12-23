// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// Test of the various gyrations necessary to generate an efficient adder tree.
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

`define F_NBITS 61

module simple_adder_tree
   #( parameter ngates = 8      // number of gates
   )( input  [`F_NBITS-1:0] v_parts [ngates-1:0]
    , output [`F_NBITS-1:0] v
    );
`include "func_lvlNumInputs.sv"

localparam nlevels = $clog2(ngates);    // number of levels of adders in the tree

// declaring negative array indices: a bold move.
wire [`F_NBITS-1:0] add_out [nlevels-1:-1] [ngates-1:0];
assign v = add_out[nlevels-1][0];

genvar GateNum;
generate
    for (GateNum = 0; GateNum < ngates; GateNum = GateNum + 1) begin: AInputs
        assign add_out[-1][GateNum] = v_parts[GateNum];
    end
endgenerate

genvar Level;
generate
    for (Level = 0; Level < nlevels; Level = Level + 1) begin: TLev
        localparam integer ni = lvlNumInputs(Level);
        for (GateNum = 0; GateNum < ni / 2; GateNum = GateNum + 1) begin: TGate
            assign add_out[Level][GateNum] = add_out[Level-1][2*GateNum] + add_out[Level-1][2*GateNum + 1];
        end

        if (ni % 2 == 1) begin: TLevOdd
            assign add_out[Level][ni/2] = add_out[Level-1][ni-1];
        end

        for (GateNum = (ni / 2) + (ni % 2); GateNum < ngates; GateNum = GateNum + 1) begin: TDfl
            assign add_out[Level][GateNum] = {{(`F_NBITS){1'bX}}};
        end
    end
endgenerate

endmodule

module bar ();

integer i;
real j;
localparam ngates = 237;
reg [`F_NBITS-1:0] v_parts [ngates-1:0];
reg [31:0] r;
wire [`F_NBITS-1:0] v;

simple_adder_tree
   #( .ngates           (ngates)
    ) iadd_tree
    ( .v_parts          (v_parts)
    , .v                (v)
    );

initial begin
    j = 0;
    for (i = 0; i < ngates; i = i + 1) begin
        r = $random;
        v_parts[i] = {{(`F_NBITS-32){1'b0}},r};
        j = j + v_parts[i];
    end
end

always @(*) begin
    $display("out: %d (%f) %s", v, j, v != j ? "!!!!!!!!!" : ":)");
    if (v != j) begin
        for (i = 0; i < ngates; i = i + 1) begin
            $display("%h: %h", i, v_parts[i]);
            j = j + v_parts[i];
        end
    end
end

endmodule
