// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// shuffle beta values in prover_compute_v_early
//   NOTE: for synthesizability, one might want to pipeline this block!
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_prover_shuffle_early
`include "simulator.v"
`include "field_arith_defs.v"
module prover_shuffle_early
   #( parameter             nValBits = 3
    , parameter             nParBits = 1
// NOTE do not override below this line //
    , parameter             nValues = 1 << nValBits
   )( input                 clk
    , input                 rstb

    , input                 en
    , input                 restart

    , input  [`F_NBITS-1:0] vals_in [nValues-1:0]

    , output [`F_NBITS-1:0] vals_out [nValues-1:0]

    , output                ready
    , output                ready_pulse
    );

// sanity check
generate
    if (nValues != (1 << nValBits)) begin: IErr1
        Error_do_not_override_nValues_in_prover_shuffle_early __error__();
    end
    if (nParBits < 1) begin: IErr2
        Error_nParBits_must_be_at_least_1_in_prover_shuffle_early __error__();
    end
    if (nValBits <= nParBits) begin: IErr3
        Error_nValBits_must_be_greater_than_nParBits_in_prover_shuffle_early __error__();
    end
endgenerate
localparam nValBitsPer = nValBits - nParBits;
localparam nValsPer = 1 << nValBitsPer;
localparam nParallel = 1 << nParBits;

wire [`F_NBITS-1:0] vals_lay [nValBitsPer:0] [nParallel-1:0] [nValsPer-1:0];
wire [`F_NBITS-1:0] vals_lm [nValBitsPer:0] [nValues-1:0];
reg [`F_NBITS-1:0] vals_out_reg [nValues-1:0];
assign vals_out = vals_out_reg;
genvar LayNum;
genvar ParNum;
genvar ValNum;
generate
    for (ParNum = 0; ParNum < nParallel; ParNum = ParNum + 1) begin: InitHookup
        localparam nOffset = ParNum * nValsPer;
        for (ValNum = 0; ValNum < nValsPer; ValNum = ValNum + 1) begin: InitValHookup
            assign vals_lay[0][ParNum][ValNum] = vals_in[nOffset + ValNum];
        end
    end
    for (LayNum = 1; LayNum < nValBitsPer + 1; LayNum = LayNum + 1) begin: LayHookup
        for (ParNum = 0; ParNum < nParallel / 2; ParNum = ParNum + 1) begin: LayParHookup
            localparam nSkip = nValsPer >> LayNum;
            for (ValNum = 0; ValNum < nSkip; ValNum = ValNum + 1) begin: LayValHookup
                assign vals_lay[LayNum][2*ParNum][ValNum] = vals_lay[LayNum-1][ParNum][ValNum];
                assign vals_lay[LayNum][2*ParNum+1][ValNum] = vals_lay[LayNum-1][ParNum][ValNum+nSkip];
            end
            for (ValNum = nSkip; ValNum < nValsPer; ValNum = ValNum + 1) begin: LayValDummyHookup
                assign vals_lay[LayNum][2*ParNum][ValNum] = {(`F_NBITS){1'b0}};
                assign vals_lay[LayNum][2*ParNum+1][ValNum] = {(`F_NBITS){1'b0}};
            end
        end
    end
    for (LayNum = 0; LayNum < nValBitsPer + 1; LayNum = LayNum + 1) begin: LayLMHookup
        for (ParNum = 0; ParNum < nParallel; ParNum = ParNum + 1) begin: LayLMParHookup
            localparam nOffset = ParNum * nValsPer;
            for (ValNum = 0; ValNum < nValsPer; ValNum = ValNum + 1) begin: LayLMValHookup
                assign vals_lm[LayNum][nOffset+ValNum] = vals_lay[LayNum][ParNum][ValNum];
            end
        end
    end
endgenerate

reg [nValBitsPer:0] count_reg, count_next;
generate
endgenerate
reg en_dly, ready_dly;
wire start = en & ~en_dly;
assign ready = ~start;
assign ready_pulse = ready & ~ready_dly;

integer GNumC, CNumC;
`ALWAYS_COMB begin
    for (CNumC = 0; CNumC < nValBitsPer + 1; CNumC = CNumC + 1) begin
        if (count_reg[CNumC]) begin
            for (GNumC = 0; GNumC < nValues; GNumC = GNumC + 1) begin
                vals_out_reg[GNumC] = vals_lm[CNumC][GNumC];
            end
        end
    end

    count_next = count_reg;
    if (start) begin
        if (restart) begin
            count_next = 1;
        end else if (count_reg != {1'b1,{(nValBitsPer){1'b0}}}) begin
            count_next = {count_reg[nValBitsPer-1:0],1'b0};
        end
    end
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        ready_dly <= 1'b1;
        count_reg <= 1;
    end else begin
        en_dly <= en;
        ready_dly <= ready;
        count_reg <= count_next;
    end
end

endmodule
`define __module_prover_shuffle_early
`endif // __module_prover_shuffle_early
