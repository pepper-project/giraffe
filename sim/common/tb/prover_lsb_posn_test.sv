// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// test leastSetBitPosn function
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "func_leastSetBitPosn.sv"
`include "func_convertIntMtoL.sv"

module test ();

localparam integer npoints = 5;
localparam integer ngates = 1 << (npoints - 1);
localparam integer rnd_num = 3;
wire [npoints-1:0] rnd_wire;
assign rnd_wire = (1 << rnd_num) - 1;

wire [npoints-1:0] rn2_wire = ((1 << npoints) - 1) ^ ((1 << rnd_num) - 1);

wire [npoints:0] mask_wires [ngates-1:0];
wire [npoints:0] mask2_wires [ngates-1:0];
wire [npoints-1:0] count_wires [ngates-1:0];
reg p1_mul_en [ngates-1:0];
reg p1_use_in0_1 [ngates-1:0];
reg p1_tau_1_sel [ngates-1:0];
reg p2_mul_en [ngates-1:0];
reg add_en[ngates-1:0];
genvar G;
generate
    for (G = 0; G < ngates; G = G + 1) begin
        localparam integer lsbP = leastSetBitPosn(G, npoints - 1);
        localparam integer mask_bits = npoints - lsbP;
        assign mask_wires[G] = ((1 << (npoints + 1)) - 1) ^ ((1 << mask_bits) - 1);
        assign mask2_wires[G] = ((1 << (npoints + 1)) - 1) ^ ((1 << (mask_bits + 1)) - 1);

        localparam integer foo = convertIntMtoL(G, npoints);
        assign count_wires[G] = foo;
    end
endgenerate

integer i, j, p1_mask_bits;
initial begin
    $display("%b %b", rnd_wire, rn2_wire);
    for (i = 0; i < ngates; i++) begin
        j = leastSetBitPosn(i, npoints - 1);

        p1_mul_en[i] = &( mask_wires[i] | {rnd_wire[npoints-2:0], 2'b11} );
        p1_use_in0_1[i] = &( mask2_wires[i] | {rnd_wire[npoints-2:0], 2'b11} );

        p1_tau_1_sel[i] = |((rnd_wire ^ {rnd_wire[npoints-2:0], 1'b1}) & {1'b0, count_wires[i][npoints-1:1]});

        p2_mul_en[i] = ~|(~rn2_wire & count_wires[i]);
        add_en[i] = ~|(~rn2_wire & {1'b0, count_wires[i][npoints-1:1]});

        $display("%d | %d %d |(m) %b %b |(c) %b |(p1) %b %b |(p1_tau) %b |(p2) %b %b", j, 2 * (i & (~1 << j)), 2 * i, mask_wires[i], mask2_wires[i], count_wires[i], p1_mul_en[i], p1_use_in0_1[i], p1_tau_1_sel[i], p2_mul_en[i], add_en[i]);
    end
end

endmodule
