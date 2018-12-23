// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// testbench for prover_adder_tree_pl
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

`include "prover_adder_tree_pl.sv"
module prover_adder_tree_pl_test ();

integer rseed;
reg [`F_NBITS-1:0] r;
localparam ngates = 13;
localparam ntagb = 10;
reg [`F_NBITS-1:0] j [(1<<ntagb)-1:0];
reg [`F_NBITS-1:0] tmp;

reg clk, rstb, trig, en, inhibit;
reg [`F_NBITS-1:0] in [ngates-1:0];
reg [ntagb-1:0] in_tag;

wire in_ready_pulse, in_ready, out_ready_pulse, out_ready, idle;
wire [`F_NBITS-1:0] out;
wire [ntagb-1:0] out_tag;

prover_adder_tree_pl
   #( .ngates           (ngates)
    , .ntagb            (ntagb)
    ) iadd_tree
    ( .clk              (clk)
    , .rstb             (rstb)
    , .en               ((en | trig) & ~inhibit)
    , .in               (in)
    , .in_tag           (in_tag)
    , .idle             (idle)
    , .in_ready_pulse   (in_ready_pulse)
    , .in_ready         (in_ready)
    , .out              (out)
    , .out_tag          (out_tag)
    , .out_ready_pulse  (out_ready_pulse)
    , .out_ready        (out_ready)
    );

initial begin
    rseed = 10000;
`ifdef SIMULATOR_IS_ICARUS
    $dumpfile("prover_adder_tree_pl_test.vcd");
    $dumpvars;
`else
    $shm_open("prover_adder_tree_pl_test.shm");
    $shm_probe("ASCM");
`endif
    in_tag = -1;
    randomize_inputs();
    clk = 0;
    rstb = 0;
    trig = 0;
    en = 0;
    inhibit = 0;
    #1 rstb = 1;
    clk = 1;
    #2 trig = 1;
    #2 trig = 0;
    #1000 inhibit = 1;
    #100 $finish;
end

`ALWAYS_FF @(posedge clk) begin
    en <= in_ready_pulse;
    if (in_ready_pulse) begin
        randomize_inputs();
    end
    if (out_ready_pulse) begin
        show_outputs();
    end
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

task randomize_inputs;
    integer i;
begin
    in_tag = in_tag + 1;
    tmp = 0;
    for (i = 0; i < ngates; i = i + 1) begin
        r = $random(rseed);
        r = {r[31:0],32'b0} | $random(rseed);
        tmp = $f_add(tmp, r);
        in[i] = r;
    end
    j[in_tag] = tmp;
end
endtask

task show_outputs;
    integer i;
begin
    $display("out[%h]: %h (%h) %s", out_tag, out, j[out_tag], out != j[out_tag] ? "!!!!!!!!!" : ":)");
    if (out != j[out_tag]) begin
        for (i = 0; i < ngates; i = i + 1) begin
            $display("%h: %h", i, in[i]);
        end
    end
end
endtask

endmodule
