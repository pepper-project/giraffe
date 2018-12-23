// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// compute all chi evals with "dynamic programming" method
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

// This block does "dynamic programming" computation of chi values.
// Streaming in omega values in MSB-to-LSB order, we compute (say, for 3)
//
// (1-w1) (1-w2) (1-w3)
// (  w1) (1-w2) (1-w3)
// (1-w1) (  w2) (1-w3)
// (  w1) (  w2) (1-w3)
// (1-w1) (1-w2) (  w3)
// (  w1) (1-w2) (  w3)
// (1-w1) (  w2) (  w3)
// (  w1) (  w2) (  w3)
//
// Then, streaming in tau values in LSB-to-MSB order, we "collapse"
// the constellation back into a single point:
//
// First round:
// (1-w1) (1-w2) (1-w3) * (1 - t1) +
// (  w1) (1-w2) (1-w3) *      t1  = v11
//
// (1-w1) (  w2) (1-w3) * (1 - t1) +
// (  w1) (  w2) (1-w3) *      t1  = v12
//
// (1-w1) (1-w2) (  w3) * (1 - t1) +
// (  w1) (1-w2) (  w3) *      t1  = v13
//
// (1-w1) (  w2) (  w3) * (1 - t1) +
// (  w1) (  w2) (  w3) *      t1  = v14
//
// Second round:
// v11 * (1 - t2) +
// v12 *      t2  = v21 * (1 - t3) +
//
// v13 * (1 - t2) +
// v14 *      t2  = v22 *      t3  = v31
//
// Third round:
// v21 * (1 - t3) +
// v22 *      t3  = v31
//

`ifndef __module_prover_compute_chi
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
`include "field_multiplier.sv"
module prover_compute_chi
   #( parameter npoints = 3
