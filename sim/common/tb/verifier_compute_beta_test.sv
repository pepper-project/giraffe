// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// testbench for verifier_compute_beta
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "verifier_compute_beta.sv"

module test () ;

localparam nCopyBits = 4;

integer trip_count;
integer rseed, i;
reg clk, rstb, en, trig;
reg [`F_NBITS-1:0] w_vals [nCopyBits-1:0];
reg [`F_NBITS-1:0] z_vals [nCopyBits-1:0];
reg ready_dly;
wire ready;
wire ready_pulse = ready & ~ready_dly;

wire [`F_NBITS-1:0] beta_out;
reg [`F_NBITS-1:0] beta_compute;

verifier_compute_beta
   #( .nCopyBits        (nCopyBits)
    ) iBeta
    ( .clk              (clk)
    , .rstb             (rstb)
    , .en               (en | trig)
    , .w_vals           (w_vals)
    , .z_vals           (z_vals)
    , .add_en_ext       (1'b0)
    , .add_in_ext       ()
    , .add_out_ext      ()
    , .add_ready_ext    ()
    , .mul_en_ext       (1'b0)
    , .mul_in_ext       ()
    , .mul_out_ext      ()
    , .mul_ready_ext    ()
    , .ready            (ready)
    , .beta_out         (beta_out)
    );

initial begin
    $dumpfile("verifier_compute_beta_test.fst");
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
    integer i, do_check;
    reg [2*`F_NBITS:0] tmp1, tmp2, tmp3;
begin
    for (i = 0; i < nCopyBits; i = i + 1) begin
        w_vals[i] = random_value();
        z_vals[i] = random_value();
    end

    if (do_check != 0) begin
        $display("%h %h %s", beta_compute, beta_out, beta_compute == beta_out ? ":)" : "!!!!!!");
    end

    if (trip_count == 7) begin
        $finish;
    end else begin
        trip_count = trip_count + 1;
    end

    tmp3 = 1;
    for (i = 0; i < nCopyBits; i = i + 1) begin
        tmp1 = (w_vals[i] * z_vals[i]) % `F_Q;
        tmp2 = (one_minus(w_vals[i]) * one_minus(z_vals[i])) % `F_Q;
        tmp2 = (tmp2 + tmp1) % `F_Q;
        tmp3 = (tmp3 * tmp2) % `F_Q;
    end
    beta_compute = tmp3;
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
