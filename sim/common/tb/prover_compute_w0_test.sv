// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// test for compute_w0
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "prover_compute_w0.sv"

module test ();

localparam ninbits = 8;

integer rseed, i, val_num, pass_num;
reg [`F_NBITS-1:0] w1 [ninbits-1:0], w2_m_w1 [ninbits-1:0], tau;
reg [`F_NBITS-1:0] compute_w0 [ninbits-1:0], compute_m_w0_p1 [ninbits-1:0];
reg clk, rstb, en, trig, cont;
wire [`F_NBITS-1:0] w0, m_w0_p1;
wire ready, w0_ready;
reg ready_dly;
wire ready_pulse = ready & ~ready_dly;

prover_compute_w0
    #( .ninbits     (ninbits)
     ) iW0
     ( .clk         (clk)
     , .rstb        (rstb)
     , .en          (en | trig)
     , .cont        (cont)
     , .w1          (w1)
     , .w2_m_w1     (w2_m_w1)
     , .tau         (tau)
     , .ready       (ready)
     , .w0_ready    (w0_ready)
     , .w0          (w0)
     , .m_w0_p1     (m_w0_p1)
     );

initial begin
    $dumpfile("prover_compute_w0_test.fst");
    $dumpvars;
    rseed = 3;
    en = 0;
    clk = 0;
    rstb = 0;
    trig = 0;
    pass_num = 0;
    cont = 0;
    randomize_inputs();
    #1 rstb = 1;
    clk = 1;
    #1 trig = 1;
    #2 trig = 0;
end

`ALWAYS_FF @(posedge clk) begin
    cont <= w0_ready;
    ready_dly <= ready;
    en <= ready_pulse;
    if (w0_ready & ~cont) begin
        check_outputs();
    end
    if (ready_pulse) begin
        randomize_inputs();
    end
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

task check_outputs;
begin
    $display("%h %h %s", compute_w0[val_num], w0, compute_w0[val_num] == w0 ? ":)" : "!!!!!!");
    $display("%h %h %s", compute_m_w0_p1[val_num], m_w0_p1, compute_m_w0_p1[val_num] == m_w0_p1 ? ":)" : "!!!!!!");
    val_num = val_num - 1;
end
endtask

task randomize_inputs;
    integer i;
    reg [2*`F_NBITS:0] tmp;
    reg [`F_NBITS-1:0] tmp1;
begin
    tau = random_value();
    for (i = 0; i < ninbits; i = i + 1) begin
        w1[i] = random_value();
        w2_m_w1[i] = random_value();
    end

    val_num = ninbits - 1;

    if (pass_num == 7) begin
        $finish;
    end else begin
        pass_num = pass_num + 1;
    end
    $display("**");

    /*
    if (compare != 0) begin
        for (i = 0; i < ninbits; i = i + 1) begin
            $display("%h %h %s", compute_w0[i], w0[i], compute_w0[i] == w0[i] ? ":)" : "!!!!!!");
            $display("%h %h %s", compute_m_w0_p1[i], m_w0_p1[i], compute_m_w0_p1[i] == m_w0_p1[i] ? ":)" : "!!!!!!");
        end
    end
    */

    for (i = 0; i < ninbits; i = i + 1) begin
        tmp = (w2_m_w1[i] * tau) % `F_Q;
        tmp = (tmp + w1[i]) % `F_Q;
        compute_w0[i] = tmp;
        tmp1 = ~tmp;
        tmp1 = (tmp1 + `F_Q_P2_MI) % `F_Q;
        compute_m_w0_p1[i] = tmp1;
    end
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
