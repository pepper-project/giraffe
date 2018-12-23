// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// testbench for prover_compute_chi
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "field_arith_defs.v"
`include "prover_compute_chi.sv"

module prover_compute_chi_test ();

localparam npoints = 5;
localparam noutputs = 1 << npoints;
localparam ngates = 1 << (npoints - 1);

integer round_count, trip_count;
integer rseed, i;
reg clk, rstb, en, trig;
reg restart;
reg preload;
reg [`F_NBITS-1:0] chi_in [noutputs-1:0];
wire [`F_NBITS-1:0] chi_out [noutputs-1:0];
wire [`F_NBITS-1:0] point3_out [ngates-1:0];
wire [`F_NBITS-1:0] point4_out [ngates-1:0];
reg [`F_NBITS-1:0] tau, m_tau_p1;

reg [`F_NBITS-1:0] chi_compute [noutputs-1:0];
reg [`F_NBITS-1:0] point3_compute [ngates-1:0];
reg [`F_NBITS-1:0] point4_compute [ngates-1:0];

wire ready, ready_pulse;

prover_compute_chi
    #( .npoints     (npoints)
     ) icompute
     ( .clk         (clk)
     , .rstb        (rstb)
     , .en          (en | trig)
     , .restart     (restart)
     , .preload     (preload)
     , .skip_pt4    (1'b0)
     , .skip_pt3    (1'b0)
     , .tau         (tau)
     , .m_tau_p1    (m_tau_p1)
     , .chi_in      (chi_in)
     , .ready_pulse (ready_pulse)
     , .ready       (ready)
     , .chi_out     (chi_out)
     , .point3_out  (point3_out)
     , .point4_out  (point4_out)
     );

initial begin
`ifdef SIMULATOR_IS_ICARUS
    $dumpfile("prover_compute_v_test.fst");
    $dumpvars;
    for (i = 0; i < noutputs; i = i + 1) begin
        //$dumpvars(0, icompute.chi_out_reg[i]);
        //$dumpvars(0, icompute.chi_out_next[i]);
        $dumpvars(0, chi_out[i]);
        $dumpvars(0, chi_in[i]);
        $dumpvars(0, chi_compute[i]);
    end
    for (i = 0; i < ngates; i = i + 1) begin
        $dumpvars(0, icompute.mul_out[i], icompute.add_out[i]);
    end
`else
    $shm_open("prover_compute_v_test.shm");
    $shm_probe("ASCM");
`endif
    rseed = 3;
    trip_count = 0;
    round_count = npoints;
    randomize_chi_in();
    compute_point34(0);
    compute_point34(0);
    clk = 0;
    rstb = 0;
    trig = 0;
    en = 0;
    #1 rstb = 1;
    clk = 1;
    preload = 1;
    #2 trig = 1;
    #2 trig = 0;
    preload = 0;
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
    reg [2*`F_NBITS:0] tmp;
begin
    // check that the computation is correct
    if (round_count <= npoints) begin
        j = noutputs >> round_count;
        $display("***");
        for (i = 0; i < (1 << round_count); i = i + 1) begin
            $display("%h %h %s", chi_compute[i], chi_out[i * j], chi_compute[i] == chi_out[i * j] ? ":)" : "!!!!!!");
        end
    end else begin
        j = noutputs >> (round_count - npoints);
        $display("***");
        for (i = 0; i < j; i = i + 1) begin
            $display("%h %h %s", chi_compute[i], chi_out[i], chi_compute[i] == chi_out[i] ? ":)" : "!!!!!!");
        end
    end

    if (round_count >= npoints) begin
        j = noutputs >> (round_count - npoints + 1);
        $display("*3*");
        for (i = 0; i < j; i = i + 1) begin
            $display("%h %h %s", point3_compute[i], point3_out[i], point3_compute[i] == point3_out[i] ? ":)" : "!!!!!!");
        end
        $display("*4*");
        for (i = 0; i < j; i = i + 1) begin
            $display("%h %h %s", point4_compute[i], point4_out[i], point4_compute[i] == point4_out[i] ? ":)" : "!!!!!!");
        end
    end
    $display("");

    // restart
    if (round_count >= 2 * npoints) begin
        restart = 1'b1;
        round_count = 0;
        trip_count = trip_count + 1;
        randomize_chi_in();
        compute_point34(0);
    end

    if (trip_count > 7) begin
        $finish;
    end

    // set new tau and (1 - tau)
    tau = $random(rseed);
    tau = {tau[31:0],32'b0} | $random(rseed);
    tmp = (~tau + `F_Q_P2_MI) % `F_Q;
    m_tau_p1 = tmp;

    // update tracking values
    if (round_count == 0) begin
        chi_compute[0] = m_tau_p1;
        chi_compute[1] = tau;
    end else if (round_count < npoints) begin
        for (i = (1 << round_count) - 1; i >= 0; i = i - 1) begin
            tmp = (chi_compute[i] * tau) % `F_Q;
            chi_compute[2*i + 1] = tmp;
            tmp = (chi_compute[i] * m_tau_p1) % `F_Q;
            chi_compute[2*i] = tmp;
        end
    end else begin
        j = noutputs >> (round_count - npoints + 1);
        for (i = 0; i < j; i = i + 1) begin
            tmp = (chi_compute[2*i] * m_tau_p1) % `F_Q;
            tmp1 = tmp;
            tmp = (chi_compute[2*i+1] * tau) % `F_Q;
            tmp2 = tmp;
            chi_compute[2*i] = 0;
            chi_compute[2*i+1] = 0;
            tmp = (tmp1 + tmp2) % `F_Q;
            chi_compute[i] = tmp;
        end
    end

    round_count = round_count + 1;

    if (round_count >= npoints) begin
        compute_point34(round_count - npoints);
    end
end
endtask

task randomize_chi_in;
    integer i;
begin
    for (i = 0; i < noutputs; i = i + 1) begin
        chi_in[i] = $random(rseed);
        chi_in[i] = {chi_in[i][31:0],32'b0} | $random(rseed);
        chi_compute[i] = chi_in[i];
    end
end
endtask

task compute_point34;
    input rcount;
    integer rcount, i, j;
    reg [`F_NBITS-1:0] tmp1, tmp2;
    reg [2*`F_NBITS:0] tmp;
begin
    j = noutputs >> (rcount + 1);
    for (i = 0; i < j; i = i + 1) begin
        tmp = (chi_compute[2*i] * `F_M1) % `F_Q;
        tmp1 = tmp;
        tmp = (chi_compute[2*i + 1] * 2) % `F_Q;
        tmp2 = tmp;
        tmp = (tmp1 + tmp2) % `F_Q;
        point4_compute[i] = tmp;

        tmp = (chi_compute[2*i] * 2) % `F_Q;
        tmp1 = tmp;
        tmp = (chi_compute[2*i+1] * `F_M1) % `F_Q;
        tmp2 = tmp;
        tmp = (tmp1 + tmp2) % `F_Q;
        point3_compute[i] = tmp;
    end
end
endtask

endmodule
