// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// testbench for prover_compute_chi
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "field_arith_defs.v"
`include "prover_compute_h_percopy.sv"

module prover_compute_h_percopy_test ();

localparam nCopies = 16;
localparam nCopyBits = $clog2(nCopies);
localparam nCopiesRnd = 1 << nCopyBits;
localparam nInputs = 16;
localparam nSerBits = $clog2(nInputs) - 1;

integer round_count, trip_count, rseed, i, c;
reg clk, rstb, en, trig, restart;

reg [`F_NBITS-1:0] tau, m_tau_p1;

reg [`F_NBITS-1:0] layer_inputs [nCopies-1:0] [nInputs-1:0];
wire [`F_NBITS-1:0] z2 [nCopyBits-1:0];
wire [`F_NBITS-1:0] m_z2_p1 [nCopyBits-1:0];
wire [`F_NBITS-1:0] outputs [nInputs-1:0];
reg [`F_NBITS-1:0] chi_compute [nCopiesRnd-1:0];
reg [`F_NBITS-1:0] outputs_compute [nInputs-1:0];
reg [`F_NBITS-1:0] z2_save [nCopyBits-1:0];
reg [`F_NBITS-1:0] m_z2_p1_save [nCopyBits-1:0];

wire ready_pulse, ready, outputs_ready;

prover_compute_h_percopy
    #( .nCopies         (nCopies)
     , .nInputs         (nInputs)
     , .nSerBits        (nSerBits)
     ) iHPer
     ( .clk             (clk)
     , .rstb            (rstb)
     , .en              (en | trig)
     , .restart         (restart)
     , .tau             (tau)
     , .m_tau_p1        (m_tau_p1)
     , .layer_inputs    (layer_inputs)
     , .z2              (z2)
     , .m_z2_p1         (m_z2_p1)
     , .outputs         (outputs)
     , .ready_pulse     (ready_pulse)
     , .ready           (ready)
     , .outputs_ready   (outputs_ready)
     );

initial begin
`ifdef SIMULATOR_IS_ICARUS
    $dumpfile("prover_compute_h_percopy_test.fst");
    $dumpvars;
    /*
    for (i = 0; i < nInputs; i = i + 1) begin
        for (c = 0; c < nCopies; c = c + 1) begin
            $dumpvars(layer_inputs[c][i]);
        end
        $dumpvars(0, outputs[i]);
    end
    for (c = 0; c < nCopyBits; c = c + 1) begin
        $dumpvars(z2[c]);
    end
    for (c = 0; c < nCopiesRnd; c = c + 1) begin
        $dumpvars(iHPer.chi_out[c]);
    end
    */
`else
    $shm_open("prover_compute_h_percopy_test.shm");
    $shm_probe("ASCM");
`endif
    randomize_layer_inputs();
    randomize_tau();
    restart = 1;
    rseed = 1221;
    trip_count = 0;
    round_count = 0;
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
    reg [`F_NBITS-1:0] tmp1, tmp2;
begin
    if (round_count == nCopyBits) begin
        $display("***");
        for (i = 0; i < nCopyBits; i = i + 1) begin
            $display("%h %h %s", z2_save[i], z2[i], z2_save[i] == z2[i] ? ":)" : "!!!!!!");
            $display("%h %h %s", m_z2_p1_save[i], m_z2_p1[i], m_z2_p1_save[i] == m_z2_p1[i] ? ":)" : "!!!!!!");
        end
        if (~outputs_ready) begin
            $display("ERROR outputs not ready!!!");
            if (iHPer.chi_ready) begin
                $display("STRANGELY, chi_ready IS asserted...");
            end
        end else begin
            $display("");
        end

        /*
        for (c = 0; c < nCopies; c = c + 1) begin
            $display("%h %h %s", chi_compute[c], iHPer.chi_out[c], chi_compute[c] == iHPer.chi_out[c] ? ":)" : "!!!!!!");
        end
        $display("");
        */

        for (i = 0; i < nInputs; i = i + 1) begin
            $display("%h %h %s", outputs_compute[i], outputs[i], outputs_compute[i] == outputs[i] ? ":)" : "!!!!!!");
        end
    end else if (outputs_ready) begin
        $display("ERROR outputs should not be ready!!!");
    end

    // restart
    if (round_count == nCopyBits) begin
        restart = 1'b1;
        round_count = 0;
        trip_count = trip_count + 1;
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

    z2_save[round_count] = tau;
    m_z2_p1_save[round_count] = m_tau_p1;

    // update tracking values
    if (round_count == 0) begin
        chi_compute[0] = m_tau_p1;
        chi_compute[1] = tau;
    end else begin
        j = (1 << round_count);
        for (i = 0; i < j; i = i + 1) begin
            tmp1 = chi_compute[i];
            chi_compute[i] = $f_mul(tmp1, m_tau_p1);
            chi_compute[i+j] = $f_mul(tmp1, tau);
        end
    end

    round_count = round_count + 1;

    if (round_count == nCopyBits) begin
        for (i = 0; i < nInputs; i = i + 1) begin
            outputs_compute[i] = {(`F_NBITS){1'b0}};
        end

        for (i = 0; i < nInputs; i = i + 1) begin
            tmp2 = 0;
            for (c = 0; c < nCopies; c = c + 1) begin
                tmp1 = $f_mul(layer_inputs[c][i], chi_compute[c]);
                tmp2 = $f_add(tmp1, tmp2);
            end
            outputs_compute[i] = tmp2;
        end
    end
end
endtask

task randomize_layer_inputs;
    integer c, i;
    reg [`F_NBITS-1:0] temp;
begin
    for (c = 0; c < nCopies; c = c + 1) begin
        for (i = 0; i < nInputs; i = i + 1) begin
            temp = $random(rseed);
            temp = {temp[31:0],32'b0} | $random(rseed);
            layer_inputs[c][i] = temp;
        end
    end
end
endtask

endmodule
