// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// collect enable pulses
// (C) Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_prover_compute_v_encollect
`include "simulator.v"
module prover_compute_v_encollect
    #( parameter                ninputs = 8
     , parameter                nParallel = 4
    )( input                    clk
     , input                    rstb

     , input                    en_master
     , input  [nParallel-1:0]   en_in [ninputs-1:0]
     , output [nParallel-1:0]   en_out
     );

reg [ninputs-1:0] en_collect_reg [nParallel-1:0];

genvar ParNum;
generate
    for (ParNum = 0; ParNum < nParallel; ParNum = ParNum + 1) begin: CollectEn
        assign en_out[ParNum] = &(en_collect_reg[ParNum]) & en_master;
    end
endgenerate

integer ParNumF;
integer InNumF;
`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        for (ParNumF = 0; ParNumF < nParallel; ParNumF = ParNumF + 1) begin
            en_collect_reg[ParNumF] <= {(ninputs){1'b0}};
        end
    end else begin
        for (ParNumF = 0; ParNumF < nParallel; ParNumF = ParNumF + 1) begin
            for (InNumF = 0; InNumF < ninputs; InNumF = InNumF + 1) begin
                if (en_out[ParNumF]) begin
                    en_collect_reg[ParNumF][InNumF] <= 1'b0;
                end else begin
                    en_collect_reg[ParNumF][InNumF] <= en_in[InNumF][ParNumF] | en_collect_reg[ParNumF][InNumF];
                end
            end
        end
    end
end

endmodule
`define __module_prover_compute_v_encollect
`endif // __module_prover_compute_v_encollect
