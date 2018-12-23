// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// test the shim
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "prover_shim.sv"

module test () ;

localparam nCopyBits = 8;
localparam nGateBits = 6;
localparam nGates = 1 << nGateBits;

integer trip_count, rseed, i;
reg clk, rstb, en, trig, ready_dly;
reg [`F_NBITS-1:0] z1 [nGateBits-1:0], z2 [nCopyBits-1:0];
wire [`F_NBITS-1:0] m_z2_p1 [nCopyBits-1:0], z1_chi [nGates-1:0];
wire ready;
wire ready_pulse = ready & ~ready_dly;

reg [`F_NBITS-1:0] mz2p1_compute [nCopyBits-1:0], z1chi_compute [nGates-1:0];

prover_shim
   #( .nCopyBits    (nCopyBits)
    , .nGateBits    (nGateBits)
    ) iShim
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en | trig)
    , .z1           (z1)
    , .z2           (z2)
    , .m_z2_p1      (m_z2_p1)
    , .z1_chi       (z1_chi)
    , .ready        (ready)
    );

initial begin
    $dumpfile("prover_shim_test.fst");
    $dumpvars;
    rseed = 3;
    trip_count = 0;
    clk = 0;
    rstb = 0;
    trig = 0;
    ready_dly = 1;
    randomize_values(0);
    en = 0;
    #1 rstb = 1;
    clk = 1;
    #1 trig = 1;
    #3 trig = 0;
end

`ALWAYS_FF @(posedge clk) begin
    ready_dly <= ready;
    en <= ready_pulse;
    if (ready_pulse) begin
        randomize_values(1);
    end
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

task randomize_values;
    input do_check;
    integer i, j, k, do_check;
    reg [2*`F_NBITS:0] tmp1, tmp2;
    reg [`F_NBITS-1:0] val, mvalp1;
begin
    for (i = 0; i < nCopyBits; i = i + 1) begin
        z2[i] = random_value();
    end
    for (i = 0; i < nGateBits; i = i + 1) begin
        z1[i] = random_value();
    end

    if (do_check == 1) begin
        $display("**");
        for (i = 0; i < nGates; i = i + 1) begin
            $display("%h %h %s", z1chi_compute[i], z1_chi[i], z1chi_compute[i] == z1_chi[i] ? ":)" : "!!!!!!");
        end
        $display("");
        for (i = 0; i < nCopyBits; i = i + 1) begin
            $display("%h %h %s", mz2p1_compute[i], m_z2_p1[i], mz2p1_compute[i] == m_z2_p1[i] ? ":)" : "!!!!!!");
        end
    end

    if (trip_count == 7) begin
        $finish;
    end else begin
        trip_count = trip_count + 1;
    end

    for (i = 0; i < nCopyBits; i = i + 1) begin
        mz2p1_compute[i] = one_minus(z2[i]);
    end

    z1chi_compute[0] = one_minus(z1[nGateBits-1]);
    z1chi_compute[1] = z1[nGateBits-1];
    for (i = 1; i < nGateBits; i = i + 1) begin
        j = 1 << i;
        val = z1[nGateBits - i - 1];
        mvalp1 = one_minus(z1[nGateBits - i - 1]);
        for (k = j - 1; k >= 0; k = k - 1) begin
            tmp1 = (val * z1chi_compute[k]) % `F_Q;
            tmp2 = (mvalp1 * z1chi_compute[k]) % `F_Q;
            z1chi_compute[2*k + 1] = tmp1;
            z1chi_compute[2*k] = tmp2;
        end
    end
end
endtask

function [`F_NBITS-1:0] random_value;
    integer i;
    reg [`F_NBITS-1:0] tmp;
begin
    tmp = $random(rseed);
    for (i = 0; i < (`F_NBITS / 32) + 1; i = i + 1) begin
        tmp = {tmp[`F_NBITS-33:0],32'b0} | $random(rseed);
    end
    random_value = tmp;
end
endfunction

function [`F_NBITS-1:0] one_minus;
    input [`F_NBITS-1:0] inval;
    reg [`F_NBITS-1:0] tmp;
begin
    tmp = ~inval;
    tmp = (tmp + `F_Q_P2_MI) % `F_Q;
    one_minus = tmp;
end
endfunction

endmodule
