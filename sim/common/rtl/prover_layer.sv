// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// one layer of prover
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_prover_layer
`include "simulator.v"
`include "field_arith_defs.v"
`include "gatefn_defs.v"
`include "field_one_minus.sv"
`include "prover_compute_h.sv"
`include "prover_compute_v_early.sv"
`include "prover_compute_v_late.sv"
`include "prover_compute_w0.sv"
module prover_layer
   #( parameter             nInputs = 8
    , parameter             nGates = 8
    , parameter             nMuxSels = 1
    , parameter             nCopyBits = 3
    , parameter             plStages = 0
    , parameter             nParBits = 1
    , parameter             nParBitsH = 1

    , parameter             nInBits = $clog2(nInputs)       // do not override
    , parameter             nMuxBits = $clog2(nMuxSels)     // do not override

    , parameter [`GATEFN_BITS*nGates-1:0] gates_fn = 0
    , parameter [(nInBits*nGates)-1:0] gates_in0 = 0
    , parameter [(nInBits*nGates)-1:0] gates_in1 = 0
    , parameter [(nGates*nMuxBits)-1:0] gates_mux = 0
// NOTE do not override below this line //
    , parameter             nCopies = 1 << nCopyBits
    , parameter             nOutBits = $clog2(nGates)
    , parameter             lastCoeff = (nInBits < 3) ? 3 : nInBits
    , parameter             nCoeffBits = $clog2(lastCoeff + 1)
   )( input                 clk
    , input                 rstb

    , input                 en
    , input                 restart

    , input  [nMuxSels-1:0] mux_sel

    , input  [`F_NBITS-1:0] v_in [nCopies-1:0] [nInputs-1:0]

    , input                 z1_chi_in_ready
    , input  [`F_NBITS-1:0] z1_chi [nGates-1:0]         // these come from compute_v_late in next layer
    , input  [`F_NBITS-1:0] z2 [nCopyBits-1:0]          // these come from compute_h in next layer
    , input  [`F_NBITS-1:0] m_z2_p1 [nCopyBits-1:0]     // "

    , output                z1_chi_out_ready            // these go to next layer
    , output [`F_NBITS-1:0] z1_chi_out [nInputs-1:0]    // "
    , output                z2_out_ready                // "
    , output [`F_NBITS-1:0] z2_out [nCopyBits-1:0]      // "
    , output [`F_NBITS-1:0] m_z2_p1_out [nCopyBits-1:0] // "

    , input  [`F_NBITS-1:0] tau

    , output [`F_NBITS-1:0] coeff_out [lastCoeff:0]
    , output                ready
    , output                cubic
    );

// sanity check
generate
    if (nInBits != $clog2(nInputs)) begin: IErr1
        Error_do_not_override_nInBits_in_prover_layer __error__();
    end
    if (nMuxBits != $clog2(nMuxSels)) begin: IErr2
        Error_do_not_override_nMuxBits_in_prover_layer __error__();
    end
    if (nCopies != (1 << nCopyBits)) begin: IErr3
        Error_do_not_override_nCopies_in_prover_layer __error__();
    end
    if (nOutBits != $clog2(nGates)) begin: IErr4
        Error_do_not_override_nOutBits_in_prover_layer __error__();
    end
    if (nCoeffBits != $clog2(nInBits + 1)) begin: IErr5
        Error_do_not_override_nCoeffBits_in_prover_layer __error__();
    end
    if ((lastCoeff < 3) | (lastCoeff < nInBits)) begin: IErr6
        Error_do_not_override_lastCoeff_in_prover_layer __error__();
    end
endgenerate

localparam nInputsRnd = 1 << nInBits;
localparam nCountBits = $clog2(nCopyBits + 2 * nInBits + 2);

