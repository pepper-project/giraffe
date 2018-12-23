// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// "late" part of prover's computation
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_prover_compute_v_late
`include "simulator.v"
`include "field_arith_defs.v"
`include "gatefn_defs.v"
`include "prover_compute_chi.sv"
`include "prover_compute_v_late_gates.sv"
`include "prover_shuffle_v.sv"
module prover_compute_v_late
    #( parameter                ngates = 8
     , parameter                ninputs = 8
     , parameter                nmuxsels = 1
     , parameter                plstages = 0

     , parameter [`GATEFN_BITS*ngates-1:0] gates_fn = 0

     , parameter                ninbits = $clog2(ninputs)   // do not override
     , parameter                nmuxbits = $clog2(nmuxsels < 2 ? 2 : nmuxsels) // do not override

     , parameter [(ninbits*ngates)-1:0] gates_in0 = 0
     , parameter [(ninbits*ngates)-1:0] gates_in1 = 0
     , parameter [(ngates*nmuxbits)-1:0] gates_mux = 0
// NOTE do not override below this line //
    )( input                    clk
     , input                    rstb

     , input                    en
     , input                    restart

     , input  [`F_NBITS-1:0]    tau
     , input  [`F_NBITS-1:0]    m_tau_p1

     , input  [`F_NBITS-1:0]    chi_in [ninputs-1:0]
     , input  [`F_NBITS-1:0]    z1_chi_in [ngates-1:0]
     , input  [`F_NBITS-1:0]    beta_in

     , input                    precomp
     , input                    z1_ready
     , output                   z1_continue
     , input  [`F_NBITS-1:0]    z1
     , input  [`F_NBITS-1:0]    m_z1_p1
     , output [`F_NBITS-1:0]    z1_chi_out [ninputs-1:0]

     , input  [nmuxsels-1:0]    mux_sel

     , output                   ready
     , output                   ready_pulse

     , output [`F_NBITS-1:0]    h0_out
     , output [`F_NBITS-1:0]    h1_out
     , output [`F_NBITS-1:0]    c_out [2:0]
     );

// sanity check
generate
    if (ninbits != $clog2(ninputs)) begin: IErr1
        Error_do_not_override_ninbits_in_prover_compute_v_late __error__();
    end
    if (nmuxbits != $clog2(nmuxsels < 2 ? 2 : nmuxsels)) begin: IErr2
        Error_do_not_override_nmuxbits_in_prover_compute_v_late __error__();
    end
endgenerate

localparam ninputsHalf = 1 << (ninbits - 1);
localparam ncountbits = $clog2(2 * ninbits + 1);
localparam ninputsRnd = 1 << ninbits;

reg [ncountbits-1:0] count_reg, count_next;
wire in_first_half = count_reg < ninbits;

reg [`F_NBITS-1:0] chi_in_reg [ninputs-1:0];
reg [`F_NBITS-1:0] beta_in_reg, h0_reg, h0_next;

