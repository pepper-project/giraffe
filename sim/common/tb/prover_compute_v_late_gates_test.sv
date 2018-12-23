// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// test
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "prover_compute_v_late_gates.sv"

module test ();

localparam ngates = 8;
localparam ninputs = 8;
localparam [`GATEFN_BITS*ngates-1:0] gates_fn = {`GATEFN_MUL, `GATEFN_ADD, `GATEFN_MUL, `GATEFN_ADD, `GATEFN_MUL, `GATEFN_ADD, `GATEFN_MUL, `GATEFN_ADD};
localparam ninbits = $clog2(ninputs);
localparam [(ngates*ninbits)-1:0] gates_in0 = {3'b000, 3'b001, 3'b010, 3'b011, 3'b100, 3'b101, 3'b110, 3'b111};
localparam [(ngates*ninbits)-1:0] gates_in1 = {3'b111, 3'b110, 3'b101, 3'b100, 3'b011, 3'b010, 3'b001, 3'b000};

integer rseed, i, j;
integer round_count, trip_count;
reg clk, rstb, en, restart, trig;
wire ready_pulse;

reg [`F_NBITS-1:0] tau, m_tau_p1;
reg [`F_NBITS-1:0] v_in0 [ninputs-1:0] [1:0];
reg [`F_NBITS-1:0] v_in1 [ninputs-1:0];
reg [`F_NBITS-1:0] z1_chi [ngates-1:0];
reg [`F_NBITS-1:0] beta_in;
wire [`F_NBITS-1:0] c_out [2:0];

reg [`F_NBITS-1:0] wpred [ngates-1:0];
reg [`F_NBITS-1:0] compute_out [2:0];

prover_compute_v_late_gates
    #( .ngates          (ngates)
     , .ninputs         (ninputs)
     , .nmuxsels        (1)
     , .gates_fn        (gates_fn)
     , .gates_in0       (gates_in0)
     , .gates_in1       (gates_in1)
     , .gates_mux       (1'b0)
     ) iCompute
     ( .clk             (clk)
     , .rstb            (rstb)
     , .en              (en | trig)
     , .restart         (restart | trig)
     , .tau             (tau)
     , .m_tau_p1        (m_tau_p1)
     , .v_in0           (v_in0)
     , .v_in1           (v_in1)
     , .z1_chi          (z1_chi)
     , .beta_in         (beta_in)
     , .mux_sel         (1'b0)
     , .ready           ()
     , .ready_pulse     (ready_pulse)
     , .c_out           (c_out)
     );

wire [`F_NBITS-1:0] v_in0_dump [2*ninputs-1:0];
genvar XNum;
generate
    for (XNum = 0; XNum < ninputs; XNum = XNum + 1) begin: VIn0DumpHookup
        assign v_in0_dump[2*XNum] = v_in0[XNum][0];
        assign v_in0_dump[2*XNum+1] = v_in0[XNum][1];
    end
endgenerate

initial begin
    $dumpfile("prover_compute_v_late_gates_test.fst");
    $dumpvars;
    for (i = 0; i < ninputs; i = i + 1) begin
        $dumpvars(0, v_in1[i]);
    end
    for (i = 0; i < 2*ninputs; i = i + 1) begin
        $dumpvars(0, v_in0_dump[i]);
    end
    for (i = 0; i < ngates; i = i + 1) begin
        $dumpvars(0, z1_chi[i], wpred[i], iCompute.iAddT.in[i]);
    end
    for (i = 0; i < 3; i = i + 1) begin
        $dumpvars(0, c_out[i], iCompute.mul_out[i]);
    end
    rseed = 12345;  // And change the combination on my luggage!
    round_count = 2 * ninbits + 1;
    trip_count = -1;
    clk = 0;
    rstb = 0;
    trig = 0;
    en = 0;
    restart = 0;
    recompute_vals();
    #1 rstb = 1;
    clk = 1;
    #2 trig = 1;
    #2 trig = 0;
    #10000 $finish;
end

`ALWAYS_FF @(posedge clk) begin
    if (en | trig) begin
        restart <= 1'b0;
    end
    en <= ready_pulse;
    if (ready_pulse) begin
        recompute_vals();
    end
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

task recompute_vals;
    integer i, j, bit1_val, bit2_val;
    reg [2*`F_NBITS:0] tmp1, tmp2, tmp3;
    reg [2*ninbits-1:0] id_reg;
