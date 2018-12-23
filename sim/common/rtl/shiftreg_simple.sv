// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// a shift register: parallel-in serial-out
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// A simple parallel-in serial-out shift register
// (where each register is multiple bits)

`ifndef __module_shiftreg_simple
`include "simulator.v"
module shiftreg_simple
   #( parameter nbits = 8
    , parameter nwords = 8
   )( input                 clk
    , input                 rstb

    , input                 wren
    , input                 shen

    , input     [nbits-1:0] d [nwords-1:0]

    , output    [nbits-1:0] q
    , output    [nbits-1:0] q_all [nwords-1:0]
    );

// make sure that the nwords parameter is reasonable
generate
    if (nwords < 2) begin: IErr1
        Illegal_parameter__nwords_must_be_at_least_2 __error__();
    end
endgenerate

reg [nbits-1:0] data_reg [nwords-1:0];
reg [nbits-1:0] data_next [nwords-1:0];
assign q = data_reg[0];
assign q_all = data_reg;

integer WordC;
`ALWAYS_COMB begin
    for (WordC = 0; WordC < nwords; WordC = WordC + 1) begin
        data_next[WordC] = data_reg[WordC];
    end

    if (wren) begin
        for (WordC = 0; WordC < nwords; WordC = WordC + 1) begin
            data_next[WordC] = d[WordC];
        end
    end else if (shen) begin
        data_next[nwords-1] = data_reg[0];
        for (WordC = 0; WordC < nwords - 1; WordC = WordC + 1) begin
            data_next[WordC] = data_reg[WordC+1];
        end
    end
end

integer WordF;
`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        for (WordF = 0; WordF < nwords; WordF = WordF + 1) begin
            data_reg[WordF] <= 0;
        end
    end else begin
        for (WordF = 0; WordF < nwords; WordF = WordF + 1) begin
            data_reg[WordF] <= data_next[WordF];
        end
    end
end

endmodule
`define __module_shiftreg_simple
`endif // __module_shiftreg_simple