reg [nCountBits-1:0] count_reg, count_next;
wire in_early = count_reg < nCopyBits;
wire early_finishing = count_reg == nCopyBits;
wire in_late = count_reg < (nCopyBits + 2 * nInBits);
wire late_finishing = count_reg == (nCopyBits + 2 * nInBits);
assign z2_out_ready = late_finishing & ready;
wire count_zero = count_reg == {(`F_NBITS){1'b0}};
wire chi_early_ready = ~(in_early | early_finishing);

assign cubic = in_early;

reg [`F_NBITS-1:0] z1_chi_reg [nGates-1:0];
reg en_dly;
wire start = en & ~en_dly;
enum { ST_IDLE, ST_ONEM_ST, ST_ONEM, ST_EARLYONLY_ST, ST_EARLY_ST, ST_EARLY, ST_LATEONLY_ST, ST_LATE_ST, ST_LATE, ST_FINAL_ST, ST_FINAL } state_reg, state_next;
assign ready = (state_reg == ST_IDLE) & ~start;

wire [`F_NBITS-1:0] m_tau_p1;
wire negate_ready, z1comp_ready, comph_ready, late_ready, early_ready;
wire negate_en = state_reg == ST_ONEM_ST;
wire z1comp_en = state_reg == ST_FINAL_ST;
wire comph_en = (state_reg == ST_EARLY_ST) | (state_reg == ST_LATE_ST);
wire comph_restart = count_reg == 1;
wire late_en = (state_reg == ST_LATE_ST) | (state_reg == ST_LATEONLY_ST) | (state_reg == ST_FINAL_ST);
wire late_restart = early_finishing;
wire late_precomp = (state_reg == ST_FINAL_ST) | (state_reg == ST_FINAL);

// run "early" either at 0 or while we're computing z1_chi in _late_
wire early_en = (state_reg == ST_EARLYONLY_ST) | (state_reg == ST_EARLY_ST) | (state_reg == ST_FINAL_ST);
wire early_restart = count_zero;

wire [`F_NBITS-1:0] h_coeff_out [nInBits:0], cubic_coeff_out [3:0], quad_coeff_out [2:0];
reg [`F_NBITS-1:0] coeff_out_reg [3:0];
genvar GNum;
generate
    for (GNum = 0; GNum < 4; GNum = GNum + 1) begin
        assign coeff_out[GNum] = coeff_out_reg[GNum];
    end
    for (GNum = 4; GNum < nInBits + 1; GNum = GNum + 1) begin
        assign coeff_out[GNum] = h_coeff_out[GNum];
    end
endgenerate

wire load_z1_chi = z1_chi_in_ready & count_zero;
reg z1_chi_out_ready_reg, z1_chi_out_ready_next;
assign z1_chi_out_ready = z1_chi_out_ready_reg;

integer GNumC;
`ALWAYS_COMB begin
    z1_chi_out_ready_next = z1_chi_out_ready_reg;
    state_next = state_reg;
    count_next = count_reg;
    if (in_early) begin
        for (GNumC = 0; GNumC < 4; GNumC = GNumC + 1) begin
            coeff_out_reg[GNumC] = cubic_coeff_out[GNumC];
        end
    end else if (in_late) begin
        for (GNumC = 0; GNumC < 3; GNumC = GNumC + 1) begin
            coeff_out_reg[GNumC] = quad_coeff_out[GNumC];
        end
        coeff_out_reg[3] = {(`F_NBITS){1'bX}};
    end else begin
        for (GNumC = 0; GNumC < 4; GNumC = GNumC + 1) begin
            coeff_out_reg[GNumC] = h_coeff_out[GNumC];
        end
    end

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                z1_chi_out_ready_next = 1'b0;
                if (restart) begin
                    count_next = {(nCountBits){1'b0}};
                    state_next = ST_EARLYONLY_ST;
                end else begin
                    if (late_finishing) begin
                        count_next = {(`F_NBITS){1'b0}};
                        state_next = ST_FINAL_ST;
                    end else begin
                        count_next = count_reg + 1;
                        state_next = ST_ONEM_ST;
                    end
                end
            end
        end
        
        ST_ONEM_ST, ST_ONEM: begin
            if (negate_ready) begin
                if (in_early | early_finishing) begin
                    state_next = ST_EARLY_ST;
                end else begin
                    state_next = ST_LATE_ST;
                end
            end else begin
                state_next = ST_ONEM;
            end
        end

        ST_EARLY_ST, ST_EARLYONLY_ST: begin
            state_next = ST_EARLY;
        end

        ST_EARLY: begin
            if (early_finishing) begin
                if (early_ready) begin
                    state_next = ST_LATEONLY_ST;
                end
            end else if (early_ready & comph_ready) begin
                state_next = ST_IDLE;
            end
        end

        ST_LATE_ST, ST_LATEONLY_ST: begin
            state_next = ST_LATE;
        end

        ST_LATE_ST, ST_LATE: begin
            if (late_ready & comph_ready) begin
                state_next = ST_IDLE;
            end
        end

        ST_FINAL_ST, ST_FINAL: begin
            if (late_ready) begin
                z1_chi_out_ready_next = 1'b1;
                state_next = ST_EARLY;
            end else begin
                state_next = ST_FINAL;
            end
        end
    endcase
end

integer GNumF;
`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        z1_chi_out_ready_reg <= 1'b0;
        state_reg <= ST_IDLE;
        count_reg <= {(nCountBits){1'b0}};
        en_dly <= 1'b1;
        for (GNumF = 0; GNumF < nGates; GNumF = GNumF + 1) begin
            z1_chi_reg[GNumF] <= {(`F_NBITS){1'b0}};
        end
    end else begin
        z1_chi_out_ready_reg <= z1_chi_out_ready_next;
        state_reg <= state_next;
        count_reg <= count_next;
        en_dly <= en;
        for (GNumF = 0; GNumF < nGates; GNumF = GNumF + 1) begin
            z1_chi_reg[GNumF] <= load_z1_chi ? z1_chi[GNumF] : z1_chi_reg[GNumF];
        end
    end
end

field_one_minus iNegate
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (negate_en)
    , .a            (tau)
    , .ready_pulse  ()
    , .ready        (negate_ready)
    , .c            (m_tau_p1)
    );

wire [`F_NBITS-1:0] w1 [nInBits-1:0], w2_m_w1 [nInBits-1:0];
wire [`F_NBITS-1:0] z1_next, m_z1_p1_next;
wire z1comp_cont, z1comp_val_ready;
prover_compute_w0
   #( .ninbits      (nInBits)
    ) iZ1
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (z1comp_en)
    , .cont         (z1comp_cont)
    , .w1           (w1)
    , .w2_m_w1      (w2_m_w1)
    , .tau          (tau)
    , .ready        (z1comp_ready)
    , .w0_ready     (z1comp_val_ready)
    , .w0           (z1_next)
    , .m_w0_p1      (m_z1_p1_next)
    );

wire [`F_NBITS-1:0] h0_val, h1_val;
wire [`F_NBITS-1:0] chi_early [nInputs-1:0];
prover_compute_h
   #( .nCopies      (nCopies)
    , .nInputs      (nInputs)
    , .nParBits     (nParBitsH)
    ) iCompH
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (comph_en)
    , .restart      (comph_restart)
    , .tau          (tau)
    , .m_tau_p1     (m_tau_p1)
    , .h0_in        (h0_val)
    , .h1_in        (h1_val)
    , .chi_early    (chi_early)
    , .chi_early_ready (chi_early_ready)
    , .h_coeff_out  (h_coeff_out)
    , .w1           (w1)
    , .w2_m_w1      (w2_m_w1)
    , .z2           (z2_out)
    , .m_z2_p1      (m_z2_p1_out)
    , .ready_pulse  ()
    , .ready        (comph_ready)
    );

