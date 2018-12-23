// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// testbench for field_halve
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "field_halve.sv"
`include "field_multiplier.sv"

module field_halve_test ();

integer rseed;
reg [`F_NBITS-1:0] tau;
wire halve_ready, mul_ready;
wire ready = halve_ready & mul_ready;
reg ready_dly;
wire ready_pulse = ready & ~ready_dly;
reg clk, rstb, en, trig;
wire [`F_NBITS-1:0] halve_out, mul_out;

field_halve ihalve
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en | trig)
    , .a            (tau)
    , .ready_pulse  ()
    , .ready        (halve_ready)
    , .c            (halve_out)
    );

field_multiplier imul
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en | trig)
    , .a            (tau)
    , .b            (`F_HALF)
    , .ready_pulse  ()
    , .ready        (mul_ready)
    , .c            (mul_out)
    );

initial begin
    $dumpfile("field_halve_test.fst");
    $dumpvars;
    rseed = 1;
    clk = 0;
    rstb = 0;
    trig = 0;
    en = 0;
    #1 rstb = 1;
    clk = 1;
    randomize_tau();
    #2 trig = 1;
    #2 trig = 0;
    #1000 $finish;
end

`ALWAYS_FF @(posedge clk) begin
    ready_dly <= ready;
    en <= ready_pulse;
    if (ready_pulse) begin
        randomize_tau();
    end
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

task randomize_tau;
begin
    if (ready_pulse) begin
        $display("%h %h %s", halve_out, mul_out, halve_out == mul_out ? ":)" : "!!!!!!");
    end
    tau = $random(rseed);
    tau = {tau[31:0], 32'b0} | $random(rseed);
end
endtask

endmodule
