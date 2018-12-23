// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// testbench for prover_compute_chi
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "field_arith_defs.v"
`include "prover_compute_h.sv"

module prover_compute_h_test ();

localparam nCopies = 32;
localparam nCopyBits = $clog2(nCopies);
localparam nCopiesRnd = 1 << nCopyBits;
localparam nInputs = 16;
localparam nInBits = $clog2(nInputs);
localparam nInputsRnd = 1 << nInBits;
localparam nSerBits = $clog2(nInputs) - 1;

integer round_count, trip_count, rseed, i, c;
reg clk, rstb, en, trig, restart;

reg [`F_NBITS-1:0] tau, m_tau_p1;
reg [`F_NBITS-1:0] chi_early [nInputs-1:0];
reg [`F_NBITS-1:0] h_in [1:0];
wire [`F_NBITS-1:0] h_coeff_out [nInBits:0];
wire [`F_NBITS-1:0] w1 [nInBits-1:0];
wire [`F_NBITS-1:0] w2_m_w1 [nInBits-1:0];
wire [`F_NBITS-1:0] z2 [nCopyBits-1:0];
wire [`F_NBITS-1:0] m_z2_p1 [nCopyBits-1:0];

reg [`F_NBITS-1:0] h_vals_compute [nInBits:0];
reg [`F_NBITS-1:0] h_chi_compute [nInBits:2] [nInputsRnd-1:0];

reg [`F_NBITS-1:0] z2_save [nCopyBits-1:0];
reg [`F_NBITS-1:0] m_z2_p1_save [nCopyBits-1:0];
reg [`F_NBITS-1:0] w1_save [nInBits-1:0];
reg [`F_NBITS-1:0] w2_m_w1_save [nInBits-1:0];

reg chi_early_ready;

wire ready_pulse, ready;

prover_compute_h
    #( .nCopies         (nCopies)
     , .nInputs         (nInputs)
     , .nSerBits        (nSerBits)
     ) iHComp
     ( .clk             (clk)
     , .rstb            (rstb)

     , .en              (en | trig)
     , .restart         (restart)

     , .tau             (tau)
     , .m_tau_p1        (m_tau_p1)

     , .h0_in           (h_in[0])
     , .h1_in           (h_in[1])

     , .chi_early       (chi_early)
     , .chi_early_ready (chi_early_ready)

     , .h_coeff_out     (h_coeff_out)

     , .w1              (w1)
     , .w2_m_w1         (w2_m_w1)
     , .z2              (z2)
     , .m_z2_p1         (m_z2_p1)

     , .ready_pulse     (ready_pulse)
     , .ready           (ready)
     );

initial begin
`ifdef SIMULATOR_IS_ICARUS
    $dumpfile("prover_compute_h_test.fst");
    $dumpvars;
    for (i = 0; i < nCopyBits; i = i + 1) begin
        $dumpvars(0, z2[i], m_z2_p1[i]);
    end
`else
    $shm_open("prover_compute_h_test.shm");
    $shm_probe("ASCM");
`endif
    randomize_layer_inputs();
    randomize_tau();
    restart = 1;
    rseed = 31337;
    trip_count = 0;
    round_count = 0;
    chi_early_ready = 0;
    clk = 0;
    rstb = 0;
    trig = 0;
    en = 0;
    #1 rstb = 1;
    clk = 1;
    #2 trig = 1;
    #2 trig = 0;
end

`ALWAYS_FF @(posedge clk) begin
    if (en) begin
        restart <= 1'b0;
    end
    en <= ready_pulse;
    if (ready_pulse) begin
        randomize_tau();
    end
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

task randomize_tau;
    integer i, j;
    integer rnd, hval;
    reg [`F_NBITS-1:0] w2_tmp, mw2p1_tmp;
    reg [`F_NBITS-1:0] tmp1, tmp2;
    reg [`F_NBITS-1:0] tmp_chi [nInputsRnd-1:0];