// NOTE do not override parameters below this line //
    , parameter noutputs = 1 << npoints
    , parameter ngates = 1 << (npoints - 1)
   )( input                 clk
    , input                 rstb

    , input                 en
    , input                 restart
    , input                 preload

    , input                 skip_pt3
    , input                 skip_pt4

    , input  [`F_NBITS-1:0] tau
    , input  [`F_NBITS-1:0] m_tau_p1

    , input  [`F_NBITS-1:0] chi_in [noutputs-1:0]

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] chi_out [noutputs-1:0]

    , output [`F_NBITS-1:0] point3_out [ngates-1:0]
    , output [`F_NBITS-1:0] point4_out [ngates-1:0]
    );
`include "func_leastSetBitPosn.sv"
`include "func_convertIntMtoL.sv"

// sanity checking
generate
    if (npoints < 2) begin: IErr1
        Error_npoints_must_be_at_least_two_in_prover_compute_chi __error__();
    end
    if (npoints != $clog2(noutputs)) begin: IErr2
        Error_do_not_override_noutputs_in_prover_compute_chi __error__();
    end
    if (npoints != $clog2(ngates) + 1) begin: IErr3
        Error_do_not_override_ngates_in_prover_compute_chi __error__();
    end
endgenerate

// ints for static hookups
integer GateNumF, GateNumC;

// retime tau and m_tau_p1
reg [`F_NBITS-1:0] tau_reg, tau_next;
reg [`F_NBITS-1:0] m_tau_p1_reg, m_tau_p1_next;
enum { PC_N, PC_3, PC_4 } pcomp_reg, pcomp_next;
wire pc_p3 = pcomp_reg == PC_3;
wire pc_p4 = pcomp_reg == PC_4;
wire pc_pn = pcomp_reg == PC_N;

// chi output registers
reg [`F_NBITS-1:0] chi_out_reg [noutputs-1:0], chi_out_next [noutputs-1:0];
reg [`F_NBITS-1:0] point3_reg [ngates-1:0], point3_next [ngates-1:0];
reg [`F_NBITS-1:0] point4_reg [ngates-1:0], point4_next [ngates-1:0];
genvar GateNum;
generate
    // real outputs: wire up chi_out
    for (GateNum = 0; GateNum < noutputs; GateNum = GateNum + 1) begin: ChiOutHookup
        assign chi_out[GateNum] = chi_out_reg[GateNum];
    end
    for (GateNum = 0; GateNum < ngates; GateNum = GateNum + 1) begin: PointXHookup
        assign point3_out[GateNum] = point3_reg[GateNum];
        assign point4_out[GateNum] = point4_reg[GateNum];
    end
endgenerate

// rounds and states
reg [npoints-1:0] rnd_reg, rnd_next;
wire [npoints-1:0] rnd_nxstep = {rnd_reg[npoints-2:0], ~rnd_reg[npoints-1]};
wire mid_round = rnd_reg == {(npoints){1'b1}};
wire first_round = rnd_reg == {(npoints){1'b0}};
wire premid_round = rnd_reg == {1'b0,{(npoints-1){1'b1}}};
wire final_round = rnd_reg == {1'b1,{(npoints-1){1'b0}}};
wire restart_int = restart | first_round;
wire chi_ready = rnd_reg[npoints-1];
enum { ST_IDLE, ST_LOAD, ST_MUL1, ST_MUL2, ST_TMUL1, ST_TMUL2, ST_TMUL3, ST_TADD } state_reg, state_next;
wire inST_MUL2 = state_reg == ST_MUL2;
wire inST_TMUL3 = state_reg == ST_TMUL3;
wire inST_TMUL2 = state_reg == ST_TMUL2;
wire inST_IDLE = state_reg == ST_IDLE;

// edge detect for enable
reg en_dly;
wire start = en & ~en_dly;
assign ready = inST_IDLE & ~start;
reg ready_dly;
assign ready_pulse = ready & ~ready_dly;

// multiplier and adder hookup
reg mul_en_reg, mul_en_next;
reg add_en_reg, add_en_next;
wire [`F_NBITS-1:0] mul_out [ngates-1:0];
wire [`F_NBITS-1:0] add_out [ngates-1:0];
wire [ngates-1:0] mul_ready, add_ready;
wire mul_idle = &(mul_ready);
wire add_idle = &(add_ready);
// instantiate multipliers and adders
generate
    for (GateNum = 0; GateNum < ngates; GateNum = GateNum + 1) begin: MulAddGen
        // generate masks for input selection
        localparam integer int_gate_num_MtoL = convertIntMtoL(GateNum, npoints);
        wire [npoints-1:0] gate_num_MtoL = int_gate_num_MtoL;
        localparam integer lsbP = leastSetBitPosn(GateNum, npoints - 1);
        localparam integer p1_in0_0_num = 2 * (GateNum & ~(1 << lsbP));
        localparam integer p1_in0_1_num = 2 * GateNum;

        // phase 1: figure out whether mul should be running
        localparam integer p1_mask_bits = npoints - lsbP;
        wire [npoints:0] p1_mask_0 = ((1 << (npoints + 1)) - 1) ^ ((1 << p1_mask_bits) - 1);
        wire p1_mul_en = &(p1_mask_0 | {rnd_reg[npoints-2:0], 2'b11}) & mul_en_reg;

        // phase 1: figure out whether we should use in0_0 or in0_1
        wire [npoints:0] p1_mask_1 = ((1 << (npoints + 1)) - 1) ^ ((1 << (p1_mask_bits + 1)) - 1);
        wire p1_use_in0_1 = &(p1_mask_1 | {rnd_reg[npoints-2:0], 2'b11});
        wire [`F_NBITS-1:0] p1_in0 = p1_use_in0_1 ? chi_out_reg[p1_in0_1_num] : chi_out_reg[p1_in0_0_num];

        // phase 1: figure out whether to use tau or m_tau_p1
        //wire p1_tau_1_sel = |((rnd_reg ^ {rnd_reg[npoints-2:0], 1'b1}) & {1'b0, gate_num_MtoL[npoints-1:1]});
        wire p1_tau_1_sel = ~p1_use_in0_1;  // happens that this is true; the above is equivalent
        wire p1_tau_2_sel = inST_MUL2;
        wire p1_tau_sel = premid_round ? p1_tau_2_sel : p1_tau_1_sel;

        // phase 2: inputs
        localparam integer p2_in0_0_num = 2 * GateNum;
        localparam integer p2_in0_1_num = 2 * GateNum + 1;
        localparam integer p2_in0_2_num = GateNum;
        wire p2_tau_2_sel = GateNum & 1'b1;
        wire p2_01_sel = inST_TMUL2;
        wire [`F_NBITS-1:0] p2_in0 = inST_TMUL3 ? chi_out_reg[p2_in0_2_num] :
                                        (p2_01_sel ? chi_out_reg[p2_in0_1_num] : chi_out_reg[p2_in0_0_num]);
        wire p2_tau_sel = inST_TMUL3 ? p2_tau_2_sel : p2_01_sel;

        // phase 2: when are we active
        wire p2_mul_en = ~|(~rnd_reg & gate_num_MtoL) & mul_en_reg;

        // mul hookups: select input and enable wires
        wire [`F_NBITS-1:0] mul_in0 = chi_ready ? p2_in0 : p1_in0;
        wire [`F_NBITS-1:0] mul_in1 = (chi_ready ? p2_tau_sel : p1_tau_sel) ? tau_reg : m_tau_p1_reg;
        wire mul_en = chi_ready ? p2_mul_en : p1_mul_en;

        field_multiplier imult
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (mul_en)
            , .a            (mul_in0)
            , .b            (mul_in1)
            , .ready_pulse  ()
            , .ready        (mul_ready[GateNum])
            , .c            (mul_out[GateNum])
            );

        // add hookups
        wire add_en = ~|(~rnd_reg & {1'b0, gate_num_MtoL[npoints-1:1]}) & add_en_reg;
        wire [`F_NBITS-1:0] add_in0, add_in1;

        wire [`F_NBITS-1:0] intermed_val_reg = pc_pn ? chi_out_reg[2 * GateNum]
                                                     : (pc_p3 ? point3_reg[GateNum] : point4_reg[GateNum]);
        if (GateNum < ngates / 2) begin: AddInSel
            wire add_in_sel = mid_round;
            assign add_in0 = add_in_sel ? mul_out[GateNum] : mul_out[2 * GateNum];
            assign add_in1 = add_in_sel ? intermed_val_reg : mul_out[2 * GateNum + 1];
        end else begin: AddInNoSel
            assign add_in0 = mul_out[GateNum];
            assign add_in1 = intermed_val_reg;
        end

        field_adder iadd
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (add_en)
            , .a            (add_in0)
            , .b            (add_in1)
            , .ready_pulse  ()
            , .ready        (add_ready[GateNum])
            , .c            (add_out[GateNum])
            );
    end
endgenerate

`ALWAYS_COMB begin
    rnd_next = rnd_reg;
    state_next = state_reg;
    tau_next = tau_reg;
    m_tau_p1_next = m_tau_p1_reg;
    mul_en_next = 1'b0;
    add_en_next = 1'b0;
    pcomp_next = pcomp_reg;
    for (GateNumC = 0; GateNumC < noutputs; GateNumC = GateNumC + 1) begin
        chi_out_next[GateNumC] = chi_out_reg[GateNumC];
    end
    for (GateNumC = 0; GateNumC < ngates; GateNumC = GateNumC + 1) begin
        point3_next[GateNumC] = point3_reg[GateNumC];
        point4_next[GateNumC] = point4_reg[GateNumC];
    end

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                if (preload) begin
                    rnd_next = {(npoints){1'b1}};
                    for (GateNumC = 0; GateNumC < noutputs; GateNumC = GateNumC + 1) begin
                        chi_out_next[GateNumC] = chi_in[GateNumC];
                    end
                    pcomp_next = PC_3;
                    tau_next = `F_M1;
                    m_tau_p1_next = {{(`F_NBITS-2){1'b0}}, 2'b10};
                    mul_en_next = 1'b1;
                    state_next = ST_TMUL1;
                end else begin
                    tau_next = tau;
                    m_tau_p1_next = m_tau_p1;
                    if (restart_int) begin
                        state_next = ST_LOAD;
                    end else if (chi_ready) begin
                        pcomp_next = PC_N;
                        mul_en_next = 1'b1;
                        if (mid_round) begin
                            state_next = ST_TMUL1;
                        end else begin
                            state_next = ST_TMUL3;
                        end
                    end else begin
                        mul_en_next = 1'b1;
                        if (premid_round) begin
                            state_next = ST_MUL2;
                        end else begin
                            state_next = ST_MUL1;
                        end
                    end
                end
            end
        end

        ST_LOAD: begin
            for (GateNumC = 0; GateNumC < noutputs; GateNumC = GateNumC + 1) begin
                if (GateNumC == 0) begin
                    chi_out_next[GateNumC] = m_tau_p1_reg;
                end else if (GateNumC == (1 << (npoints - 1))) begin
                    chi_out_next[GateNumC] = tau_reg;
                end else begin
                    chi_out_next[GateNumC] = {(`F_NBITS){1'b0}};
                end
            end

            rnd_next = {{(npoints-1){1'b0}},1'b1};
            state_next = ST_IDLE;
        end

        ST_MUL1: begin
            if (~mul_en_reg & mul_idle) begin
                for (GateNumC = 0; GateNumC < ngates; GateNumC = GateNumC + 1) begin
                    chi_out_next[2 * GateNumC] = mul_out[GateNumC];
                end

                rnd_next = rnd_nxstep;
                if (premid_round & ~skip_pt3) begin
                    // compute point3 and point4
                    pcomp_next = PC_3;
                    tau_next = `F_M1;
                    m_tau_p1_next = {{(`F_NBITS-2){1'b0}}, 2'b10};
                    mul_en_next = 1'b1;
                    state_next = ST_TMUL1;
                end else begin
                    state_next = ST_IDLE;
                end
            end
        end

        ST_MUL2: begin
            if (~mul_en_reg & mul_idle) begin
                for (GateNumC = 0; GateNumC < ngates; GateNumC = GateNumC + 1) begin
                    chi_out_next[2 * GateNumC + 1] = mul_out[GateNumC];
                end

                mul_en_next = 1'b1;
                state_next = ST_MUL1;
            end
        end

        ST_TMUL1: begin
            if (~mul_en_reg & mul_idle) begin
                for (GateNumC = 0; GateNumC < ngates; GateNumC = GateNumC + 1) begin
                    if (pc_p3) begin
                        point3_next[GateNumC] = mul_out[GateNumC];
                    end else if (pc_p4) begin
                        point4_next[GateNumC] = mul_out[GateNumC];
                    end else begin
                        chi_out_next[2 * GateNumC] = mul_out[GateNumC];
                    end
                end

                mul_en_next = 1'b1;
                state_next = ST_TMUL2;
            end
        end

        ST_TMUL2, ST_TMUL3: begin
            if (~mul_en_reg & mul_idle) begin
                add_en_next = 1'b1;
                state_next = ST_TADD;
            end
        end

        ST_TADD: begin
            if (~add_en_reg & add_idle) begin
                for (GateNumC = 0; GateNumC < ngates; GateNumC = GateNumC + 1) begin
                    if (pc_p3) begin
                        point3_next[GateNumC] = add_out[GateNumC];
                    end else if (pc_p4) begin
                        point4_next[GateNumC] = add_out[GateNumC];
                    end else begin
                        chi_out_next[GateNumC] = add_out[GateNumC];
                    end
                end

                if (pc_p3 & ~skip_pt4) begin
                    pcomp_next = PC_4;
                    tau_next = {{(`F_NBITS-2){1'b0}}, 2'b10};
                    m_tau_p1_next = `F_M1;
                    mul_en_next = 1'b1;
                    if (mid_round) begin
                        state_next = ST_TMUL1;
                    end else begin
                        state_next = ST_TMUL3;
                    end
                end else if (pc_p4 | (pc_p3 & skip_pt4)) begin
                    pcomp_next = PC_N;
                    state_next = ST_IDLE;
                end else begin
                    rnd_next = rnd_nxstep;
                    if (final_round | skip_pt3) begin
                        state_next = ST_IDLE;
                    end else begin
                        pcomp_next = PC_3;
                        tau_next = `F_M1;
                        m_tau_p1_next = {{(`F_NBITS-2){1'b0}}, 2'b10};
                        mul_en_next = 1'b1;
                        state_next = ST_TMUL3;
                    end
                end
            end
        end
    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        ready_dly <= 1'b1;
        rnd_reg <= {(npoints){1'b0}};
        state_reg <= ST_IDLE;
        tau_reg <= {(`F_NBITS){1'b0}};
        m_tau_p1_reg <= {(`F_NBITS){1'b0}};
        mul_en_reg <= 1'b0;
        add_en_reg <= 1'b0;
        pcomp_reg <= PC_N;
        for (GateNumF = 0; GateNumF < noutputs; GateNumF = GateNumF + 1) begin
            chi_out_reg[GateNumF] <= {(`F_NBITS){1'b0}};
        end
        for (GateNumF = 0; GateNumF < ngates; GateNumF = GateNumF + 1) begin
            point3_reg[GateNumF] <= {(`F_NBITS){1'b0}};
            point4_reg[GateNumF] <= {(`F_NBITS){1'b0}};
        end
    end else begin
        en_dly <= en;
        ready_dly <= ready;
        rnd_reg <= rnd_next;
        state_reg <= state_next;
        tau_reg <= tau_next;
        m_tau_p1_reg <= m_tau_p1_next;
        mul_en_reg <= mul_en_next;
        add_en_reg <= add_en_next;
        pcomp_reg <= pcomp_next;
        for (GateNumF = 0; GateNumF < noutputs; GateNumF = GateNumF + 1) begin
            chi_out_reg[GateNumF] <= chi_out_next[GateNumF];
        end
        for (GateNumF = 0; GateNumF < ngates; GateNumF = GateNumF + 1) begin
            point3_reg[GateNumF] <= point3_next[GateNumF];
            point4_reg[GateNumF] <= point4_next[GateNumF];
        end
    end
end

endmodule
`define __module_prover_compute_chi
`endif // __module_prover_compute_chi
