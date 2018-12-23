// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// testbench for verifier_compute_wpreds
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "verifier_compute_wpreds.sv"

module test () ;

localparam nparbits = 1;
localparam ncopybits = 3;
localparam ngates = 8;
localparam ninputs = 8;
localparam [`GATEFN_BITS*ngates-1:0] gates_fn = {`GATEFN_MUL, `GATEFN_ADD, `GATEFN_MUL, `GATEFN_ADD, `GATEFN_MUL, `GATEFN_ADD, `GATEFN_MUL, `GATEFN_ADD};
localparam ninbits = $clog2(ninputs);
localparam [(ngates*ninbits)-1:0] gates_in0 = {3'b000, 3'b001, 3'b010, 3'b011, 3'b100, 3'b101, 3'b110, 3'b111};
localparam [(ngates*ninbits)-1:0] gates_in1 = {3'b111, 3'b110, 3'b101, 3'b100, 3'b011, 3'b010, 3'b001, 3'b000};
localparam noutbits = $clog2(ngates);
localparam noutputs = ngates;

integer trip_count, rseed, i;

reg clk, rstb, en, trig;
reg [`F_NBITS-1:0] z1_vals [noutbits-1:0], w1_vals [ninbits-1:0], w2_vals [ninbits-1:0];
reg [`F_NBITS-1:0] z2_vals [ncopybits-1:0], w3_vals [ncopybits-1:0];
reg [`F_NBITS-1:0] v1_val, v2_val, tau_final;
wire [`F_NBITS-1:0] v_out;
wire [`F_NBITS-1:0] z1_out [ninbits-1:0];
reg [`F_NBITS-1:0] v_compute, z1_compute [ninbits-1:0];
wire ready;
reg ready_dly;
wire ready_pulse = ready & ~ready_dly;

verifier_compute_wpreds
   #( .nGates       (ngates)
    , .nInputs      (ninputs)
    , .nMuxSels     (1)
    , .nCopyBits    (ncopybits)
    , .nParBits     (nparbits)
    , .gates_fn     (gates_fn)
    , .gates_in0    (gates_in0)
    , .gates_in1    (gates_in1)
    , .gates_mux    (0)
    ) iPreds
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en | trig)
    , .mux_sel      (1'b0)
    , .z1_vals      (z1_vals)
    , .w1_vals      (w1_vals)
    , .w2_vals      (w2_vals)
    , .z2_vals      (z2_vals)
    , .w3_vals      (w3_vals)
    , .tau_final    (tau_final)
    , .z1_out       (z1_out)
    , .v1_v2_ready  (1'b1)
    , .v1_val       (v1_val)
    , .v2_val       (v2_val)
    , .v_out        (v_out)
    , .ready        (ready)
    );

initial begin
    $dumpfile("verifier_compute_wpreds_test.fst");
    $dumpvars;
    /*
    for (i = 0; i < ninputs; i = i + 1) begin
        $dumpvars(0, iPreds.chis_out[i]);
        $dumpvars(0, iPreds.w1_w2_chis[i]);
    end
    for (i = 0; i < 5; i = i + 1) begin
        //$dumpvars(0, iPreds.wpred_next[i]);
        $dumpvars(0, iPreds.wpvals[i]);
    end
    */
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
    reg [2*`F_NBITS:0] tmp1, tmp2, tmp3;
    reg [`F_NBITS-1:0] beta, addw, mulw, val, mvalp1;
    reg [`F_NBITS-1:0] w1_chi [ninputs-1:0], w2_chi [ninputs-1:0], z1_chi [noutputs-1:0];
