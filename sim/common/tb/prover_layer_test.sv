// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// basic test for prover_layer
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "prover_layer.sv"

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
reg clk, rstb, en, trig, ready_dly;
reg [`F_NBITS-1:0] v_in [ncopies-1:0] [ninputs-1:0];
reg [`F_NBITS-1:0] z1_chi [ngates-1:0];
reg [`F_NBITS-1:0] z2 [ncopybits-1:0], m_z2_p1 [ncopybits-1:0];
reg [`F_NBITS-1:0] tau;

wire z1_chi_out_ready;
wire [`F_NBITS-1:0] z1_chi_out [ninputs-1:0], z2_out [ncopybits-1:0], m_z2_p1_out [ncopybits-1:0];
wire [`F_NBITS-1:0] coeff_out [lastcoeff:0];
wire ready, cubic, z2_out_ready;
wire ready_pulse = ready & ~ready_dly;

prover_layer
   #( .nInputs      (ninputs)
    , .nGates       (ngates)
    , .nMuxSels     (1)
    , .nCopyBits    (ncopybits)
    , .plStages     (0)
    , .nParBits     (nparbits)
    , .gates_fn     (gates_fn)
    , .gates_in0    (gates_in0)
    , .gates_in1    (gates_in1)
    , .gates_mux    (0)
    ) iLayer
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en | trig)
    , .restart      (trig)
    , .mux_sel      (1'b0)
    , .v_in         (v_in)
    , .z1_chi_in_ready  (1'b1)
    , .z1_chi       (z1_chi)
    , .z2           (z2)
    , .m_z2_p1      (m_z2_p1)
    , .z1_chi_out_ready (z1_chi_out_ready)
    , .z1_chi_out   (z1_chi_out)
    , .z2_out_ready (z2_out_ready)
    , .z2_out       (z2_out)
    , .m_z2_p1_out  (m_z2_p1_out)
    , .tau          (tau)
    , .coeff_out    (coeff_out)
    , .ready        (ready)
    , .cubic        (cubic)
    );

initial begin
    $dumpfile("prover_layer_test.fst");
    $dumpvars;
    for (i = 0; i < ninputs; i = i + 1) begin
        $dumpvars(0, z1_chi_out[i]);
    end
    for (i = 0; i < ncopybits; i = i + 1) begin
        $dumpvars(0, z2_out[i], m_z2_p1_out[i]);
    end
    for (i = 0; i < lastcoeff + 1; i = i + 1) begin
        $dumpvars(0, coeff_out[i]);
    end
    rseed = 3;
    round_count = ncopybits + 2 * ninbits;
    trip_count = 0;
    clk = 0;
    rstb = 0;
    trig = 0;
    ready_dly = 1;
    randomize_inputs();
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
    end
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

task randomize_inputs;
    integer i, j;
begin
    tau = random_value();

    if (round_count == (ncopybits + 2 * ninbits)) begin
        trip_count = trip_count + 1;
        $display("%d", trip_count);
        round_count = 0;
        for (i = 0; i < ncopies; i = i + 1) begin
            for (j = 0; j < ninputs; j = j + 1) begin
                v_in[i][j] = random_value();
            end
        end
        for (i = 0; i < ngates; i = i + 1) begin
            z1_chi[i] = random_value();
        end
        for (i = 0; i < ncopybits; i = i + 1) begin
            z2[i] = random_value();
            m_z2_p1[i] = random_value();
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
