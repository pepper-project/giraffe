// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// test bench for verifier_compute_io
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "simulator.v"
`include "field_arith_defs.v"
`include "verifier_compute_io.sv"

module test () ;

localparam nValBits = 4;
localparam nParBits = 1;
localparam nValues = 1 << nValBits;
localparam nParallel = 1 << nParBits;
localparam nValBitsPer = nValBits - nParBits;
localparam nValuesPer = 1 << nValBitsPer;

integer trip_count;
integer rseed, i;
reg clk, rstb, en, trig;
reg [`F_NBITS-1:0] tau [nValBits-1:0];
reg [`F_NBITS-1:0] vals_in [nValues-1:0];
wire [`F_NBITS-1:0] dot_product_out;
reg ready_dly;
wire ready;
wire ready_pulse = ready & ~ready_dly;

reg [`F_NBITS-1:0] chi_compute [nValues-1:0];
reg [`F_NBITS-1:0] dotp_compute;

/*
reg [`F_NBITS-1:0] internal_values [nValues-1:0];
genvar GNum;
genvar INum;
generate
    for (GNum = 0; GNum < nParallel; GNum = GNum + 1) begin
        localparam noffset = GNum * nValuesPer;
        for (INum = 0; INum < nValuesPer; INum = INum + 1) begin
            assign internal_values[noffset + INum] = iChi.ParInst[GNum].values_out_inst[INum];
        end
    end
endgenerate
*/

verifier_compute_io
    #( .nValBits    (nValBits)
     , .nParBits    (nParBits)
     ) iIO
     ( .clk         (clk)
     , .rstb        (rstb)
     , .en          (en | trig)
     , .tau         (tau)
     , .vals_in     (vals_in)
     , .mlext_out   (dot_product_out)
     , .ready       (ready)
     );

initial begin
    $dumpfile("verifier_compute_io_test.fst");
    $dumpvars;
    /*
    for (i = 0; i < nValues; i = i + 1) begin
        $dumpvars(0, chi_compute[i]);
        $dumpvars(0, internal_values[i]);
    end
    for (i = 0; i < nValBits; i = i + 1) begin
        $dumpvars(0, tau[i]);
    end
    */
    rseed = 3;
    trip_count = 0;
    randomize_values(0);
    clk = 0;
    rstb = 0;
    trig = 0;
    ready_dly = 1;
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
    reg [`F_NBITS-1:0] val, mvalp1;
    reg [2*`F_NBITS:0] tmp1, tmp2, tmp3;
    integer i, j, k, do_check;
begin
    for (i = 0; i < nValBits; i = i + 1) begin
        tau[i] = random_value();
    end
    for (i = 0; i < nValues; i = i + 1) begin
        vals_in[i] = random_value();
    end

    if (do_check == 1) begin
        $display("**");
        $display("%h %h %s", dotp_compute, dot_product_out, dotp_compute == dot_product_out ? ":)" : "!!!!!!");

        trip_count = trip_count + 1;

        if (trip_count > 7) begin
            $finish;
        end
    end

    chi_compute[0] = one_minus(tau[nValBits-1]);
    chi_compute[1] = tau[nValBits-1];
    for (i = 1; i < nValBits; i = i + 1) begin
        val = tau[nValBits - 1 - i];
        mvalp1 = one_minus(tau[nValBits - 1 - i]);
        j = 1 << i;
        for (k = j - 1; k >= 0; k = k - 1) begin
            tmp1 = (val * chi_compute[k]) % `F_Q;
            tmp2 = (mvalp1 * chi_compute[k]) % `F_Q;
            chi_compute[2*k + 1] = tmp1;
            chi_compute[2*k] = tmp2;
        end
    end
    tmp2 = 0;
    for (i = 0; i < nValues; i = i + 1) begin
        tmp1 = (chi_compute[i] * vals_in[i]) % `F_Q;
        chi_compute[i] = tmp1;
        tmp2 = (tmp2 + tmp1) % `F_Q;
    end
    dotp_compute = tmp2;
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
