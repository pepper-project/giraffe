// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// test for verifier_compute_horner
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "simulator.v"
`include "field_arith_defs.v"
`include "verifier_compute_horner.sv"

module test () ;

localparam maxDegree = 9;
localparam cBits = $clog2(maxDegree + 1);

integer trip_count;
integer rseed, i;
reg clk, rstb, en, trig, restart, cubic, round, next_lay;
reg [cBits-1:0] ncoeff;
reg [`F_NBITS-1:0] tau, val_in;
reg [`F_NBITS-1:0] c_in [maxDegree:0];
wire [`F_NBITS-1:0] val_out, lay_out, v2_out;
wire ok, ready;
reg ready_dly;
wire ready_pulse = ready & ~ready_dly;

reg [`F_NBITS-1:0] lay_compute, val_compute, v2_compute;

verifier_compute_horner
   #( .maxDegree       (maxDegree)
    ) iHorner
    ( .clk              (clk)
    , .rstb             (rstb)
    , .en               (en | trig)
    , .restart          (restart)
    , .cubic            (cubic)
    , .round            (round)
    , .next_lay         (next_lay)
    , .ncoeff           (ncoeff)
    , .tau              (tau)
    , .c_in             (c_in)
    , .val_in           (val_in)
    , .val_out          (val_out)
    , .ok               (ok)
    , .lay_out          (lay_out)
    , .v2_out           (v2_out)
    , .ready            (ready)
    );

initial begin
    $dumpfile("verifier_compute_horner_test.fst");
    $dumpvars;
    rseed = 3;
    ready_dly = 1;
    trip_count = 0;
    randomize_values(0);
    clk = 0;
    rstb = 0;
    en = 0;
    trig = 0;
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

task randomize_values;
    input do_check;
    integer i, j, do_check;
    reg [2*`F_NBITS:0] tmp1, tmp2;
begin
    if (do_check) begin
        $display("**");
        if (maxDegree - trip_count > 1) begin
            $display("%h %h %s", lay_compute, lay_out, lay_compute == lay_out ? ":)" : "!!!!!!");
            $display("%h %h %s", v2_compute, v2_out, v2_compute == v2_out ? ":)" : "!!!!!!");
        end else begin
            $display("%h %h %s (%b)", val_compute, val_out, val_compute == val_out ? ":)" : "!!!!!!", ok);
            $display("%h %h %s", v2_compute, v2_out, v2_compute == v2_out ? ":)" : "!!!!!!");
        end
    end

    for (i = 0; i < maxDegree + 1; i = i + 1) begin
        c_in[i] = random_value();
    end
    tau = random_value();

    tmp1 = 0;
    tmp2 = 0;
    if (maxDegree - trip_count > 2) begin
        round = 0;
        cubic = 0;
        restart = 0;
        next_lay = 0;
        ncoeff = maxDegree - trip_count;

        for (i = maxDegree - trip_count; i >= 0; i = i - 1) begin
            tmp1 = (tmp1 * tau) % `F_Q;
            tmp1 = (tmp1 + c_in[i]) % `F_Q;
            tmp2 = (tmp2 + c_in[i]) % `F_Q;
        end
        lay_compute = tmp1;
        v2_compute = tmp2;
    end else if (trip_count < maxDegree + 2) begin
        round = 1;
        cubic = trip_count % 2;
        restart = ((maxDegree - trip_count) == 1);
        next_lay = ((maxDegree - trip_count) == 2);
        ncoeff = 0;

        j = (trip_count % 2) ? 3 : 2;

        for (i = j; i >= 0; i = i - 1) begin
            tmp1 = (tmp1 * tau) % `F_Q;
            tmp1 = (tmp1 + c_in[i]) % `F_Q;
            tmp2 = (tmp2 + c_in[i]) % `F_Q;
        end
        tmp2 = (tmp2 + c_in[0]) % `F_Q;
        val_compute = tmp1;
        v2_compute = tmp2;
        val_in = tmp2;
    end else begin
        $finish;
    end

    trip_count = trip_count + 1;
end
endtask

endmodule