begin
    if (round_count < 2 * ninbits) begin
        $display("***");
        for (i = 0; i < 3; i = i + 1) begin
            case (i)
                0, 1: begin
                    tmp2 = i;
                end

                2: begin
                    tmp2 = `F_M1;
                end
            endcase
            tmp1 = c_out[2];
            for (j = 1; j >= 0; j = j - 1) begin
                tmp1 = (tmp1 * tmp2) % `F_Q;
                tmp1 = (tmp1 + c_out[j]) % `F_Q;
            end
            $display("%h %h %s", tmp1[`F_NBITS-1:0], compute_out[i], tmp1 == compute_out[i] ? ":)" : "!!!!!!");
        end
    end

    if (round_count >= 2 * ninbits - 1) begin
        restart = 1'b1;
        round_count = 0;
        trip_count = trip_count + 1;
        randomize_in_chi(1);
    end else begin
        round_count = round_count + 1;
        randomize_in_chi(0);
    end

    if (trip_count > 7) begin
        $finish;
    end

    compute_out[0] = {(`F_NBITS){1'b0}};
    compute_out[1] = {(`F_NBITS){1'b0}};
    compute_out[2] = {(`F_NBITS){1'b0}};
    for (i = 0; i < ngates; i = i + 1) begin
        id_reg = (i << ninbits) | (7 - i);
        bit1_val = (id_reg >> (round_count - 1)) & 1'b1;
        bit2_val = (id_reg >> round_count) & 1'b1;

        if (round_count == 0) begin
            wpred[i] = z1_chi[i];
        end else begin
            tmp1 = (wpred[i] * (bit1_val ? tau : m_tau_p1)) % `F_Q;
            wpred[i] = tmp1;
        end
        tmp3 = (wpred[i] * (bit2_val ? `F_M1 : 2)) % `F_Q;

        if (round_count < ninbits) begin
            if ((i % 2) == 1) begin
                tmp1 = (v_in0[7-i][0] * v_in1[i]) % `F_Q;
                tmp2 = (v_in0[7-i][1] * v_in1[i]) % `F_Q;
            end else begin
                tmp1 = (v_in0[7-i][0] + v_in1[i]) % `F_Q;
                tmp2 = (v_in0[7-i][1] + v_in1[i]) % `F_Q;
            end
        end else begin
            if ((i % 2) == 1) begin
                tmp1 = (v_in0[i][0] * v_in1[0]) % `F_Q;
                tmp2 = (v_in0[i][1] * v_in1[0]) % `F_Q;
            end else begin
                tmp1 = (v_in0[i][0] + v_in1[0]) % `F_Q;
                tmp2 = (v_in0[i][1] + v_in1[0]) % `F_Q;
            end
        end
        tmp1 = (tmp1 * wpred[i]) % `F_Q;
        tmp2 = (tmp2 * tmp3) % `F_Q;

        if (bit2_val) begin
            tmp3 = (compute_out[1] + tmp1) % `F_Q;
            compute_out[1] = tmp3;
        end else begin
            tmp3 = (compute_out[0] + tmp1) % `F_Q;
            compute_out[0] = tmp3;
        end
        tmp3 = (compute_out[2] + tmp2) % `F_Q;
        compute_out[2] = tmp3;
    end
    for (i = 0; i < 3; i = i + 1) begin
        tmp1 = (compute_out[i] * beta_in) % `F_Q;
        compute_out[i] = tmp1;
    end
end
endtask

task randomize_in_chi;
    input full;
    integer full;
    integer i, j;
    reg [2*`F_NBITS:0] tmp;
begin
    tmp = random_value();
    tau = tmp;
    tmp = (~tmp + `F_Q_P2_MI) % `F_Q;
    m_tau_p1 = tmp;
    for (i = 0; i < ninputs; i = i + 1) begin
        v_in1[i] = random_value();
        v_in0[i][0] = random_value();
        v_in0[i][1] = random_value();
    end
    if (full == 1) begin
        beta_in = random_value();
        for (i = 0; i < ngates; i = i + 1) begin
            z1_chi[i] = random_value();
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

endmodule
