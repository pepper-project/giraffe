// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// testbench for prover_compute_chi
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "field_arith_defs.v"
`include "prover_compute_v_srbank.sv"

module prover_compute_chi_test ();

localparam nCopyBits = 8;
localparam nCopies = 1 << nCopyBits;
localparam nParBits = nCopyBits - 2;
localparam nParallel = 1 << nParBits;

integer round_count, trip_count;
integer rseed, i;
reg clk, rstb, en, trig;
reg restart;
reg [`F_NBITS-1:0] tau, m_tau_p1;

reg [`F_NBITS-1:0] in_vals [nCopies-1:0];
wire [`F_NBITS-1:0] final_out;
wire final_ready;

wire [`F_NBITS-1:0] out [nParallel-1:0] [3:0];

reg [`F_NBITS-1:0] chi_compute [nCopies-1:0];
wire [nParallel-1:0] gates_en;
reg [nParallel-1:0] gates_en_dly;
wire [nParallel-1:0] gates_ready = ~(gates_en | gates_en_dly);

wire ready, ready_pulse;

prover_compute_v_srbank
    #( .nCopyBits   (nCopyBits)
     , .nParBits    (nParBits)
     ) iBank
     ( .clk         (clk)
     , .rstb        (rstb)
     , .en          (en | trig)
     , .restart     (restart)
     , .tau         (tau)
     , .m_tau_p1    (m_tau_p1)
     , .in_vals     (in_vals)
     , .out         (out)
     , .final_out   (final_out)
     , .final_ready (final_ready)
     , .gates_ready (gates_ready)
     , .gates_en    (gates_en)
     , .ready       (ready)
     , .ready_pulse (ready_pulse)
     );

initial begin
`ifdef SIMULATOR_IS_ICARUS
    $dumpfile("prover_compute_v_srbank_test.fst");
    $dumpvars;
`else
    $shm_open("prover_compute_v_srbank_test.shm");
    $shm_probe("ASCM");
`endif
    rseed = 1;
    gates_en_dly = {(nParallel){1'b0}};
    trip_count = 0;
    round_count = nCopyBits + 1;
    randomize_tau();
    clk = 0;
    rstb = 0;
    trig = 0;
    en = 0;
    #1 rstb = 1;
    clk = 1;
    #1 trig = 1;
    restart = 1;
    #2 trig = 0;
end

`ALWAYS_FF @(posedge clk) begin
    if (en | trig) begin
        restart <= 1'b0;
    end
    en <= ready_pulse;
    gates_en_dly <= gates_en;
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
    // check that the computation is correct
    if (round_count == nCopyBits) begin
        if (! final_ready) begin
            $display("%d ERROR: final_ready not set!");
        end else begin
            $display("%h %h %s %d", chi_compute[0], final_out, chi_compute[0] == final_out ? ":)" : "!!!!!!", $time);
        end
    end

    // restart
    if (round_count >= nCopyBits) begin
        randomize_chi_in();
        restart = 1'b1;
        round_count = 0;
        trip_count = trip_count + 1;
    end

    if (trip_count > 7) begin
        $finish;
    end

    // set new tau and (1 - tau)
    tau = $random(rseed);
    tau = {tau[31:0],32'b0} | $random(rseed);
    m_tau_p1 = ~tau;
    m_tau_p1 = $f_add(m_tau_p1, `F_Q_P2_MI);

    // update tracking values
    if (round_count != 0) begin
        j = nCopies >> (round_count);
        for (i = 0; i < j; i = i + 1) begin
            tmp1 = $f_mul(chi_compute[2*i], m_tau_p1);
            tmp2 = $f_mul(chi_compute[2*i+1], tau);
            chi_compute[2*i] = 0;
            chi_compute[2*i+1] = 0;
            chi_compute[i] = $f_add(tmp1, tmp2);
        end
    end

    round_count = round_count + 1;
end
endtask

task randomize_chi_in;
    integer i;
begin
    for (i = 0; i < nCopies; i = i + 1) begin
        in_vals[i] = $random(rseed);
        in_vals[i] = {in_vals[i][31:0],32'b0} | $random(rseed);
        chi_compute[i] = in_vals[i];
    end
end
endtask

endmodule
