// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// a ring buffer of elements that can only be accessed in order
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// At several points during the sumcheck protocol, P needs to access and
// modify elements in order. A RAM would work for this, but a ring buffer
// suffices and doesn't require as much overhead.
//
// This ring buffer is simple in that the only value that can be
// overwritten is the one currently being read.

`ifndef __module_ringbuf_simple
`include "simulator.v"
module ringbuf_simple
   #( parameter nbits = 8
    , parameter nwords = 8
   )( input                 clk
    , input                 rstb

    , input                 en
    , input                 wren

    , input     [nbits-1:0] d
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

    if (en) begin
        // when wren is true, replace the value that used to be in q
        data_next[nwords-1] = wren ? d : data_reg[0];

        // everything else is just a circular shift;
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
`define __module_ringbuf_simple
`endif // __module_ringbuf_simple