wire [`F_NBITS-1:0] beta_early;
prover_compute_v_late
   #( .ngates       (nGates)
    , .ninputs      (nInputs)
    , .nmuxsels     (nMuxSels)
    , .plstages     (plStages)
    , .gates_fn     (gates_fn)
    , .gates_in0    (gates_in0)
    , .gates_in1    (gates_in1)
    , .gates_mux    (gates_mux)
    ) iLate
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (late_en)
    , .restart      (late_restart)
    , .tau          (tau)
    , .m_tau_p1     (m_tau_p1)
    , .chi_in       (chi_early)
    , .z1_chi_in    (z1_chi_reg)
    , .beta_in      (beta_early)
    , .precomp      (late_precomp)
    , .z1_ready     (z1comp_val_ready)
    , .z1_continue  (z1comp_cont)
    , .z1           (z1_next)
    , .m_z1_p1      (m_z1_p1_next)
    , .z1_chi_out   (z1_chi_out)
    , .mux_sel      (mux_sel)
    , .ready        (late_ready)
    , .ready_pulse  ()
    , .h0_out       (h0_val)
    , .h1_out       (h1_val)
    , .c_out        (quad_coeff_out)
    );

prover_compute_v_early
   #( .ngates       (nGates)
    , .ninputs      (nInputs)
    , .nmuxsels     (nMuxSels)
    , .nCopyBits    (nCopyBits)
    , .nParBits     (nParBits)
    , .gates_fn     (gates_fn)
    , .gates_in0    (gates_in0)
    , .gates_in1    (gates_in1)
    , .gates_mux    (gates_mux)
    ) iEarly
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (early_en)
    , .restart      (early_restart)
    , .tau          (tau)
    , .m_tau_p1     (m_tau_p1)
    , .z2           (z2)
    , .m_z2_p1      (m_z2_p1)
    , .v_in         (v_in)
    , .z1_chi       (z1_chi_reg)
    , .z1_chi_ready (z1_chi_in_ready)
    , .mux_sel      (mux_sel)
    , .chi_out      (chi_early)
    , .beta_out     (beta_early)
    , .ready        (early_ready)
    , .ready_pulse  ()
    , .c_out        (cubic_coeff_out)
    );

endmodule
`define __module_prover_layer
`endif // __module_prover_layer
