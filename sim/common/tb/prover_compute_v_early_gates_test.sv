// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// test
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "prover_compute_v_early_gates.sv"

module test ();

localparam ngates = 8;
localparam ninputs = 8;
localparam [`GATEFN_BITS*ngates-1:0] gates_fn = {`GATEFN_MUL, `GATEFN_ADD, `GATEFN_MUL, `GATEFN_ADD, `GATEFN_MUL, `GATEFN_ADD, `GATEFN_MUL, `GATEFN_ADD};
localparam ninbits = $clog2(ninputs);
localparam [(ngates*ninbits)-1:0] gates_in0 = {3'b000, 3'b001, 3'b010, 3'b011, 3'b100, 3'b101, 3'b110, 3'b111};
localparam [(ngates*ninbits)-1:0] gates_in1 = {3'b111, 3'b110, 3'b101, 3'b100, 3'b011, 3'b010, 3'b001, 3'b000};

integer rseed, i, j;
reg clk, rstb, en, trig, ready_dly, mask_en;
wire in_ready, out_ready;
wire ready = in_ready & out_ready;
wire ready_pulse = ready & ~ready_dly;
reg [`F_NBITS-1:0] z1_chi [ngates-1:0];
reg [`F_NBITS-1:0] v_in [ninputs-1:0] [3:0];
reg [`F_NBITS-1:0] beta_in [3:0];
wire [`F_NBITS-1:0] v_out [3:0];

prover_compute_v_early_gates
    #( .ngates      (ngates)
     , .ninputs     (ninputs)
     , .nmuxsels    (1)
     , .gates_fn    (gates_fn)
     , .gates_in0   (gates_in0)
     , .gates_in1   (gates_in1)
     , .gates_mux   (1'b0)
     ) iCompute
     ( .clk         (clk)
     , .rstb        (rstb)
     , .en          (en | trig)
     , .mask_en     (mask_en)
     , .v_in        (v_in)
     , .z1_chi      (z1_chi)
     , .beta_in     (beta_in)
     , .mux_sel     (1'b0)
     , .in_ready    (in_ready)
     , .out_ready   (out_ready)
     , .out_ready_pulse ()
     , .v_out       (v_out)
     );

wire [`F_NBITS-1:0] mul_out [3:0];
wire [`F_NBITS-1:0] v_in_flat[4*ninputs-1:0];
genvar Mul;
genvar Inp;
generate
    for (Mul = 0; Mul < 4; Mul = Mul + 1) begin
        assign mul_out[Mul] = iCompute.MulInst[Mul].mul_out;
        localparam offset = ninputs * Mul;
        for (Inp = 0; Inp < ninputs; Inp = Inp + 1) begin
            assign v_in_flat[Inp+offset] = v_in[Inp][Mul];
        end
    end
endgenerate

initial begin
    $dumpfile("pergate_compute_gatefn_early_test.fst");
    $dumpvars;
    for (i = 0; i < 4; i = i + 1) begin
        $dumpvars(0, v_out[i]);
        $dumpvars(0, beta_in[i]);
        $dumpvars(0, mul_out[i]);
    end
    for (i = 0; i < ngates; i = i + 1) begin
        $dumpvars(0, z1_chi[i]);
        $dumpvars(0, iCompute.iAddT.in[i]);
    end
    for (i = 0; i < ninputs * 4; i = i + 1) begin
        $dumpvars(0, v_in_flat[i]);
    end
    ready_dly = 1;
    rseed = 0;
    clk = 0;
    trig = 0;
    en = 0;
    rstb = 0;
    mask_en = 0;
    randomize_inputs();
    #1 rstb = 1;
    trig = 1;
    #1 clk = 1;
    #1 trig = 0;
    #1000 $finish;
end

`ALWAYS_FF @(posedge clk) begin
    ready_dly <= ready;
    en <= ready_pulse;
    mask_en <= en;
    if (ready_pulse) begin
        check_outputs();
        randomize_inputs();
    end
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

task randomize_inputs;
    integer i, j;
    reg [`F_NBITS-1:0] tmp;
begin
    for (i = 0; i < ngates; i = i + 1) begin
        z1_chi[i] = random_value();
    end
    for (i = 0; i < 4; i = i + 1) begin
        beta_in[i] = random_value();
        for (j = 0; j < ninputs; j = j + 1) begin
            v_in[j][i] = random_value();
        end
    end
end
endtask

function [`F_NBITS-1:0] random_value();
    reg [`F_NBITS-1:0] tmp;
begin
    tmp = $random(rseed);
    tmp = {tmp[31:0],32'b0} | $random(rseed);
    random_value = tmp;
end
endfunction

task check_outputs;
    integer i, j;
    reg [2*`F_NBITS:0] tmp;
    reg [`F_NBITS-1:0] compute_out [3:0];
begin
    $display("**");
    for (j = 0; j < 4; j = j + 1) begin
        compute_out[j] = {(`F_NBITS){1'b0}};
    end
    for (i = 0; i < ngates; i = i + 1) begin
        for (j = 0; j < 4; j = j + 1) begin
            tmp = 0;
            if (i % 2 == 1) begin
                tmp = (v_in[ngates - 1 - i][j] * v_in[i][j]) % `F_Q;
            end else begin
                tmp = (v_in[ngates - 1 - i][j] + v_in[i][j]) % `F_Q;
            end
            tmp = (tmp * z1_chi[i]) % `F_Q;
            tmp = (compute_out[j] + tmp) % `F_Q;
            compute_out[j] = tmp;
        end
    end
    for (j = 0; j < 4; j = j + 1) begin
        tmp = (compute_out[j] * beta_in[j]) % `F_Q;
        compute_out[j] = tmp;
        $display("%h %h %s", compute_out[j], v_out[j], compute_out[j] == v_out[j] ? ":)" : "!!!!!!");
    end
end
endtask

endmodule
