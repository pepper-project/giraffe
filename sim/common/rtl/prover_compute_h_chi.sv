// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// compute all chi evals with "dynamic programming" method for h
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

// This block does "dynamic programming" computation of chi values,
// streaming in omega values in LSB-to-MSB order.
//
// In reality the computation is exactly the same as in prover_compute_chi,
// but we renumber the chi_out so that inputs are considered LSB-to-MSB.
// The other difference from prover_compute_chi is that we simplify: there's
// no hardware implementing the "collapse back to a single point" logic.

`ifndef __module_prover_compute_h_chi
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_multiplier.sv"
module prover_compute_h_chi
   #( parameter npoints = 3
// NOTE do not override parameters below this line //
    , parameter noutputs = 1 << npoints
    , parameter ngates = 1 << (npoints - 1)
   )( input                 clk
    , input                 rstb

    , input                 en
    , input                 restart

    , input  [`F_NBITS-1:0] tau
    , input  [`F_NBITS-1:0] m_tau_p1

    // hookups for external adder tree s.t. we can share one tree
    , input                 addt_ready
    , input  [`F_NBITS-1:0] mvals_in [noutputs-1:0]
    , output                addt_en
    , output                addt_tag
    , output [`F_NBITS-1:0] mvals_out [ngates-1:0]

    , output                chi_ready

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] chi_out [noutputs-1:0]
    );
`include "func_leastSetBitPosn.sv"
`include "func_convertIntMtoL.sv"

// sanity checking
generate
    if (npoints < 2) begin: IErr1
        Error_npoints_must_be_at_least_two_in_prover_compute_h_chi __error__();
    end
    if (npoints != $clog2(noutputs)) begin: IErr2
        Error_do_not_override_noutputs_in_prover_compute_h_chi __error__();
    end
    if (npoints != $clog2(ngates) + 1) begin: IErr3
        Error_do_not_override_ngates_in_prover_compute_h_chi __error__();
    end
endgenerate

// ints for static hookups
integer GateNumF, GateNumC;

// retime tau and m_tau_p1
reg [`F_NBITS-1:0] tau_reg, tau_next;
reg [`F_NBITS-1:0] m_tau_p1_reg, m_tau_p1_next;

// chi output registers
reg [`F_NBITS-1:0] chi_out_reg [noutputs-1:0], chi_out_next [noutputs-1:0];
genvar GateNum;
generate
    // real outputs: wire up chi_out
    // note that we reverse the bit index of the outputs
    // to accommodate LSB-to-MSB tau ordering
    for (GateNum = 0; GateNum < noutputs; GateNum = GateNum + 1) begin: ChiOutHookup
        localparam integer int_gate_num_MtoL = convertIntMtoL(GateNum, npoints);
        assign chi_out[int_gate_num_MtoL] = chi_out_reg[GateNum];
    end
endgenerate

// rounds and states
reg [npoints-1:0] rnd_reg, rnd_next;
wire [npoints-1:0] rnd_nxstep = {rnd_reg[npoints-2:0], 1'b1};
assign chi_ready = rnd_reg[npoints-1];
wire first_round = rnd_reg == {(npoints){1'b0}};
wire premid_round = rnd_reg == {1'b0,{(npoints-1){1'b1}}};
wire restart_int = restart | first_round;
enum { ST_IDLE, ST_LOAD, ST_MUL1, ST_MUL2, ST_TMUL1, ST_TMUL2 } state_reg, state_next;
wire inST_MUL2 = state_reg == ST_MUL2;
wire inST_IDLE = state_reg == ST_IDLE;
wire inST_TMUL2 = state_reg == ST_TMUL2;
assign addt_tag = state_reg != ST_TMUL1;

// edge detect for enable
reg en_dly;
wire start = en & ~en_dly;
assign ready = inST_IDLE & ~start;
reg ready_dly;
assign ready_pulse = ready & ~ready_dly;

// multiplier and adder hookup
reg mul_en_reg, mul_en_next;
reg addt_en_reg, addt_en_next;
assign addt_en = addt_en_reg;
wire [`F_NBITS-1:0] mul_out [ngates-1:0];
wire [ngates-1:0] mul_ready;
wire mul_idle = &(mul_ready);
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
        wire [`F_NBITS-1:0] p1_in1 = p1_tau_sel ? tau_reg : m_tau_p1_reg;

        // phase 2
        localparam integer p2_in1_0 = 2 * GateNum;
        localparam integer p2_in1_1 = 2 * GateNum + 1;
        localparam integer p2_in0_0 = convertIntMtoL(p2_in1_0, npoints);
        localparam integer p2_in0_1 = convertIntMtoL(p2_in1_1, npoints);
        wire [`F_NBITS-1:0] p2_in0 = inST_TMUL2 ? chi_out_reg[p2_in0_0] : chi_out_reg[p2_in0_1];
        wire [`F_NBITS-1:0] p2_in1 = inST_TMUL2 ? mvals_in[p2_in1_0] : mvals_in[p2_in1_1];
        wire p2_mul_en = mul_en_reg;

        // mul hookups: select input and enable wires
        wire [`F_NBITS-1:0] mul_in0 = chi_ready ? p2_in0 : p1_in0;
        wire [`F_NBITS-1:0] mul_in1 = chi_ready ? p2_in1 : p1_in1;
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

        // hook up multiplier output
        assign mvals_out[GateNum] = mul_out[GateNum];
    end
endgenerate

`ALWAYS_COMB begin
    rnd_next = rnd_reg;
    state_next = state_reg;
    tau_next = tau_reg;
    m_tau_p1_next = m_tau_p1_reg;
    mul_en_next = 1'b0;
    addt_en_next = 1'b0;
    for (GateNumC = 0; GateNumC < noutputs; GateNumC = GateNumC + 1) begin
        chi_out_next[GateNumC] = chi_out_reg[GateNumC];
    end

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                tau_next = tau;
                m_tau_p1_next = m_tau_p1;
                if (restart_int) begin
                    state_next = ST_LOAD;
                end else if (~chi_ready) begin
                    mul_en_next = 1'b1;
                    if (premid_round) begin
                        state_next = ST_MUL2;
                    end else begin
                        state_next = ST_MUL1;
                    end
                end else begin
                    mul_en_next = 1'b1;
                    state_next = ST_TMUL2;
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
                state_next = ST_IDLE;
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
            if (~mul_en_reg & mul_idle & addt_ready) begin
                addt_en_next = 1'b1;
                state_next = ST_IDLE;
            end
        end

        ST_TMUL2: begin
            if (~mul_en_reg & mul_idle & addt_ready) begin
                addt_en_next = 1'b1;
                mul_en_next = 1'b1;
                state_next = ST_TMUL1;
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
        addt_en_reg <= 1'b0;
        for (GateNumF = 0; GateNumF < noutputs; GateNumF = GateNumF + 1) begin
            chi_out_reg[GateNumF] <= {(`F_NBITS){1'b0}};
        end
    end else begin
        en_dly <= en;
        ready_dly <= ready;
        rnd_reg <= rnd_next;
        state_reg <= state_next;
        tau_reg <= tau_next;
        m_tau_p1_reg <= m_tau_p1_next;
        mul_en_reg <= mul_en_next;
        addt_en_reg <= addt_en_next;
        for (GateNumF = 0; GateNumF < noutputs; GateNumF = GateNumF + 1) begin
            chi_out_reg[GateNumF] <= chi_out_next[GateNumF];
        end
    end
end

endmodule
`define __module_prover_compute_h_chi
`endif // __module_prover_compute_h_chi