begin
    for (i = 0; i < noutbits; i = i + 1) begin
        z1_vals[i] = random_value();
    end
    for (i = 0; i < ninbits; i = i + 1) begin
        w1_vals[i] = random_value();
        w2_vals[i] = random_value();
    end
    for (i = 0; i < ncopybits; i = i + 1) begin
        z2_vals[i] = random_value();
        w3_vals[i] = random_value();
    end
    v1_val = random_value();
    v2_val = random_value();
    tau_final = random_value();

    if (do_check != 0) begin
        $display("**");
        $display("%h %h %s", v_compute, v_out, v_compute == v_out ? ":)" : "!!!!!!");
        for (i = 0; i < ninbits; i = i + 1) begin
            $display("%h %h %s", z1_compute[i], z1_out[i], z1_compute[i] == z1_out[i] ? ":)" : "!!!!!!");
        end
    end

    if (trip_count == 7) begin
        $finish;
    end else begin
        trip_count = trip_count + 1;
    end

    w1_chi[0] = one_minus(w1_vals[ninbits-1]);
    w1_chi[1] = w1_vals[ninbits-1];
    w2_chi[0] = one_minus(w2_vals[ninbits-1]);
    w2_chi[1] = w2_vals[ninbits-1];
    for (i = 1; i < ninbits; i = i + 1) begin
        j = 1 << i;
        val = w1_vals[ninbits - 1 - i];
        mvalp1 = one_minus(w1_vals[ninbits - 1 - i]);
        for (k = j - 1; k >= 0; k = k - 1) begin
            tmp1 = (val * w1_chi[k]) % `F_Q;
            tmp2 = (mvalp1 * w1_chi[k]) % `F_Q;
            w1_chi[2*k + 1] = tmp1;
            w1_chi[2*k] = tmp2;
        end
        val = w2_vals[ninbits - 1 - i];
        mvalp1 = one_minus(w2_vals[ninbits - 1 - i]);
        for (k = j - 1; k >= 0; k = k - 1) begin
            tmp1 = (val * w2_chi[k]) % `F_Q;
            tmp2 = (mvalp1 * w2_chi[k]) % `F_Q;
            w2_chi[2*k + 1] = tmp1;
            w2_chi[2*k] = tmp2;
        end
    end

    z1_chi[0] = one_minus(z1_vals[noutbits-1]);
    z1_chi[1] = z1_vals[ninbits-1];
    for (i = 1; i < noutbits; i = i + 1) begin
        j = 1 << i;
        val = z1_vals[noutbits - 1 - i];
        mvalp1 = one_minus(z1_vals[noutbits - 1 - i]);
        for (k = j - 1; k >= 0; k = k - 1) begin
            tmp1 = (val * z1_chi[k]) % `F_Q;
            tmp2 = (mvalp1 * z1_chi[k]) % `F_Q;
            z1_chi[2*k + 1] = tmp1;
            z1_chi[2*k] = tmp2;
        end
    end

    addw = {(`F_NBITS){1'b0}};
    mulw = {(`F_NBITS){1'b0}};
    for (i = 0; i < noutputs; i = i + 1) begin
        tmp1 = (z1_chi[i] * w2_chi[i]) % `F_Q;
        tmp1 = (tmp1 * w1_chi[7 - i]) % `F_Q;
        if ((i % 2) == 0) begin
            addw = (addw + tmp1) % `F_Q;
        end else begin
            mulw = (mulw + tmp1) % `F_Q;
        end
    end

    tmp3 = 1;
    for (i = 0; i < ncopybits; i = i + 1) begin
        tmp1 = (w3_vals[i] * z2_vals[i]) % `F_Q;
        tmp2 = (one_minus(w3_vals[i]) * one_minus(z2_vals[i])) % `F_Q;
        tmp2 = (tmp2 + tmp1) % `F_Q;
        tmp3 = (tmp3 * tmp2) % `F_Q;
    end
    beta = tmp3;

    tmp1 = (v1_val + v2_val) % `F_Q;
    tmp1 = (tmp1 * addw) % `F_Q;

    tmp2 = (v1_val * v2_val) % `F_Q;
    tmp2 = (tmp2 * mulw) % `F_Q;

    tmp1 = (tmp1 + tmp2) % `F_Q;
    tmp1 = (tmp1 * beta) % `F_Q;
    v_compute = tmp1;

    for (i = 0; i < ninbits; i = i + 1) begin
        tmp1 = (`F_M1 * w1_vals[i]) % `F_Q;
        tmp1 = (tmp1 + w2_vals[i]) % `F_Q;
        tmp1 = (tmp1 * tau_final) % `F_Q;
        tmp1 = (tmp1 + w1_vals[i]) % `F_Q;
        z1_compute[i] = tmp1;
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
