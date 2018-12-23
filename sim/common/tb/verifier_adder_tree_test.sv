// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// testbench for verifier_adder_tree
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

`include "verifier_adder_tree.sv"
module verifier_adder_tree_test ();

integer rseed;
reg [`F_NBITS-1:0] r, j;
localparam ngates = 35;

reg clk, rstb, trig, en;
reg [`F_NBITS-1:0] v_parts [ngates-1:0];
wire ready_pulse, ready;
wire [`F_NBITS-1:0] v;

verifier_adder_tree
   #( .ngates       (ngates)
    ) iadd_tree
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en | trig)
    , .v_parts      (v_parts)
    , .ready_pulse  (ready_pulse)
    , .ready        (ready)
    , .v            (v)
    );

initial begin
    rseed = 1000;
    $dumpfile("verifier_adder_tree_test.fst");
    $dumpvars;
    randomize_inputs();
    clk = 0;
    rstb = 0;
    trig = 0;
    en = 0;
    #1 rstb = 1;
    clk = 1;
    #3 trig = 1;
    #2 trig = 0;
    #3000 $finish;
end

`ALWAYS_FF @(posedge clk) begin
    en <= ready_pulse;
    if (ready_pulse) begin
        show_outputs();
        randomize_inputs();
    end
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

task randomize_inputs;
    integer i;
begin
    j = 0;
    for (i = 0; i < ngates; i = i + 1) begin
        r = $random(rseed);
        r = {r[31:0],32'b0} | $random(rseed);
        j = $f_add(j, r);
        v_parts[i] = r;
    end
end
endtask

task show_outputs;
    integer i;
begin
    $display("out: %h (%h) %s", v, j, v != j ? "!!!!!!!!!" : ":)");
    if (v != j) begin
        for (i = 0; i < ngates; i = i + 1) begin
            $display("%h: %h", i, v_parts[i]);
        end
    end
end
endtask

endmodule