begin
    if (round_count == nCopyBits) begin
        $display("***\n  z2:");
        for (i = 0; i < nCopyBits; i = i + 1) begin
            $display("%h %h %s", z2_save[i], z2[i], z2_save[i] == z2[i] ? ":)" : "!!!!!!");
            $display("%h %h %s", m_z2_p1_save[i], m_z2_p1[i], m_z2_p1_save[i] == m_z2_p1[i] ? ":)" : "!!!!!!");
        end
        chi_early_ready = 1'b1;
    end else if (round_count == nCopyBits + 2 * nInBits) begin
        $display("  w1:");
        for (i = 0; i < nInBits; i = i + 1) begin
            $display("%h %h %s", w1_save[i], w1[i], w1_save[i] == w1[i] ? ":)" : "!!!!!!");
        end
        $display("  w2_m_w1:");
        for (i = 0; i < nInBits; i = i + 1) begin
            $display("%h %h %s", w2_m_w1_save[i], w2_m_w1[i], w2_m_w1_save[i] == w2_m_w1[i] ? ":)" : "!!!!!!");
        end
        $display("  lagrange_in:");
        for (hval = 0; hval < nInBits + 1; hval = hval + 1) begin
            $display("%h %h %s", h_vals_compute[hval], iHComp.lagrange_in[hval], h_vals_compute[hval] == iHComp.lagrange_in[hval] ? ":)" : "!!!!!!");
        end
        $display("  lagrange_in_recomputed:");
        recompute_outputs_from_coeffs();
    end

    // restart
    if (round_count == nCopyBits + 2 * nInBits) begin
        restart = 1'b1;
        round_count = 0;
        trip_count = trip_count + 1;
        chi_early_ready = 1'b0;
        randomize_layer_inputs();
    end

    if (trip_count > 7) begin
        $finish;
    end

    // set new tau and (1 - tau)
    tau = $random(rseed);
    tau = {tau[31:0],32'b0} | $random(rseed);
    m_tau_p1 = ~tau;
    m_tau_p1 = $f_add(m_tau_p1, `F_Q_P2_MI);

    if (round_count < nCopyBits) begin
        z2_save[round_count] = tau;
        m_z2_p1_save[round_count] = m_tau_p1;
    end else if (round_count < nCopyBits + nInBits) begin
        w1_save[round_count - nCopyBits] = tau;
    end else if (round_count < nCopyBits + 2 * nInBits) begin
        w2_m_w1_save[round_count - nCopyBits - nInBits] = $f_sub(tau, w1_save[round_count - nCopyBits - nInBits]);
    end

    round_count = round_count + 1;
    if (round_count == nCopyBits + 2 * nInBits) begin
        for (rnd = 0; rnd < nInBits; rnd = rnd + 1) begin
            w2_tmp = $f_add(w1_save[rnd], w2_m_w1_save[rnd]);
            for (hval = 2; hval < nInBits + 1; hval = hval + 1) begin
                w2_tmp = $f_add(w2_tmp, w2_m_w1_save[rnd]);
                mw2p1_tmp = $f_sub(1, w2_tmp);
                if (rnd == 0) begin
                    h_chi_compute[hval][0] = mw2p1_tmp;
                    h_chi_compute[hval][1] = w2_tmp;
                end else begin
                    j = (1 << rnd);
                    for (i = 0; i < j; i = i + 1) begin
                        tmp1 = h_chi_compute[hval][i];
                        h_chi_compute[hval][i] = $f_mul(tmp1, mw2p1_tmp);
                        h_chi_compute[hval][i+j] = $f_mul(tmp1, w2_tmp);
                    end
                end
            end
        end

        // at this point, wee have h_chi_compute done. Compute dot products.
        h_vals_compute[0] = h_in[0];
        h_vals_compute[1] = h_in[1];
        for (hval = 2; hval < nInBits + 1; hval = hval + 1) begin
            tmp2 = 0;
            for (i = 0; i < nInputs; i = i + 1) begin
                tmp1 = $f_mul(chi_early[i], h_chi_compute[hval][i]);
                tmp2 = $f_add(tmp1, tmp2);
            end
            h_vals_compute[hval] = tmp2;
        end
    end
end
endtask

task randomize_layer_inputs;
    integer i;
    reg [`F_NBITS-1:0] temp;
begin
    for (i = 0; i < nInputs; i = i + 1) begin
        temp = $random(rseed);
        temp = {temp[31:0],32'b0} | $random(rseed);
        chi_early[i] = temp;
    end
    for (i = 0; i < 2; i = i + 1) begin
        temp = $random(rseed);
        temp = {temp[31:0],32'b0} | $random(rseed);
        h_in[i] = temp;
    end
end
endtask

task recompute_outputs_from_coeffs;
    integer hval, idx;
    reg [`F_NBITS-1:0] tmp;
begin
    for (hval = 0; hval < nInBits + 1; hval = hval + 1) begin
        tmp = h_coeff_out[nInBits];
        for (idx = nInBits - 1; idx >= 0; idx = idx - 1) begin
            tmp = $f_mul(tmp, hval);
            tmp = $f_add(tmp, h_coeff_out[idx]);
        end
        $display("%h %h %s", tmp, h_vals_compute[hval], tmp == h_vals_compute[hval] ? ":)" : "!!!!!!");
    end
end
endtask

endmodule
