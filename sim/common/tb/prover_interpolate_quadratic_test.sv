// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// testbench for prover_interpolate_qc
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "prover_interpolate_quadratic.sv"

module test ();

reg clk, rstb, en, trig;
wire ready, ready_pulse;
reg [`F_NBITS-1:0] y_in [2:0];
wire [`F_NBITS-1:0] c_out [2:0];

prover_interpolate_quadratic iQuad
    ( .clk              (clk)
    , .rstb             (rstb)
    , .en               (en | trig)
    , .y_in             (y_in)
    , .c_out            (c_out)
    , .ready_pulse      (ready_pulse)
    , .ready            (ready)
    );

integer i, rseed, n_passes;
initial begin
    $dumpfile("prover_interpolate_qc_test.fst");
    $dumpvars;
    for (i = 0; i < 3; i = i + 1) begin
        $dumpvars(0, y_in[i]);
        $dumpvars(0, c_out[i]);
    end
    rseed = 1;
    randomize_yi();
    clk = 0;
    rstb = 0;
    trig = 0;
    n_passes = 0;
    en = 0;
    #1 rstb = 1;
    clk = 1;
    #1 trig = 1;
    #2 trig = 0;
    #1000 $finish;
end

`ALWAYS_FF @(posedge clk) begin
    en <= ready_pulse;
    if (ready_pulse) begin
        check_outputs();
        randomize_yi();
    end
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

task check_outputs;
    integer i, j, max;
    reg [`F_NBITS-1:0] tmp, val;
    reg [2*`F_NBITS:0] tmp2;
begin
    max = 3;
    $display("**");
    for (i = 0; i < max; i = i + 1) begin
        case (i)
            0: begin
                val = {(`F_NBITS){1'b0}};
            end

            1: begin
                val = {{(`F_NBITS-1){1'b0}},1'b1};
            end

            2: begin
                val = `F_M1;
            end
        endcase
        tmp = c_out[max - 1];
        for (j = max - 2; j >= 0; j = j - 1) begin
            tmp2 = (tmp * val) % `F_Q;
            tmp2 = (tmp2 + c_out[j]) % `F_Q;
            tmp = tmp2;
        end
        $display("%h %h %s", tmp, y_in[i], tmp == y_in[i] ? ":)" : "!!");
    end
end
endtask

task randomize_yi;
    integer i;
    reg [`F_NBITS-1:0] tmp;
begin
    for (i = 0; i < 3; i = i + 1) begin
        tmp = $random(rseed);
        tmp = {tmp[31:0], 32'b0} | $random(rseed);
        y_in[i] = tmp;
    end
    if (n_passes == 8) begin
        $finish;
    end else begin
        n_passes = n_passes + 1;
    end
end
endtask

endmodule
