// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// testbench for verifier_compute_chi without dot product
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "simulator.v"
`include "field_arith_defs.v"
`include "verifier_compute_chi_single.sv"

module test () ;

localparam nValBits = 4;
localparam nEarlyBits = 3;
localparam nValues = 1 << nValBits;
localparam nEarly = 1 << nEarlyBits;

integer trip_count;
integer rseed, i;
reg clk, rstb, en, trig, early;
reg [`F_NBITS-1:0] tau [nValBits-1:0];
wire [`F_NBITS-1:0] chi_out [nValues-1:0];
wire [`F_NBITS-1:0] chi_out_early [nEarly-1:0];
reg ready_dly;
wire ready;
wire ready_pulse = ready & ~ready_dly;

reg [`F_NBITS-1:0] chi_compute [nValues-1:0];

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

genvar INum;
generate
    for (INum = 0; INum < nEarly; INum = INum + 1) begin: EarlyHookup
        assign chi_out_early[INum] = chi_out[INum];
    end
endgenerate

verifier_compute_chi_single
    #( .nValBits    (nValBits)
     , .nEarlyBits  (nEarlyBits)
     ) iChi
     ( .clk         (clk)
     , .rstb        (rstb)
     , .en          (en | trig)
     , .early       (early)
     , .tau         (tau)
     , .chi_out     (chi_out)
     , .ready       (ready)
     );

initial begin
    $dumpfile("verifier_compute_chi_single_test.fst");
    $dumpvars;
    for (i = 0; i < nValues; i = i + 1) begin
        $dumpvars(0, chi_out[i]);
        $dumpvars(0, chi_compute[i]);
        //$dumpvars(0, internal_values[i]);
    end
    for (i = 0; i < nEarly; i = i + 1) begin
        $dumpvars(0, chi_out_early[i]);
    end
    for (i = 0; i < nValBits; i = i + 1) begin
        $dumpvars(0, tau[i]);
    end
    rseed = 3;
    trip_count = 0;
    early = 0;
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
    integer i, j, k, do_check, start;
begin
    for (i = 0; i < nValBits; i = i + 1) begin
        tau[i] = random_value();
    end

    if (do_check == 1) begin
        $display("**");
        if (early) begin
            for (i = 0; i < nEarly; i = i + 1) begin
                $display("%h %h %s", chi_compute[i], chi_out_early[i], chi_out_early[i] == chi_compute[i] ? ":)" : "!!!!!!");
            end
        end else begin
            for (i = 0; i < nValues; i = i + 1) begin
                $display("%h %h %s", chi_compute[i], chi_out[i], chi_out[i] == chi_compute[i] ? ":)" : "!!!!!!");
            end
        end

        trip_count = trip_count + 1;

        if (trip_count > 7) begin
            $finish;
        end
    end

    early = trip_count % 2;
    if (trip_count % 2) begin
        start = nEarlyBits;
    end else begin
        start = nValBits;
    end

    chi_compute[0] = one_minus(tau[start - 1]);
    chi_compute[1] = tau[start - 1];
    for (i = 1; i < start; i = i + 1) begin
        val = tau[start - 1 - i];
        mvalp1 = one_minus(tau[start - 1 - i]);
        j = 1 << i;
        for (k = j - 1; k >= 0; k = k - 1) begin
            tmp1 = (val * chi_compute[k]) % `F_Q;
            tmp2 = (mvalp1 * chi_compute[k]) % `F_Q;
            chi_compute[2*k + 1] = tmp1;
            chi_compute[2*k] = tmp2;
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
