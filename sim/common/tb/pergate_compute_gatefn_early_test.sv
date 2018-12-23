// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// test
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "pergate_compute_gatefn_early.sv"

module test ();

integer rseed, i;
reg clk, rstb, en, trig, ready_dly;
wire ready_pulse = ready & ~ready_dly;
reg [`F_NBITS-1:0] z1_chi, in0 [3:0], in1 [3:0];
wire ready;
wire [`F_NBITS-1:0] out [3:0];

pergate_compute_gatefn_early
    #( .gate_fn     (`GATEFN_MUL)
     ) iFn
     ( .clk         (clk)
     , .rstb        (rstb)
     , .en          (en | trig)
     , .mux_sel     (1'b0)
     , .z1_chi      (z1_chi)
     , .in0         (in0)
     , .in1         (in1)
     , .ready       (ready)
     , .gatefn      (out)
     );

initial begin
    $dumpfile("pergate_compute_gatefn_early_test.fst");
    $dumpvars;
    for (i = 0; i < 4; i = i + 1) begin
        $dumpvars(0, in0[i], in1[i]);
    end
    rseed = 0;
    clk = 0;
    trig = 0;
    en = 0;
    rstb = 0;
    randomize_inputs(0);
    #1 rstb = 1;
    trig = 1;
    #1 clk = 1;
    #1 trig = 0;
    #1000 $finish;
end

`ALWAYS_FF @(posedge clk) begin
    ready_dly <= ready;
    en <= ready_pulse;
    if (ready_pulse) begin
        randomize_inputs(1);
    end
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

task randomize_inputs;
    input do_comp;
    integer do_comp, i;
    reg [`F_NBITS-1:0] tmp;
begin
    $display("**");
    for (i = 0; i < 4; i = i + 1) begin
        if (do_comp == 1) begin
            tmp = $f_mul(in0[i], in1[i]);
            tmp = $f_mul(tmp, z1_chi);
            $display("%h %h %s", tmp, out[i], tmp == out[i] ? ":)" : "!!!!!!");
        end

        in0[i] = random_value();
        in1[i] = random_value();
    end
    z1_chi = random_value();
end
endtask

function [`F_NBITS-1:0] random_value();
    reg [`F_NBITS-1:0] tmp;
begin
    tmp = $random(rseed);
    tmp = {tmp[31:0],32'b0} | $random(rseed);
    random_value = tmp;
end
endfunction

endmodule
