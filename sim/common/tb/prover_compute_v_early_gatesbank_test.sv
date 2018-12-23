// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// test
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`include "prover_compute_v_early_gatesbank.sv"

module test ();

localparam nCopyBits = 4;
localparam nParBits = 3;
localparam nBetaPer = 1 << (nCopyBits - nParBits - 1);
localparam numRounds = nBetaPer;
localparam numRepeats = 3;
localparam numRuns = 7;

localparam nCopies = 1 << nCopyBits;
localparam nCopiesH = 1 << (nCopyBits - 1);

localparam nParallel = 1 << nParBits;

localparam ngates = 8;
localparam ninputs = 8;
localparam [`GATEFN_BITS*ngates-1:0] gates_fn = {`GATEFN_MUL, `GATEFN_ADD, `GATEFN_MUL, `GATEFN_ADD, `GATEFN_MUL, `GATEFN_ADD, `GATEFN_MUL, `GATEFN_ADD};
localparam ninbits = $clog2(ninputs);
localparam [(ngates*ninbits)-1:0] gates_in0 = {3'b000, 3'b001, 3'b010, 3'b011, 3'b100, 3'b101, 3'b110, 3'b111};
localparam [(ngates*ninbits)-1:0] gates_in1 = {3'b111, 3'b110, 3'b101, 3'b100, 3'b011, 3'b010, 3'b001, 3'b000};

integer rseed, i, j, round_num, round_next, repeat_num, repeat_next, run_num, run_next;
reg clk, rstb;
reg en, en_next, interp_en, interp_next, beta_en, beta_next, trig;
wire [nParallel-1:0] in_ready;
wire out_ready;
wire ready = &(in_ready) & out_ready;
//wire ready_pulse = ready & ~ready_dly;

reg [`F_NBITS-1:0] z1_chi [ngates-1:0];
reg [`F_NBITS-1:0] v_in [nParallel-1:0] [ninputs-1:0] [3:0];
reg [`F_NBITS-1:0] beta_in_even [nCopiesH-1:0], beta_in_odd[nCopiesH-1:0], point3_in [nCopiesH-1:0], point4_in [nCopiesH-1:0];
wire [`F_NBITS-1:0] v_out [3:0];

reg [`F_NBITS-1:0] v_out_compute_0;
reg [`F_NBITS-1:0] v_out_compute_1;
reg [`F_NBITS-1:0] v_out_compute_2;
reg [`F_NBITS-1:0] v_out_compute_3;

enum { ST_IDLE, ST_RESTART, ST_START, ST_RUNNING, ST_INTERP, ST_CHECK, ST_FINISH } state_reg, state_next;

initial begin
    $dumpfile("pergate_compute_gatefn_early_test.fst");
    $dumpvars;
    for (i = 0; i < nParallel; i = i + 1) begin
        $dumpvars(0, iCompute.iAddT.in[i]);
        // $dumpvars(0, beta_in[i]);
        // $dumpvars(0, mul_out[i]);
    end
    for (i = 0; i < 4; i = i + 1) begin
        $dumpvars(0, iCompute.accum_out[i]);
        $dumpvars(0, v_out[i]);
        // $dumpvars(0, iCompute.iAddT.in[i]);
    end
    /*
    for (i = 0; i < ninputs * 4; i = i + 1) begin
        $dumpvars(0, v_in_flat[i]);
    end
    */
    rseed = 1337;
    trig = 0;
    rstb = 1;
    #1 rstb = 0;
    #3 rstb = 1;
    #2 trig = 1;
    #3 trig = 0;
end

integer CompC;
`ALWAYS_COMB begin
    en_next = 1'b0;
    beta_next = 1'b0;
    interp_next = 1'b0;
    state_next = state_reg;
    round_next = round_num;
    repeat_next = repeat_num;
    run_next = run_num;

    case (state_reg)
        ST_IDLE: begin
            if (trig) begin // TODO is trig the right thing here?
                run_next = 0;
                round_next = 0;
                repeat_next = 0;
                state_next = ST_RESTART;
            end
        end

        ST_RESTART: begin
            randomize_inputs(1);
            beta_next = 1'b1;
            state_next = ST_START;
        end

        ST_START: begin
            en_next = 1'b1;
            state_next = ST_RUNNING;
            if (~beta_en) begin
                randomize_inputs(0);
            end
        end

        ST_RUNNING: begin
            if (~en & ready) begin
                if (round_num == numRounds - 1) begin
                    round_next = 0;
                    if (repeat_num == numRepeats - 1) begin
                        repeat_next = 0;
                        interp_next = 1'b1;
                        state_next = ST_INTERP;
                    end else begin
                        repeat_next = repeat_num + 1;
                        state_next = ST_START;
                    end
                end else begin
                    round_next = round_num + 1;
                    state_next = ST_START;
                end
            end
        end

        ST_INTERP: begin
            if (~interp_en & ready) begin
                state_next = ST_CHECK;
            end
        end

        ST_CHECK: begin
            check_outputs();
            if (run_num == numRuns - 1) begin
                state_next = ST_FINISH;
            end else begin
                run_next = run_num + 1;
                state_next = ST_RESTART;
            end
        end

        ST_FINISH: begin
            $finish;
        end

    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        state_reg <= ST_IDLE;
        en <= 1'b0;
        interp_en <= 1'b0;
        beta_en <= 1'b0;
        round_num <= 0;
        repeat_num <= 0;
        run_num <= 0;
    end else begin
        state_reg <= state_next;
        en <= en_next;
        interp_en <= interp_next;
        beta_en <= beta_next;
        round_num <= round_next;
        repeat_num <= repeat_next;
        run_num <= run_next;
    end
end

`ALWAYS_FF @(clk or rstb) begin
    if (~rstb) begin
        clk <= 1'b1;
    end else begin
        clk <= #1 ~clk;
    end
