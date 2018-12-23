// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// testbench for prover_compute_chi
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "field_arith_defs.v"
`include "prover_compute_h_chi.sv"
`include "prover_adder_tree_pl.sv"
`include "prover_compute_h_accum.sv"

module prover_compute_h_chi_test ();

localparam npoints = 5;
localparam noutputs = 1 << npoints;
localparam ngates = 1 << (npoints - 1);

integer round_count, trip_count;
integer rseed, i;
reg clk, rstb, en, trig;
reg restart;
wire [`F_NBITS-1:0] chi_out [noutputs-1:0];
reg [`F_NBITS-1:0] tau, m_tau_p1;

reg [`F_NBITS-1:0] chi_compute [noutputs-1:0];

wire chi_ready;
wire addt_ready, addt_en, addt_idle, addt_in_tag, addt_out_ready_pulse, addt_out_tag;
wire accum_ready, accum_ready_pulse;
reg [`F_NBITS-1:0] mvals_in[noutputs-1:0];
wire [`F_NBITS-1:0] mvals_out[ngates-1:0];
wire [`F_NBITS-1:0] addt_out;
wire [`F_NBITS-1:0] accum_out;
reg [`F_NBITS-1:0] accum_compute;

wire all_ready = chi_ready & addt_idle & accum_ready;
reg all_ready_dly;
wire all_ready_pulse = all_ready & ~all_ready_dly;

prover_compute_h_chi
    #( .npoints     (npoints)
     ) icompute
     ( .clk         (clk)
     , .rstb        (rstb)
     , .en          (en | trig)
     , .restart     (restart)
     , .tau         (tau)
     , .m_tau_p1    (m_tau_p1)
     , .addt_ready  (addt_ready)
     , .mvals_in    (mvals_in)
     , .addt_en     (addt_en)
     , .addt_tag    (addt_in_tag)
     , .mvals_out   (mvals_out)
     , .ready_pulse ()
     , .ready       (chi_ready)
     , .chi_out     (chi_out)
     );

prover_adder_tree_pl
    #( .ngates          (ngates)
     , .ntagb           (1)
     ) iaddt
     ( .clk             (clk)
     , .rstb            (rstb)
     , .en              (addt_en)
     , .in              (mvals_out)
     , .in_tag          (addt_in_tag)
     , .idle            (addt_idle)
     , .in_ready_pulse  ()
     , .in_ready        (addt_ready)
     , .out_ready_pulse (addt_out_ready_pulse)
     , .out_ready       ()
     , .out             (addt_out)
     , .out_tag         (addt_out_tag)
     );

prover_compute_h_accum iaccum
     ( .clk         (clk)
     , .rstb        (rstb)
     , .en          (addt_out_ready_pulse)
     , .in          (addt_out)
     , .in_tag      (addt_out_tag)
     , .ready_pulse (accum_ready_pulse)
     , .ready       (accum_ready)
     , .out         (accum_out)
     );

initial begin
`ifdef SIMULATOR_IS_ICARUS
    $dumpfile("prover_compute_v_test.fst");
    $dumpvars;
    for (i = 0; i < noutputs; i = i + 1) begin
        //$dumpvars(0, icompute.chi_out_reg[i]);
        //$dumpvars(0, icompute.chi_out_next[i]);
        $dumpvars(0, chi_out[i]);
        $dumpvars(0, chi_compute[i]);
    end
    for (i = 0; i < ngates; i = i + 1) begin
        $dumpvars(0, icompute.mul_out[i]);
    end
`else
    $shm_open("prover_compute_v_test.shm");
    $shm_probe("ASCM");
`endif
    randomize_mvals_in();
    randomize_tau();
    restart = 1;
    rseed = 1;
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
    all_ready_dly <= all_ready;
    if (en) begin
        restart <= 1'b0;
    end
    en <= all_ready_pulse;
    if (all_ready_pulse) begin
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
    if (round_count == npoints) begin
        $display("***");
        for (i = 0; i < noutputs; i = i + 1) begin
            $display("%h %h %s", chi_compute[i], chi_out[i], chi_compute[i] == chi_out[i] ? ":)" : "!!!!!!");
        end
    end else if (round_count > npoints) begin
        $display("***");
        $display("%h %h %s", accum_compute, accum_out, accum_compute == accum_out ? ":)" : "!!!!!!");
    end

    // restart
    if (round_count > npoints) begin
        restart = 1'b1;
        round_count = 0;
        trip_count = trip_count + 1;
        randomize_mvals_in();
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
    if (round_count == 0) begin
        chi_compute[0] = m_tau_p1;
        chi_compute[1] = tau;
    end else if (round_count < npoints) begin
        j = (1 << round_count);
        for (i = 0; i < j; i = i + 1) begin
            tmp1 = chi_compute[i];
            chi_compute[i] = $f_mul(tmp1, m_tau_p1);
            chi_compute[i+j] = $f_mul(tmp1, tau);
        end
    end else begin
        accum_compute = {(`F_NBITS){1'b0}};
        for (i = 0; i < noutputs; i = i + 1) begin
            tmp1 = $f_mul(mvals_in[i], chi_compute[i]);
            tmp2 = $f_add(tmp1, accum_compute);
            accum_compute = tmp2;
        end
    end

    round_count = round_count + 1;
end
endtask

task randomize_mvals_in;
    integer i;
begin
    for (i = 0; i < noutputs; i = i + 1) begin
        mvals_in[i] = $random(rseed);
        mvals_in[i] = {mvals_in[i][31:0],32'b0} | $random(rseed);
    end
end
endtask

endmodule
