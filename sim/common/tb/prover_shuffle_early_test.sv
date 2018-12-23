// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// testbench for prover_shuffle_early
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "prover_shuffle_early.sv"

module prover_shuffle_early_test ();

localparam nValBits = 4;
localparam nParBits = 1;
localparam nValues = 1 << nValBits;

integer rseed, i;
reg clk, rstb, en, trig, restart;
wire ready, ready_pulse;
reg [`F_NBITS-1:0] v_in [nValues-1:0];
wire [`F_NBITS-1:0] v_out [nValues-1:0];

prover_shuffle_early
   #( .nValBits     (nValBits)
    , .nParBits     (nParBits)
    ) ishuffle
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en | trig)
    , .restart      (trig | restart)
    , .vals_in      (v_in)
    , .vals_out     (v_out)
    , .ready        (ready)
    , .ready_pulse  (ready_pulse)
    );

initial begin
`ifdef SIMULATOR_IS_ICARUS
    $dumpfile("prover_shuffle_early_test.fst");
    $dumpvars;
    for (i = 0; i < nValues; i = i + 1) begin
        $dumpvars(0, ishuffle.vals_in[i]);
    end
    for (i = 0; i < nValues; i = i + 1) begin
        $dumpvars(0, v_out[i]);
    end
`else
    $shm_open("prover_shuffle_v_test.shm");
    $shm_probe("ASCM");
`endif
    rseed = 1;
    set_inputs();
    clk = 0;
    rstb = 0;
    trig = 0;
    restart = 0;
    en = 0;
    #1 rstb = 1;
    clk = 1;
    #1 trig = 1;
    #2 trig = 0;
    //#100 trig = 1;
    //#2 trig = 0;
    #20 restart = 1;
    #4 restart = 0;
    #20 $finish;
end

`ALWAYS_FF @(posedge clk) begin
    en <= ready_pulse;
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

task set_inputs;
begin
    for (i = 0; i < nValues; i = i + 1) begin
        v_in[i] = i;
    end
end
endtask

task randomize_inputs;
begin
    for (i = 0; i < nValues; i = i + 1) begin
        v_in[i] = $random(rseed);
        v_in[i] = {v_in[i][31:0],32'b0} | $random(rseed);
    end
end
endtask

endmodule