wire chi_ready;
wire [`F_NBITS-1:0] chi_out [ninputsRnd-1:0];
wire [`F_NBITS-1:0] point3_out [ninputsHalf-1:0];
wire [`F_NBITS-1:0] point4_out [ninputsHalf-1:0];

wire [`F_NBITS-1:0] chi_shuffle_out [ninputsRnd-1:0];
wire [`F_NBITS-1:0] point3_shuffle_out [ninputsHalf-1:0];
wire [1:0] shuffle_ready;
wire all_shuffle_ready = &(shuffle_ready);

wire [`F_NBITS-1:0] v_late_in0 [ninputs-1:0] [1:0];
wire [`F_NBITS-1:0] v_late_in1 [ninputs-1:0];
wire gates_ready;

assign h0_out = h0_reg;
assign h1_out = chi_out[0];

enum { ST_IDLE, ST_PRE_WAIT, ST_PRE_ST, ST_PRE, ST_PRE_CONT, ST_CHI_ST, ST_CHI, ST_CHI2_ST, ST_CHI2, ST_SHUF_ST, ST_SHUF, ST_GATES_ST, ST_GATES } state_reg, state_next;
reg en_dly, ready_dly, preload_reg, preload_next;
reg restart_gates_reg, restart_gates_next, restart_chi_reg, restart_chi_next;
wire start = en & ~en_dly;
wire load_chi_beta = start & restart;
assign ready = (state_reg == ST_IDLE) & ~start;
assign ready_pulse = ready & ~ready_dly;
assign z1_continue = state_reg == ST_PRE_CONT;

wire en_chi = (state_reg == ST_CHI_ST) | (state_reg == ST_CHI2_ST) | (state_reg == ST_PRE_ST);
wire en_shuf = state_reg == ST_SHUF_ST;
wire en_gates = state_reg == ST_GATES_ST;

wire z1_sel = (state_reg == ST_PRE_ST) | (state_reg == ST_PRE) | (state_reg == ST_PRE_WAIT) | (state_reg == ST_PRE_CONT);
wire [`F_NBITS-1:0] tau_sel = z1_sel ? z1 : tau;
wire [`F_NBITS-1:0] m_tau_p1_sel = z1_sel ? m_z1_p1 : m_tau_p1;

integer GNumC;
`ALWAYS_COMB begin
    state_next = state_reg;
    count_next = count_reg;
    h0_next = h0_reg;
    preload_next = preload_reg;
    restart_gates_next = restart_gates_reg;
    restart_chi_next = restart_chi_reg;

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                if (precomp) begin
                    preload_next = 1'b0;
                    restart_gates_next = 1'b0;
                    restart_chi_next = 1'b1;
                    count_next = ninbits - 1;
                    state_next = ST_PRE_WAIT;
                end else begin
                    if (restart) begin
                        preload_next = 1'b1;
                        restart_gates_next = 1'b1;
                        restart_chi_next = 1'b0;
                        count_next = {(ncountbits){1'b0}};
                    end else begin
                        preload_next = 1'b0;
                        restart_gates_next = 1'b0;
                        restart_chi_next = 1'b0;
                        count_next = count_reg + 1'b1;
                    end
                    state_next = ST_CHI_ST;
                end
            end
        end

        ST_PRE_WAIT: begin
            if (z1_ready) begin
                state_next = ST_PRE_ST;
            end
        end

        ST_PRE_ST: begin
            state_next = ST_PRE_CONT;
        end

        ST_PRE_CONT: begin
            state_next = ST_PRE;
        end

        ST_PRE: begin
            if (chi_ready) begin
                if (count_reg == 0) begin
                    state_next = ST_IDLE;
                end else begin
                    count_next = count_reg - 1;
                    state_next = ST_PRE_WAIT;
                    restart_chi_next = 1'b0;
                end
            end
        end

        ST_CHI_ST, ST_CHI: begin
            if (chi_ready) begin
                if (count_reg == ninbits) begin
                    h0_next = chi_out[0];
                    preload_next = 1'b1;
                    state_next = ST_CHI2_ST;
                end else if (count_reg == (2 * ninbits)) begin
                    state_next = ST_IDLE;
                end else begin
                    state_next = ST_SHUF_ST;
                end
            end else begin
                state_next = ST_CHI;
            end
        end

        ST_CHI2_ST, ST_CHI2: begin
            if (chi_ready) begin
                state_next = ST_SHUF_ST;
            end else begin
                state_next = ST_CHI2;
            end
        end

        ST_SHUF_ST, ST_SHUF: begin
            if (all_shuffle_ready) begin
                state_next = ST_GATES_ST;
                preload_next = 1'b0;
            end else begin
                state_next = ST_SHUF;
            end
        end

        ST_GATES_ST, ST_GATES: begin
            if (gates_ready) begin
                state_next = ST_IDLE;
                restart_gates_next = 1'b0;
            end else begin
                state_next = ST_GATES;
            end
        end
    endcase
end

integer GNumF;
`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        ready_dly <= 1'b1;
        state_reg <= ST_IDLE;
        for (GNumF = 0; GNumF < ninputs; GNumF = GNumF + 1) begin
            chi_in_reg[GNumF] <= {(`F_NBITS){1'b0}};
        end
        beta_in_reg <= {(`F_NBITS){1'b0}};
        h0_reg <= {(`F_NBITS){1'b0}};
        count_reg <= {(ncountbits){1'b0}};
        preload_reg <= 1'b0;
        restart_gates_reg <= 1'b0;
        restart_chi_reg <= 1'b0;
    end else begin
        en_dly <= en;
        ready_dly <= ready;
        state_reg <= state_next;
        for (GNumF = 0; GNumF < ninputs; GNumF = GNumF + 1) begin
            chi_in_reg[GNumF] <= load_chi_beta ? chi_in[GNumF] : chi_in_reg[GNumF];
        end
        beta_in_reg <= load_chi_beta ? beta_in : beta_in_reg;
        h0_reg <= h0_next;
        count_reg <= count_next;
        preload_reg <= preload_next;
        restart_gates_reg <= restart_gates_next;
        restart_chi_reg <= restart_chi_next;
    end;

end

wire [`F_NBITS-1:0] chi_in_wire [ninputsRnd-1:0];
genvar ChiNum;
generate
    for (ChiNum = 0; ChiNum < ninputs; ChiNum = ChiNum + 1) begin: ChiHookup
        assign chi_in_wire[ChiNum] = chi_in_reg[ChiNum];
    end
    for (ChiNum = ninputs; ChiNum < ninputsRnd; ChiNum = ChiNum + 1) begin: ChiDummyHookup
        assign chi_in_wire[ChiNum] = {(`F_NBITS){1'b0}};
    end
endgenerate
prover_compute_chi
    #( .npoints         (ninbits)
     ) iChi
     ( .clk             (clk)
     , .rstb            (rstb)
     , .en              (en_chi)
     , .restart         (restart_chi_reg)
     , .preload         (preload_reg)
     , .skip_pt4        (1'b1)
     , .skip_pt3        (z1_sel)
     , .tau             (tau_sel)
     , .m_tau_p1        (m_tau_p1_sel)
     , .chi_in          (chi_in_wire)
     , .ready_pulse     ()
     , .ready           (chi_ready)
     , .chi_out         (chi_out)
     , .point3_out      (point3_out)
     , .point4_out      (point4_out)
     );

genvar PointNum;
generate
    for (PointNum = 0; PointNum < ninputs; PointNum = PointNum + 1) begin: VLateInHookup
        assign z1_chi_out[PointNum] = chi_out[PointNum];

        assign v_late_in0[PointNum][0] = chi_shuffle_out[PointNum];
        assign v_late_in0[PointNum][1] = point3_shuffle_out[PointNum >> 1];

        if (PointNum == 0) begin: VLate1HookupZero
            assign v_late_in1[0] = in_first_half ? chi_in_reg[0] : h0_reg;
        end else begin: VLate1HookupNonZero
            assign v_late_in1[PointNum] = chi_in_reg[PointNum];
        end
    end
endgenerate
prover_shuffle_v
    #( .nInBits         (ninbits)
     , .plstages        (plstages)
     ) iShuffleChi
     ( .clk             (clk)
     , .rstb            (rstb)
     , .en              (en_shuf)
     , .restart         (preload_reg)
     , .v_in            (chi_out)
     , .ready_pulse     ()
     , .ready           (shuffle_ready[0])
     , .v_out           (chi_shuffle_out)
     );
prover_shuffle_v
    #( .nInBits         (ninbits - 1)
     , .plstages        (plstages)
     ) iShufflePoint3
     ( .clk             (clk)
     , .rstb            (rstb)
     , .en              (en_shuf)
     , .restart         (preload_reg)
     , .v_in            (point3_out)
     , .ready_pulse     ()
     , .ready           (shuffle_ready[1])
     , .v_out           (point3_shuffle_out)
     );

prover_compute_v_late_gates
    #( .ngates          (ngates)
     , .ninputs         (ninputs)
     , .nmuxsels        (nmuxsels)
     , .gates_fn        (gates_fn)
     , .gates_in0       (gates_in0)
     , .gates_in1       (gates_in1)
     , .gates_mux       (gates_mux)
     ) iGates
     ( .clk             (clk)
     , .rstb            (rstb)
     , .en              (en_gates)
     , .restart         (restart_gates_reg)
     , .tau             (tau)
     , .m_tau_p1        (m_tau_p1)
     , .v_in0           (v_late_in0)
     , .v_in1           (v_late_in1)
     , .z1_chi          (z1_chi_in)
     , .beta_in         (beta_in_reg)
     , .mux_sel         (mux_sel)
     , .ready           (gates_ready)
     , .ready_pulse     ()
     , .c_out           (c_out)
     );

endmodule
`define __module_prover_compute_v_late
`endif // __module_prover_compute_v_late
