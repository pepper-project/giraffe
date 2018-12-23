// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// basic test for verifier_layer
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "verifier_layer.sv"

module test () ;

localparam nparbits = 1;
localparam ncopybits = 3;
localparam ncopies = 1 << ncopybits;
localparam ngates = 8;
localparam ninputs = 8;
localparam [`GATEFN_BITS*ngates-1:0] gates_fn = {`GATEFN_MUL, `GATEFN_ADD, `GATEFN_MUL, `GATEFN_ADD, `GATEFN_MUL, `GATEFN_ADD, `GATEFN_MUL, `GATEFN_ADD};
localparam ninbits = $clog2(ninputs);
localparam [(ngates*ninbits)-1:0] gates_in0 = {3'b000, 3'b001, 3'b010, 3'b011, 3'b100, 3'b101, 3'b110, 3'b111};
localparam [(ngates*ninbits)-1:0] gates_in1 = {3'b111, 3'b110, 3'b101, 3'b100, 3'b011, 3'b010, 3'b001, 3'b000};
localparam noutbits = $clog2(ngates);
localparam noutputs = ngates;
localparam lastcoeff = (ninbits < 3) ? 3 : ninbits;
localparam ncoeffbits = $clog2(lastcoeff + 1);

integer round_count, trip_count, rseed, i;
reg clk, rstb, en, trig, ready_dly, restart;
reg [`F_NBITS-1:0] c_in [lastcoeff:0];
reg [`F_NBITS-1:0] val_in;
reg [`F_NBITS-1:0] z1_vals [noutbits-1:0];
reg [`F_NBITS-1:0] z2_vals [ncopybits-1:0];
reg [`F_NBITS-1:0] w1_vals [ninbits-1:0];
reg [`F_NBITS-1:0] w2_vals [ninbits-1:0];
reg [`F_NBITS-1:0] w3_vals [ncopybits-1:0];
reg [`F_NBITS-1:0] tau_final;

wire [`F_NBITS-1:0] lay_out, tau_out, z1_out [ninbits-1:0];
wire ok, ready, fin_layer;
wire ready_pulse = ready & ~ready_dly;

verifier_layer
   #( .nInputs      (ninputs)
    , .nGates       (ngates)
    , .nMuxSels     (1)
    , .nCopyBits    (ncopybits)
    , .nParBits     (nparbits)
    , .gates_fn     (gates_fn)
    , .gates_in0    (gates_in0)
    , .gates_in1    (gates_in1)
    , .gates_mux    (0)
    ) iLayer
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en | trig)
    , .restart      (restart | trig)
    , .mux_sel      (1'b0)
    , .c_in         (c_in)
    , .val_in       (val_in)
    , .lay_out      (lay_out)
    , .z1_vals      (z1_vals)
    , .z2_vals      (z2_vals)
    , .w1_vals      (w1_vals)
    , .w2_vals      (w2_vals)
    , .w3_vals      (w3_vals)
    , .tau_final    (tau_final)
    , .tau_out      (tau_out)
    , .z1_out       (z1_out)
    , .ok           (ok)
    , .ready        (ready)
    , .fin_layer    (fin_layer)
    );

initial begin
    $dumpfile("verifier_layer_test.fst");
    $dumpvars;
    for (i = 0; i < ninbits; i = i + 1) begin
        $dumpvars(0, z1_out[i]);
    end
    rseed = 3;
    round_count = ncopybits + 2 * ninbits;
    trip_count = 0;
    clk = 0;
    rstb = 0;
    trig = 0;
    ready_dly = 1;
    randomize_inputs();
    restart = 0;
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
        randomize_inputs();
        restart <= #5 1'b0;
    end
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

task randomize_inputs;
    integer i;
begin
    if (round_count == (ncopybits + 2 * ninbits)) begin
        trip_count = trip_count + 1;
        round_count = 0;
        restart = 1;
        $display("%d", trip_count);

        tau_final = random_value();
        val_in = random_value();
        for (i = 0; i < lastcoeff + 1; i = i + 1) begin
            c_in[i] = random_value();
        end
        for (i = 0; i < ncopybits; i = i + 1) begin
            z2_vals[i] = random_value();
            w3_vals[i] = random_value();
        end
        for (i = 0; i < noutbits; i = i + 1) begin
            z1_vals[i] = random_value();
        end
        for (i = 0; i < ninbits; i = i + 1) begin
            w1_vals[i] = random_value();
            w2_vals[i] = random_value();
        end
    end else begin
        round_count = round_count + 1;
    end

    if (trip_count == 7) begin
        $finish;
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

endmodule
