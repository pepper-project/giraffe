// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// special shift register for collapsing V computation
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_prover_compute_v_sr
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
`include "field_multiplier.sv"
`include "prover_compute_v_srelem.sv"
module prover_compute_v_sr
    #( parameter                nCopyBits = 2
     , parameter                posParallel = 0
     , parameter                totParallel = 1
// NOTE do not override below this line //
     , parameter                nCopies = 1 << nCopyBits
    )( input                    clk
     , input                    rstb

     , input                    en
     , input                    restart

     , input  [`F_NBITS-1:0]    tau
     , input  [`F_NBITS-1:0]    m_tau_p1

     , input  [`F_NBITS-1:0]    in_vals [nCopies-1:0]

     , output [`F_NBITS-1:0]    out [3:0]

     , input  [`F_NBITS-1:0]    even_in         // NOTE you should short this to pass_out if posParallel == 0!
     , input                    even_in_ready   // NOTE you should short this to pass_out_ready if posParallel == 0!
     , input  [`F_NBITS-1:0]    odd_in
     , input                    odd_in_ready

     , output [`F_NBITS-1:0]    pass_out
     , output                   pass_out_ready

     , input                    gates_ready
     , output                   gates_en

     , output                   ready_pulse
     , output                   ready
     );

// sanity check
generate
    if (nCopyBits < 2) begin: IErr1
        Error_nCopyBits_must_be_at_least_two_in_prover_compute_v_sr __error__();
    end
    if (posParallel < 0) begin: IErr2
        Error_posParallel_must_be_nonnegative_in_prover_compute_v_sr __error__();
    end
    if (totParallel <= posParallel) begin: IErr3
        Error_totParallel_must_be_greater_than_posParallel_in_prover_compute_v_sr __error__();
    end
    if (nCopies != (1 << nCopyBits)) begin: IErr4
        Error_do_not_override_nCopies_in_prover_compute_v_sr __error__();
    end
endgenerate

localparam integer nEvenOdd = 1 << (nCopyBits - 1);
localparam integer numFinalRuns = 1 + $clog2(totParallel) - $clog2(posParallel + 1);

reg [nCopies-1:0] count_reg, count_next;
reg [nCopies-1:0] bpsel_reg, bpsel_next;
reg load_reg, load_next;
reg load_final_reg, load_final_next;
reg shen_reg, shen_next;
reg shfin_reg, shfin_next;
reg gates_reg, gates_next;
reg gates_started;
assign gates_en = gates_reg;
wire [`F_NBITS-1:0] evens [nEvenOdd-1:0];
wire [`F_NBITS-1:0] odds [nEvenOdd-1:0];

reg [`F_NBITS-1:0] out_reg [3:0], out_next [3:0];
reg [`F_NBITS-1:0] out_s_reg [3:0];
assign out = out_s_reg;

reg [2:0] add_en_reg, add_en_next;
wire any_add_en = |(add_en_reg);
reg [`F_NBITS-1:0] add_in0_reg [2:0], add_in0_next [2:0];
reg [`F_NBITS-1:0] add_in1_reg [2:0], add_in1_next [2:0];
wire [2:0] add_ready;
wire all_add_ready = &(add_ready);
wire [`F_NBITS-1:0] add_out [2:0];

// adder[2] is the one we'll use for the combining result
wire [`F_NBITS-1:0] bypass_val = add_out[2];

// data passed to successors
reg prdy_reg, prdy_next;
reg [`F_NBITS-1:0] pout_reg, pout_next;
generate
    if (totParallel == 1) begin: LoneHookup
        assign pass_out = evens[0];
        assign pass_out_ready = ready & ~&(bpsel_reg);
    end else begin
        assign pass_out = pout_reg;
        assign pass_out_ready = prdy_reg;
    end
endgenerate

reg [1:0] mul_en_reg, mul_en_next;
wire any_mul_en = |(mul_en_reg);
wire [`F_NBITS-1:0] mul_in0 [1:0];
wire [`F_NBITS-1:0] mul_in1 [1:0];
assign mul_in0[0] = evens[0];
assign mul_in0[1] = odds[0];
assign mul_in1[0] = mtaup1_reg;
assign mul_in1[1] = tau_reg;
wire [1:0] mul_ready;
wire all_mul_ready = &(mul_ready);
wire [`F_NBITS-1:0] mul_out [1:0];

reg [`F_NBITS-1:0] tau_reg, tau_next;
reg [`F_NBITS-1:0] mtaup1_reg, mtaup1_next;

enum { ST_IDLE, ST_WAIT_START, ST_WAIT, ST_LD0, ST_LD1, ST_LD2, ST_LD3_START, ST_LD3, ST_NORM0, ST_NORM1, ST_NORM2, ST_NORM3, ST_NORM4, ST_NORM5, ST_NORM6, ST_NORM7_START, ST_NORM7, ST_FIN0, ST_FIN1 } state_reg, state_next;

reg en_dly, ready_dly;
wire start = en & ~en_dly;
assign ready = (state_reg == ST_IDLE) & ~start;
assign ready_pulse = ready & ~ready_dly;

integer InstNumC;
`ALWAYS_COMB begin
    shen_next = 1'b0;
    shfin_next = 1'b0;
    mul_en_next = 2'b0;
    add_en_next = 3'b0;
    load_next = 1'b0;
    gates_next = 1'b0;
    count_next = count_reg;
    bpsel_next = bpsel_reg;
    mtaup1_next = mtaup1_reg;
    tau_next = tau_reg;
    state_next = state_reg;
    prdy_next = prdy_reg;
    pout_next = pout_reg;
    for (InstNumC = 0; InstNumC < 4; InstNumC = InstNumC + 1) begin
        out_next[InstNumC] = out_reg[InstNumC];
    end
    for (InstNumC = 0; InstNumC < 3; InstNumC = InstNumC + 1) begin
        add_in0_next[InstNumC] = add_in0_reg[InstNumC];
        add_in1_next[InstNumC] = add_in1_reg[InstNumC];
    end

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                prdy_next = 1'b0;
                for (InstNumC = 0; InstNumC < 4; InstNumC = InstNumC + 1) begin
                    out_next[InstNumC] = {(`F_NBITS){1'b0}};
                end
                if (restart) begin
                    // restart case: we only do the 3rd and 4th point comps
                    shen_next = 1'b1;
                    load_next = 1'b1;
                    bpsel_next = {1'b1, {(nCopies-1){1'b0}}};
                    count_next = {{(nEvenOdd-1){1'b0}},1'b1,{(nEvenOdd){1'b0}}};
                    state_next = ST_LD0;
                end else if (bpsel_reg[0]) begin
                    // the "last time through" case
                    tau_next = tau;
                    mtaup1_next = m_tau_p1;
                    count_next = count_reg + 1;
                    state_next = ST_NORM0;
                end else if (|(bpsel_reg)) begin
                    // the "normal" case
                    // run until count_next intersects bpsel_next
                    count_next = {{(nCopies-1){1'b0}},1'b1};
                    tau_next = tau;
                    mtaup1_next = m_tau_p1;
                    state_next = ST_NORM0;
                end
            end
        end

        ST_FIN0: begin
            if (all_add_ready & ~any_add_en) begin
                prdy_next = 1'b1;
                pout_next = add_out[2];

                if (count_reg == numFinalRuns) begin
                    // in the final-final run, we don't run the gates, so we're done
                    state_next = ST_WAIT;
                    bpsel_next = {(nCopies){1'b0}};
                end else begin
                    state_next = ST_FIN1;
                end
            end
        end

        ST_FIN1: begin
            if (odd_in_ready & even_in_ready) begin
                out_next[0] = even_in;
                out_next[1] = odd_in;
                shfin_next = 1'b1;

                // reuse the LD0 machinery
                state_next = ST_LD0;
            end
        end

        ST_NORM0: begin
            // start computing even[0] * (1-tau) + odd[0] * tau
            mul_en_next = 2'b11;
            state_next = ST_NORM1;
        end

        ST_NORM1, ST_NORM4: begin
            if (all_add_ready & ~any_add_en & all_mul_ready & ~any_mul_en) begin
                // sum result --- can't do anything else right now...
                add_in0_next[2] = mul_out[0];
                add_in1_next[2] = mul_out[1];
                add_en_next[2] = 1'b1;

                if (bpsel_reg[0]) begin
                    state_next = ST_FIN0;
                end else if (state_reg == ST_NORM1) begin
                    state_next = ST_NORM2;
                end else begin
                    // save off intermediate point3 and point4 vals
                    out_next[2] = add_out[0];
                    out_next[3] = add_out[1];
                    state_next = ST_NORM5;
                end
            end
        end

        ST_NORM2, ST_NORM5: begin
            if (all_add_ready & ~any_add_en) begin
                // read combined value out of adder
                shen_next = 1'b1;
                // compute 2*combined
                add_in0_next[0] = add_out[2][`F_NBITS-1] ? `F_I : {(`F_NBITS){1'b0}};
                add_in1_next[0] = {add_out[2][`F_NBITS-2:0], 1'b0};
                add_en_next[0] = 1'b1;
                // combined -1*combined
                add_in0_next[1] = `F_Q_P1_MI;
                add_in1_next[1] = ~add_out[2];
                add_en_next[1] = 1'b1;

                if (state_reg == ST_NORM2) begin
                    out_next[0] = add_out[2];
                    state_next = ST_NORM3;
                end else begin
                    out_next[1] = add_out[2];
                    state_next = ST_NORM6;
                end
            end
        end

        ST_NORM3: begin
            if (~shen_reg) begin
                // update counter and bpsel
                bpsel_next = {1'b0, bpsel_reg[nCopies-1:1]};
                count_next = {count_reg[nCopies-2:0], 1'b0};
                // start on next pair!
                mul_en_next = 2'b11;

                state_next = ST_NORM4;
            end
        end

        ST_NORM6: begin
            if (all_add_ready & ~any_add_en) begin
                // sum up point3 components
                add_in0_next[0] = out_reg[2];
                add_in1_next[0] = add_out[1];
                add_en_next[0] = 1'b1;
                // sum up point4 components
                add_in0_next[1] = out_reg[3];
                add_in1_next[1] = add_out[0];
                add_en_next[1] = 1'b1;

                state_next = ST_NORM7_START;
            end
        end

        ST_NORM7_START: begin
            if (gates_started) begin
                state_next = ST_NORM7;
            end
        end

        ST_NORM7: begin
            if (all_add_ready & ~any_add_en & gates_ready & ~gates_reg) begin
                // update bpsel (counter update depends...
                bpsel_next = {1'b0, bpsel_reg[nCopies-1:1]};

                // store away computations for point3 and point4
                out_next[2] = add_out[0];
                out_next[3] = add_out[1];
                // start gates computing
                gates_next = 1'b1;

                if (count_reg == bpsel_reg) begin
                    state_next = ST_WAIT_START;
                end else begin
                    state_next = ST_NORM0;
                end

                if (bpsel_reg[1]) begin
                    count_next = {(nCopies){1'b0}};
                end else begin
                    count_next = {count_reg[nCopies-2:0], 1'b0};
                end
            end
        end

        ST_WAIT_START: begin
            if (gates_started) begin
                state_next = ST_WAIT;
            end
        end

        ST_WAIT: begin
            if (all_add_ready & ~any_add_en & all_mul_ready & ~any_mul_en & gates_ready & ~gates_reg) begin
                state_next = ST_IDLE;
            end
        end

        ST_LD0: begin
            if (~shen_reg & ~shfin_reg) begin
                // start computing point3
                // 2 * even
                add_in0_next[0] = evens[0][`F_NBITS-1] ? `F_I : {(`F_NBITS){1'b0}};
                add_in1_next[0] = {evens[0][`F_NBITS-2:0], 1'b0};
                add_en_next[0] = 1'b1;
                // -1 * odd
                add_in0_next[1] = `F_Q_P1_MI;
                add_in1_next[1] = ~(odds[0]);
                add_en_next[1] = 1'b1;

                state_next = ST_LD1;
            end
        end

        ST_LD1: begin
            if (all_add_ready & ~any_add_en) begin
                // finish computing point3
                add_in0_next[2] = add_out[0];
                add_in1_next[2] = add_out[1];
                add_en_next[2] = 1'b1;
                // start computing point4
                // 2 * odd
                add_in0_next[0] = odds[0][`F_NBITS-1] ? `F_I : {(`F_NBITS){1'b0}};
                add_in1_next[0] = {odds[0][`F_NBITS-2:0], 1'b0};
                add_en_next[0] = 1'b1;
                // -1 * even
                add_in0_next[1] = `F_Q_P1_MI;
                add_in1_next[1] = ~(evens[0]);
                add_en_next[1] = 1'b1;

                if (~bpsel_reg[0]) begin
                    // save these off and rotate
                    // except when we're in the final pass, in which
                    // case this has already been done for us
                    out_next[0] = evens[0];
                    out_next[1] = odds[0];
                    shen_next = 1'b1;
                end

                state_next = ST_LD2;
            end
        end

        ST_LD2: begin
            if (all_add_ready & ~any_add_en) begin
                // finish computing point4
                add_in0_next[2] = add_out[0];
                add_in1_next[2] = add_out[1];
                add_en_next[2] = 1'b1;
                // save point3
                out_next[2] = add_out[2];

                state_next = ST_LD3_START;
            end
        end

        ST_LD3_START: begin
            if (gates_started) begin
                state_next = ST_LD3;
            end
        end

        ST_LD3: begin
            if (all_add_ready & ~any_add_en & gates_ready & ~gates_reg) begin
                // save off point4
                out_next[3] = add_out[2];
                // start gates computing
                gates_next = 1'b1;

                if (count_reg[nCopies-1]) begin
                    bpsel_next = {1'b0, bpsel_reg[nCopies-1:1]};
                    state_next = ST_WAIT_START;
                end else if (bpsel_reg[0]) begin
                    state_next = ST_WAIT_START;
                end else begin
                    count_next = {count_reg[nCopies-2:0], 1'b0};
                    state_next = ST_LD0;
                end
            end
        end
    endcase
end

integer InstNumF;
`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        ready_dly <= 1'b1;
        count_reg <= {(nCopies){1'b0}};
        bpsel_reg <= {(nCopies){1'b0}};
        shen_reg <= 1'b0;
        shfin_reg <= 1'b0;
        load_reg <= 1'b0;
        gates_reg <= 1'b0;
        gates_started <= 1'b0;
        mul_en_reg <= 2'b0;
        add_en_reg <= 3'b0;
        prdy_reg <= 1'b0;
        pout_reg <= {(`F_NBITS){1'b0}};
        mtaup1_reg <= {(`F_NBITS){1'b0}};
        tau_reg <= {(`F_NBITS){1'b0}};
        state_reg <= state_next;
        for (InstNumF = 0; InstNumF < 4; InstNumF = InstNumF + 1) begin
            out_reg[InstNumF] <= {(`F_NBITS){1'b0}};
            out_s_reg[InstNumF] <= {(`F_NBITS){1'b0}};
        end
        for (InstNumF = 0; InstNumF < 3; InstNumF = InstNumF + 1) begin
            add_in0_reg[InstNumF] <= {(`F_NBITS){1'b0}};
            add_in1_reg[InstNumF] <= {(`F_NBITS){1'b0}};
        end
    end else begin
        en_dly <= en;
        ready_dly <= ready;
        count_reg <= count_next;
        bpsel_reg <= bpsel_next;
        shen_reg <= shen_next;
        shfin_reg <= shfin_next;
        load_reg <= load_next;
        gates_reg <= gates_next;
        gates_started <= gates_next ? 1'b0 : ((start | ~gates_ready) ? 1'b1 : gates_started);
        mul_en_reg <= mul_en_next;
        add_en_reg <= add_en_next;
        prdy_reg <= prdy_next;
        pout_reg <= pout_next;
        mtaup1_reg <= mtaup1_next;
        tau_reg <= tau_next;
        state_reg <= state_next;
        for (InstNumF = 0; InstNumF < 4; InstNumF = InstNumF + 1) begin
            out_reg[InstNumF] <= out_next[InstNumF];
            out_s_reg[InstNumF] <= gates_reg ? out_reg[InstNumF] : out_s_reg[InstNumF];
        end
        for (InstNumF = 0; InstNumF < 3; InstNumF = InstNumF + 1) begin
            add_in0_reg[InstNumF] <= add_in0_next[InstNumF];
            add_in1_reg[InstNumF] <= add_in1_next[InstNumF];
        end
    end
end

genvar SRNum;
genvar InstNum;
generate
    for (InstNum = 0; InstNum < 3; InstNum = InstNum + 1) begin: AddGen
        field_adder IAdd
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (add_en_reg[InstNum])
            , .a            (add_in0_reg[InstNum])
            , .b            (add_in1_reg[InstNum])
            , .ready_pulse  ()
            , .ready        (add_ready[InstNum])
            , .c            (add_out[InstNum])
            );
    end
    for (InstNum = 0; InstNum < 2; InstNum = InstNum + 1) begin: MulGen
        field_multiplier IMul
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (mul_en_reg[InstNum])
            , .a            (mul_in0[InstNum])
            , .b            (mul_in1[InstNum])
            , .ready_pulse  ()
            , .ready        (mul_ready[InstNum])
            , .c            (mul_out[InstNum])
            );
    end
    for (SRNum = 0; SRNum < nCopies; SRNum = SRNum + 1) begin: SRElmGen
        // hook up input and output wires
        wire [`F_NBITS-1:0] normal, out, in_alt, in_load;
        wire load_sig, shen_sig;
        localparam integer thisNum = SRNum >> 1;
        localparam integer predNum = (thisNum + 1) % nEvenOdd;
        if (SRNum % 2 == 0) begin: SREvenGen
            assign evens[thisNum] = out;
            assign normal = evens[predNum];
            assign in_alt = even_in;
        end else begin: SROddGen
            assign odds[thisNum] = out;
            assign normal = odds[predNum];
            assign in_alt = odd_in;
        end

        // bypass selector: last elem is never selected
        wire bpsel = (SRNum == nCopies - 1) ? 1'b0 : bpsel_reg[SRNum];

        if (thisNum == 0) begin: AltInHookup
            assign in_load = shfin_reg ? in_alt : in_vals[SRNum];
            assign load_sig = load_reg | shfin_reg;
            assign shen_sig = shen_reg | shfin_reg;
        end else begin: NormalHookup
            assign in_load = in_vals[SRNum];
            assign load_sig = load_reg;
            assign shen_sig = shen_reg;
        end

        prover_compute_v_srelem ISRElem
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (shen_sig)
            , .load         (load_sig)
            , .bypass       (bpsel)
            , .in_normal    (normal)
            , .in_load      (in_load)
            , .in_bypass    (bypass_val)
            , .out          (out)
            );
    end
endgenerate

endmodule
`define __module_prover_compute_v_sr
`endif // __module_prover_compute_v_sr