end

prover_compute_v_early_gatesbank
    #( .nParBits    (nParBits)
     , .nCopyBits   (nCopyBits)
     , .ngates      (ngates)
     , .ninputs     (ninputs)
     , .nmuxsels    (1)
     , .gates_fn    (gates_fn)
     , .gates_in0   (gates_in0)
     , .gates_in1   (gates_in1)
     , .gates_mux   (1'b0)
     ) iCompute
     ( .clk         (clk)
     , .rstb        (rstb)
     , .beta_en     ({(4){beta_en}})
     , .en          ({(nParallel){en}})
     , .interp_en   (interp_en)
     , .v_in        (v_in)
     , .z1_chi      (z1_chi)
     , .beta_in_even(beta_in_even)
     , .beta_in_odd (beta_in_odd)
     , .point3_in   (point3_in)
     , .point4_in   (point4_in)
     , .mux_sel     (1'b0)
     , .in_ready    (in_ready)
     , .out_ready   (out_ready)
     , .out_ready_pulse ()
     , .c_out       (v_out)
     );

task randomize_inputs;
    input all;
    integer i, j, k, all;
    reg [`F_NBITS-1:0] tmp;
begin
    if (all != 0) begin
        for (i = 0; i < ngates; i = i + 1) begin
            z1_chi[i] = random_value();
        end
        for (i = 0; i < nCopiesH; i = i + 1) begin
            beta_in_even[i] = random_value();
            beta_in_odd[i] = random_value();
            point3_in[i] = random_value();
            point4_in[i] = random_value();
        end
        v_out_compute_0 = {(`F_NBITS){1'b0}};
        v_out_compute_1 = {(`F_NBITS){1'b0}};
        v_out_compute_2 = {(`F_NBITS){1'b0}};
        v_out_compute_3 = {(`F_NBITS){1'b0}};
    end

    for (i = 0; i < 4; i = i + 1) begin
        for (j = 0; j < ninputs; j = j + 1) begin
            for (k = 0; k < nParallel; k = k + 1) begin
                v_in[k][j][i] = random_value();
            end
        end
    end

    update_outputs();
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
    reg [`F_NBITS-1:0] val;
    reg [2*`F_NBITS:0] tmp;
    reg [`F_NBITS-1:0] tmp2, tmp3;
begin
    $display("***");
    for (i = 0; i < 4; i = i + 1) begin
        case (i)
            0, 1: begin
                val = i;
            end

            2: begin
                val = `F_M1;
            end

            3: begin
                val = 2;
            end
        endcase
        tmp = v_out[3];
        for (j = 2; j >= 0; j = j - 1) begin
            tmp = (tmp * val) % `F_Q;
            tmp = (tmp + v_out[j]) % `F_Q;
        end
        tmp2 = tmp;
        case (i)
            0: begin
                tmp3 = v_out_compute_0;
            end
            1: begin
                tmp3 = v_out_compute_1;
            end
            2: begin
                tmp3 = v_out_compute_2;
            end
            3: begin
                tmp3 = v_out_compute_3;
            end
        endcase
        $display("%h %h %s", tmp3, tmp2, tmp3 == tmp2 ? ":)" : "!!!!!!");
    end
end
endtask

task update_outputs;
    integer i, j, k, offset;
    reg [2*`F_NBITS:0] tmp;
    reg [`F_NBITS-1:0] compute_out [3:0];
    reg [`F_NBITS-1:0] beta_vals [3:0];
begin
    for (k = 0; k < nParallel; k = k + 1) begin

        for (j = 0; j < 4; j = j + 1) begin
            compute_out[j] = {(`F_NBITS){1'b0}};
        end

        for (i = 0; i < ngates; i = i + 1) begin
            for (j = 0; j < 4; j = j + 1) begin
                tmp = 0;
                if (i % 2 == 1) begin
                    tmp = (v_in[k][ngates - 1 - i][j] * v_in[k][i][j]) % `F_Q;
                end else begin
                    tmp = (v_in[k][ngates - 1 - i][j] + v_in[k][i][j]) % `F_Q;
                end
                tmp = (tmp * z1_chi[i]) % `F_Q;
                tmp = (compute_out[j] + tmp) % `F_Q;
                compute_out[j] = tmp;
            end
        end

        offset = nBetaPer * k;

        beta_vals[0] = beta_in_even[offset + round_num];
        beta_vals[1] = beta_in_odd[offset + round_num];
        beta_vals[2] = point3_in[offset + round_num];
        beta_vals[3] = point4_in[offset + round_num];

        for (j = 0; j < 4; j = j + 1) begin
            tmp = (compute_out[j] * beta_vals[j]) % `F_Q;
            case (j)
                0: begin
                    tmp = (v_out_compute_0 + tmp) % `F_Q;
                    v_out_compute_0 = tmp;
                end
                1: begin
                    tmp = (v_out_compute_1 + tmp) % `F_Q;
                    v_out_compute_1 = tmp;
                end
                2: begin
                    tmp = (v_out_compute_2 + tmp) % `F_Q;
                    v_out_compute_2 = tmp;
                end
                3: begin
                    tmp = (v_out_compute_3 + tmp) % `F_Q;
                    v_out_compute_3 = tmp;
                end
            endcase
        end
    end
end
endtask

endmodule
