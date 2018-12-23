// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// testbench for prover_compute_v_sr
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "prover_compute_v_sr.sv" 

module prover_compute_v_sr_test ();

localparam nCopyBits = 4;
localparam nCopies = 1 << nCopyBits;
localparam nEvenOdd = 1 << (nCopyBits - 1);
localparam posParallel = 0;
localparam totParallel = 4;
localparam lastRoundNum = nCopyBits + $clog2(totParallel) + 2;

integer val_count, round_count, trip_count;
integer rseed, i;
reg clk, rstb, en, trig;
reg restart;
reg [`F_NBITS-1:0] in_vals [nCopies-1:0];
reg [`F_NBITS-1:0] tau, m_tau_p1;
reg [`F_NBITS-1:0] even_in, odd_in;
wire [`F_NBITS-1:0] out [3:0];

reg [`F_NBITS-1:0] chi_compute [nCopies-1:0];
reg [`F_NBITS-1:0] point3_compute [nEvenOdd-1:0];
reg [`F_NBITS-1:0] point4_compute [nEvenOdd-1:0];

reg [`F_NBITS-1:0] last_out [1:0];

wire ready, ready_pulse, pass_out_ready, gates_en_pre;
reg pass_out_ready_dly, gates_en;
wire pass_pulse = pass_out_ready & ~pass_out_ready_dly;
wire [`F_NBITS-1:0] pass_out;

prover_compute_v_sr
    #( .nCopyBits       (nCopyBits)
     , .posParallel     (posParallel)
     , .totParallel     (totParallel)
     ) iComputeVSR
     ( .clk             (clk)
     , .rstb            (rstb)
     , .en              (en | trig)
     , .restart         (restart)
     , .tau             (tau)
     , .m_tau_p1        (m_tau_p1)
     , .in_vals         (in_vals)
     , .out             (out)
     , .even_in         (even_in)
     , .even_in_ready   (1'b1)
     , .odd_in          (odd_in)
     , .odd_in_ready    (1'b1)
     , .pass_out        (pass_out)
     , .pass_out_ready  (pass_out_ready)
     , .gates_ready     (1'b1)
     , .gates_en        (gates_en_pre)
     , .ready_pulse     (ready_pulse)
     , .ready           (ready)
     );

initial begin
`ifdef SIMULATOR_IS_ICARUS
    $dumpfile("prover_compute_h_test.fst");
    $dumpvars;
    for (i = 0; i < 4; i = i + 1) begin
        /*
        for (c = 0; c < nCopies; c = c + 1) begin
            $dumpvars(layer_inputs[c][i]);
        end
        */
        $dumpvars(0, out[i]);
    end
`else
    $shm_open("prover_compute_h_test.shm");
    $shm_probe("ASCM");
`endif
    gates_en = 1'b0;
    restart = 1;
    rseed = 31337;
    trip_count = 0;
    round_count = lastRoundNum + 1;
    randomize_tau();
    val_count = 0;
    clk = 0;
    rstb = 0;
    trig = 0;
    en = 0;
    #1 rstb = 1;
    clk = 1;
    #2 trig = 1;
    #2 trig = 0;
    restart = 0;
end

`ALWAYS_FF @(posedge clk) begin
    pass_out_ready_dly <= pass_out_ready;
    gates_en <= gates_en_pre;
    if (en) begin
        restart <= 1'b0;
    end
    en <= ready_pulse;
    if (ready_pulse) begin
        randomize_tau();
    end
    if (gates_en) begin
        check_gate();
    end
    if (pass_pulse) begin
        check_pass();
    end
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

task check_pass;
    reg [`F_NBITS-1:0] tmp1, tmp2;
begin
    tmp1 = $f_mul(m_tau_p1, last_out[0]);
    tmp2 = $f_mul(tau, last_out[1]);
    tmp1 = $f_add(tmp1, tmp2);

    $display("*p*");
    $display("0x%h 0x%h %s", tmp1, pass_out, tmp1 == pass_out ? ":)" : "!!!!!!");
end
endtask

