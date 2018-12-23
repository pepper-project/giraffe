// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// collect enable pulses testbench
// (C) Riad S. Wahby <rsw@cs.nyu.edu>

`include "prover_compute_v_encollect.sv"

module test ();

integer rseed, i;
localparam nParallel = 16;
localparam ninputs = 8;

reg clk, rstb;

reg [nParallel-1:0] en_in [ninputs-1:0];
wire [nParallel-1:0] en_out;

prover_compute_v_encollect
    #( .ninputs     (ninputs)
     , .nParallel   (nParallel)
     ) iCollect
     ( .clk         (clk)
     , .rstb        (rstb)
     , .en_in       (en_in)
     , .en_out      (en_out)
     );

initial begin
    $dumpfile("prover_compute_v_encollect_test.fst");
    $dumpvars;
    for (i = 0; i < ninputs; i = i + 1) begin
        $dumpvars(0, en_in[i]);
    end
    rseed = 3;
    randomize_inputs();
    clk = 0;
    rstb = 0;
    #1 rstb = 1;
    clk = 1;
    #1000 $finish;
end

`ALWAYS_FF @(posedge clk) begin
    randomize_inputs();
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

task randomize_inputs;
    integer i;
    reg [nParallel-1:0] tmp;
begin
    for (i = 0; i < ninputs; i = i + 1) begin
        tmp = $random(rseed);
        en_in[i] = tmp;
    end
end
endtask

endmodule
