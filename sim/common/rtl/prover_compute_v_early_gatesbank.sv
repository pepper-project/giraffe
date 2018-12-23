// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// A bank of instances of arithmetic circuits to go with _v_srbank
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_prover_compute_v_early_gatesbank
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
`include "gatefn_defs.v"
`include "prover_adder_tree_pl.sv"
`include "prover_compute_v_early_gates.sv"
`include "prover_interpolate_cubic.sv"
`include "shiftreg_simple.sv"
module prover_compute_v_early_gatesbank
    #( parameter                nCopyBits = 3
     , parameter                nParBits = 1

     , parameter                ngates = 8
     , parameter                ninputs = 8
     , parameter                nmuxsels = 1

     , parameter [`GATEFN_BITS*ngates-1:0] gates_fn = 0

     , parameter                ninbits = $clog2(ninputs)       // do not override
     , parameter                nmuxbits = $clog2(nmuxsels < 2 ? 2 : nmuxsels)     // do not override

     , parameter [(ninbits*ngates)-1:0] gates_in0 = 0
     , parameter [(ninbits*ngates)-1:0] gates_in1 = 0
     , parameter [(ngates*nmuxbits)-1:0] gates_mux = 0
// NOTE do not override below this line //
     , parameter                nParallel = 1 << nParBits
     , parameter                nCopies = 1 << nCopyBits
     , parameter                nCopiesH = 1 << (nCopyBits - 1)
    )( input                    clk
     , input                    rstb

     , input  [3:0]             beta_en
     , input  [nParallel-1:0]   en
     , input                    interp_en

     , input  [`F_NBITS-1:0]    v_in [nParallel-1:0] [ninputs-1:0] [3:0]

     , input  [`F_NBITS-1:0]    z1_chi [ngates-1:0]

     , input  [`F_NBITS-1:0]    beta_in_even [nCopiesH-1:0]
     , input  [`F_NBITS-1:0]    beta_in_odd  [nCopiesH-1:0]
     , input  [`F_NBITS-1:0]    point3_in [nCopiesH-1:0]
     , input  [`F_NBITS-1:0]    point4_in [nCopiesH-1:0]

     , input  [nmuxsels-1:0]    mux_sel

     , output [nParallel-1:0]   in_ready
     , output                   out_ready
     , output                   out_ready_pulse
     , output [`F_NBITS-1:0]    c_out [3:0]
     );

// sanity check
generate
    if (nParallel != (1 << nParBits)) begin: IErr1
        Error_do_not_override_nParallel_in_prover_compute_v_early_gatesbank __error__();
    end
    if (nCopies != (1 << nCopyBits)) begin: IErr2
        Error_do_not_override_nCopies_in_prover_compute_v_early_gatesbank __error__();
    end
    if (nCopiesH != (1 << (nCopyBits - 1))) begin: IErr3
        Error_do_not_override_nCopiesH_in_prover_compute_v_early_gatesbank __error__();
    end
    if (nCopyBits - nParBits < 1) begin: IErr4
        Error_max_parallelism_exceeded_in_prover_compute_v_early_gatesbank __error__();
    end
endgenerate

localparam nBetaPer = 1 << (nCopyBits - nParBits - 1);

wire [nParallel-1:0] ready_inst;
wire all_ready_inst = &(ready_inst);
reg all_ready_inst_dly;
wire start = all_ready_inst & ~all_ready_inst_dly;
enum { ST_IDLE, ST_RUNTREE, ST_INTERPWT, ST_INTERPST } state_reg, state_next;
reg [1:0] count_reg, count_next;
reg mask_reg, mask_next;

wire [`F_NBITS-1:0] add_in [nParallel-1:0] [3:0];
wire add_in_ready, add_out_ready_pulse, add_idle;
wire [1:0] add_out_tag;
wire [`F_NBITS-1:0] add_out;
reg [`F_NBITS-1:0] add_out_reg [2:0], add_out_next [2:0];
reg [`F_NBITS-1:0] add_in_next [nParallel-1:0];
reg en_addt_reg, en_addt_next;

wire interpolate_ready;
reg clear_adder_reg;
wire [3:0] accum_ready;
wire all_accum_ready = &(accum_ready);
assign out_ready = all_accum_ready & interpolate_ready & all_ready_inst & (state_reg == ST_IDLE) & ~start & add_idle & ~interp_en;
reg out_ready_dly;
assign out_ready_pulse = out_ready & ~out_ready_dly;

wire [`F_NBITS-1:0] accum_out [3:0];
wire accum_en = add_out_ready_pulse & (add_out_tag == 2'b11);
wire interpolate_en = state_reg == ST_INTERPST;

integer GNum, VNum;
`ALWAYS_COMB begin
    mask_next = 1'b0;
    en_addt_next = 1'b0;
    count_next = count_reg;
    state_next = state_reg;
    // outputs from the adder
    for (VNum = 0; VNum < 3; VNum = VNum + 1) begin
        if (add_out_ready_pulse & (add_out_tag == VNum)) begin
            add_out_next[VNum] = add_out;
        end else begin
            add_out_next[VNum] = add_out_reg[VNum];
        end
    end

    // mux for inputs to adder
    for (GNum = 0; GNum < nParallel; GNum = GNum + 1) begin
        for (VNum = 0; VNum < 4; VNum = VNum + 1) begin
            if (count_reg == VNum) begin
                add_in_next[GNum] = add_in[GNum][VNum];
            end
        end
    end

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                count_next = 2'b00;
                en_addt_next = 1'b1;
                state_next = ST_RUNTREE;
            end else if (interp_en) begin
                state_next = ST_INTERPWT;
            end
        end

        ST_RUNTREE: begin
            if (add_in_ready) begin
                count_next = count_reg + 1'b1;
                if (count_reg == 2'b11) begin
                    mask_next = 1'b1;
                    state_next = ST_IDLE;
                end else begin
                    en_addt_next = 1'b1;
                end
            end
        end

        ST_INTERPWT: begin
            if (accum_ready & add_idle & all_ready_inst & interpolate_ready) begin
                state_next = ST_INTERPST;
            end
        end

        ST_INTERPST: begin
            state_next = ST_IDLE;
        end
    endcase
end

integer VNumF;
`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        state_reg <= ST_IDLE;
        out_ready_dly <= 1'b1;
        mask_reg <= 1'b0;
        all_ready_inst_dly <= 1'b1;
        clear_adder_reg <= 1'b1;
        count_reg <= 2'b00;
        en_addt_reg <= 1'b0;
        for (VNumF = 0; VNumF < 3; VNumF = VNumF + 1) begin
            add_out_reg[VNumF] <= {(`F_NBITS){1'b0}};
        end
    end else begin
        state_reg <= state_next;
        out_ready_dly <= out_ready;
        mask_reg <= mask_next;
        all_ready_inst_dly <= all_ready_inst;
        clear_adder_reg <= |(beta_en) ? 1'b1 : (accum_en ? 1'b0 : clear_adder_reg);
        count_reg <= count_next;
        en_addt_reg <= en_addt_next;
        for (VNumF = 0; VNumF < 3; VNumF = VNumF + 1) begin
            add_out_reg[VNumF] <= add_out_next[VNumF];
        end
    end
end

// TODO handle case where we only have 1 _gates instance
prover_adder_tree_pl
    #( .ngates          (nParallel)
     , .ntagb           (2)
     ) iAddT
     ( .clk             (clk)
     , .rstb            (rstb)
     , .en              (en_addt_reg)
     , .in              (add_in_next)
     , .in_tag          (count_reg)
     , .idle            (add_idle)
     , .in_ready_pulse  ()
     , .in_ready        (add_in_ready)
     , .out_ready_pulse (add_out_ready_pulse)
     , .out_ready       ()
     , .out             (add_out)
     , .out_tag         (add_out_tag)
     );

prover_interpolate_cubic iInterp
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (interpolate_en)
    , .y_in         (accum_out)
    , .c_out        (c_out)
    , .ready_pulse  ()
    , .ready        (interpolate_ready)
    );

genvar GateNum;
genvar InNum;
genvar ValNum;
generate
    for (GateNum = 0; GateNum < 4; GateNum = GateNum + 1) begin: InterpHookup
        wire [`F_NBITS-1:0] accum_in;
        wire [`F_NBITS-1:0] accum_fb;
        if (GateNum < 3) begin: IntEarly
            assign accum_in = add_out_reg[GateNum];
        end else begin: IntFinal
            assign accum_in = add_out;
        end
        assign accum_fb = clear_adder_reg ? {(`F_NBITS){1'b0}} : accum_out[GateNum];

        field_adder iAdd
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (accum_en)
            , .a            (accum_in)
            , .b            (accum_fb)
            , .ready_pulse  ()
            , .ready        (accum_ready[GateNum])
            , .c            (accum_out[GateNum])
            );
    end
    for (GateNum = 0; GateNum < nParallel; GateNum = GateNum + 1) begin: GatesInst
        wire [`F_NBITS-1:0] beta_inst [3:0];
        wire shift_en;

        // hook up beta to the gates
        if (nBetaPer == 1) begin: SingleHookup
            reg [`F_NBITS-1:0] beta_in_reg [3:0];
            for (ValNum = 0; ValNum < 4; ValNum = ValNum + 1) begin: InstRegHookup
                assign beta_inst[ValNum] = beta_in_reg[ValNum];
            end
            integer BetaNumF;
            `ALWAYS_FF @(posedge clk or negedge rstb) begin
                if (~rstb) begin
                    for (BetaNumF = 0; BetaNumF < 4; BetaNumF = BetaNumF + 1) begin
                        beta_in_reg[BetaNumF] <= {(`F_NBITS){1'b0}};
                    end
                end else begin
                    beta_in_reg[0] <= beta_en[0] ? beta_in_even[GateNum] : beta_in_reg[0];
                    beta_in_reg[1] <= beta_en[1] ? beta_in_odd[GateNum] : beta_in_reg[1];
                    beta_in_reg[2] <= beta_en[2] ? point3_in[GateNum] : beta_in_reg[2];
                    beta_in_reg[3] <= beta_en[3] ? point4_in[GateNum] : beta_in_reg[3];
                end
            end
        end else begin
            localparam betaOffset = GateNum * nBetaPer;
            for (ValNum = 0; ValNum < 4; ValNum = ValNum + 1) begin: InstSRegHookup
                wire [`F_NBITS-1:0] sr_in [nBetaPer-1:0];
                for (InNum = 0; InNum < nBetaPer; InNum = InNum + 1) begin
                    if (ValNum == 0) begin
                        assign sr_in[InNum] = beta_in_even[betaOffset+InNum];
                    end else if (ValNum == 1) begin
                        assign sr_in[InNum] = beta_in_odd[betaOffset+InNum];
                    end else if (ValNum == 2) begin
                        assign sr_in[InNum] = point3_in[betaOffset+InNum];
                    end else begin
                        assign sr_in[InNum] = point4_in[betaOffset+InNum];
                    end
                end
                shiftreg_simple
                    #( .nbits       (`F_NBITS)
                     , .nwords      (nBetaPer)
                     ) iSReg
                     ( .clk         (clk)
                     , .rstb        (rstb)
                     , .wren        (beta_en[ValNum])
                     , .shen        (shift_en)
                     , .d           (sr_in)
                     , .q           (beta_inst[ValNum])
                     , .q_all       ()
                     );
            end
        end

        wire [`F_NBITS-1:0] v_in_inst [ninputs-1:0] [3:0];
        wire [`F_NBITS-1:0] v_out_inst [3:0];

        for (InNum = 0; InNum < ninputs; InNum = InNum + 1) begin: InHookup
            for (ValNum = 0; ValNum < 4; ValNum = ValNum + 1) begin: InValHookup
                assign v_in_inst[InNum][ValNum] = v_in[GateNum][InNum][ValNum];
            end
        end
        for (ValNum = 0; ValNum < 4; ValNum = ValNum + 1) begin: OutValHookup
            assign add_in[GateNum][ValNum] = v_out_inst[ValNum];
        end

        prover_compute_v_early_gates
            #( .ngates      (ngates)
             , .ninputs     (ninputs)
             , .nmuxsels    (nmuxsels)
             , .gates_fn    (gates_fn)
             , .gates_in0   (gates_in0)
             , .gates_in1   (gates_in1)
             , .gates_mux   (gates_mux)
             ) iGates
             ( .clk         (clk)
             , .rstb        (rstb)
             , .en          (en[GateNum])
             , .mask_en     (mask_reg)
             , .v_in        (v_in_inst)
             , .z1_chi      (z1_chi)
             , .beta_in     (beta_inst)
             , .mux_sel     (mux_sel)
             , .in_ready    (in_ready[GateNum])
             , .out_ready   (ready_inst[GateNum])
             , .out_ready_pulse (shift_en)
             , .v_out       (v_out_inst)
             );
    end
endgenerate

endmodule
`define __module_prover_compute_v_early_gatesbank
`endif // __module_prover_compute_v_early_gatesbank