task check_gate;
    integer m;
    reg [`F_NBITS-1:0] tmp [3:0], tmp1, tmp2;
begin
    if (nCopyBits < round_count) begin
        m = 1;
    end else begin
        m = 1 << (nCopyBits - round_count);
    end
    if (val_count >= m) begin
        $display("ERROR unexpectedly large val_count %d in round %d", val_count, round_count);
        $finish;
    end else if (val_count == 0) begin
        $display("\n****");
    end

    if (nCopyBits < round_count) begin
        tmp[0] = even_in;
        tmp[1] = odd_in;

        tmp1 = $f_mul(2, even_in);
        tmp2 = $f_mul(`F_M1, odd_in);
        tmp[2] = $f_add(tmp1, tmp2);

        tmp1 = $f_mul(`F_M1, even_in);
        tmp2 = $f_mul(2, odd_in);
        tmp[3] = $f_add(tmp1, tmp2);
    end else begin
        tmp[0] = chi_compute[2*val_count];
        tmp[1] = chi_compute[2*val_count + 1];
        tmp[2] = point3_compute[val_count];
        tmp[3] = point4_compute[val_count];
    end

    $display("** %d", m);
    for (m = 0; m < 4; m = m + 1) begin
        $display("0x%h 0x%h %s", tmp[m], out[m], tmp[m] == out[m] ? ":)" : "!!!!!!");
    end

    last_out[0] = out[0];
    last_out[1] = out[1];

    val_count = val_count + 1;
end
endtask

task randomize_tau;
    integer i, j, c;
    integer rnd, hval;
    reg [`F_NBITS-1:0] tmp1, tmp2, tmp3, tmp4;
begin
    // restart
    if (round_count > lastRoundNum) begin
        restart = 1'b1;
        round_count = 0;
        trip_count = trip_count + 1;
        randomize_in_vals();
    end
    $display("%d", round_count);

    if (trip_count > 7) begin
        $finish;
    end

    // set new tau and (1 - tau)
    tau = $random(rseed);
    tau = {tau[31:0],32'b0} | $random(rseed);
    m_tau_p1 = ~tau;
    m_tau_p1 = $f_add(m_tau_p1, `F_Q_P2_MI);

    update_chi_compute();
    update_even_odd();

    round_count = round_count + 1;
    val_count = 0;
end
endtask

task update_chi_compute;
    integer c, max;
    reg [`F_NBITS-1:0] tmp1, tmp2, tmp3, tmp4, tmp5, tmp6;
begin
    max = 1 << (nCopyBits - round_count);
    for (c = 0; c < max; c = c + 1) begin
        if (round_count == 0) begin
            chi_compute[c] = in_vals[c];
        end else begin
            tmp3 = chi_compute[2*c];
            tmp4 = chi_compute[2*c + 1];

            tmp1 = $f_mul(m_tau_p1, tmp3);
            tmp2 = $f_mul(tau, tmp4);
            chi_compute[c] = $f_add(tmp1, tmp2);
        end

        if (c % 2 == 0) begin
            tmp5 = chi_compute[c];
        end else begin
            tmp6 = chi_compute[c];

            tmp1 = $f_mul(2, tmp5);
            tmp2 = $f_mul(`F_M1, tmp6);
            point3_compute[c >> 1] = $f_add(tmp1, tmp2);

            tmp1 = $f_mul(2, tmp6);
            tmp2 = $f_mul(`F_M1, tmp5);
            point4_compute[c >> 1] = $f_add(tmp1, tmp2);
        end
    end
end
endtask

task update_even_odd;
    reg [`F_NBITS-1:0] temp;
begin
    temp = $random(rseed);
    temp = {temp[31:0],32'b0} | $random(rseed);
    even_in = temp;

    temp = $random(rseed);
    temp = {temp[31:0],32'b0} | $random(rseed);
    odd_in = temp;
end
endtask

task randomize_in_vals;
    integer c;
    reg [`F_NBITS-1:0] temp;
begin
    for (c = 0; c < nCopies; c = c + 1) begin
        temp = $random(rseed);
        temp = {temp[31:0],32'b0} | $random(rseed);
        in_vals[c] = temp;
    end
end
endtask

endmodule
