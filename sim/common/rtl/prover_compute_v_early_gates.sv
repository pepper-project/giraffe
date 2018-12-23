// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// One instance of an arithmetic circuit
// (C) Riad S. Wahby 2016 <rsw@cs.nyu.edu>

`ifndef __module_prover_compute_v_early_gates
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_multiplier.sv"
`include "gatefn_defs.v"
`include "pergate_compute_gatefn_early.sv"
`include "prover_adder_tree_pl.sv"
module prover_compute_v_early_gates
   #( parameter ngates = 8
    , parameter ninputs = 8
    , parameter nmuxsels = 1                // number of entries in mux_sel

    , parameter [`GATEFN_BITS*ngates-1:0] gates_fn = 0

    , parameter ninbits = $clog2(ninputs)   // do not override
    , parameter nmuxbits = $clog2(nmuxsels < 2 ? 2 : nmuxsels) // do not override

    , parameter [(ninbits*ngates)-1:0] gates_in0 = 0
    , parameter [(ninbits*ngates)-1:0] gates_in1 = 0
    , parameter [(ngates*nmuxbits)-1:0] gates_mux = 0   // which gate goes to which mux_sel input?
   )( input                 clk
    , input                 rstb

    , input                 en
    , input                 mask_en
    , input  [`F_NBITS-1:0] v_in [ninputs-1:0] [3:0]
    , input  [`F_NBITS-1:0] z1_chi [ngates-1:0]
    , input  [`F_NBITS-1:0] beta_in [3:0]

    , input  [nmuxsels-1:0] mux_sel

    , output                in_ready
    , output                out_ready
    , output                out_ready_pulse

    , output [`F_NBITS-1:0] v_out [3:0]
    );

// make sure params are ok
generate
    if (ninbits != $clog2(ninputs)) begin: IErr1
        Error_do_not_override_ninbits_in_computation_layer __error__();
    end
    if (nmuxbits != $clog2(nmuxsels < 2 ? 2 : nmuxsels)) begin: IErr2
        Error_do_not_override_nmuxbits_in_computation_layer __error__();
    end
endgenerate

wire [`F_NBITS-1:0] add_in [ngates-1:0] [3:0];
wire add_in_ready, add_out_ready_pulse, add_idle;
wire [`F_NBITS-1:0] add_out;
reg [`F_NBITS-1:0] add_out_reg [2:0], add_out_next [2:0];
wire [1:0] add_out_tag;
reg [`F_NBITS-1:0] add_in_next [ngates-1:0];

wire [ngates-1:0] gate_ready;
reg ready_dly;
wire all_gate_ready = &(gate_ready);
wire pre_start = all_gate_ready & ~ready_dly;
reg in_ready_reg;
assign in_ready = in_ready_reg & ~en;

reg [1:0] count_reg, count_next;
reg en_addt_reg, en_addt_next;

wire [3:0] mul_ready;
wire all_mul_ready = &(mul_ready);
wire mul_start = add_out_ready_pulse & (add_out_tag == 2'b11);

enum { ST2_IDLE, ST2_WAIT, ST2_START } state2_reg, state2_next;
wire start = state2_reg == ST2_START;
enum { ST_IDLE, ST_PRE_IDLE, ST_RUNTREE } state_reg, state_next;
assign out_ready = ((state_reg == ST_IDLE) & ~start) | ((state_reg == ST_PRE_IDLE) & all_mul_ready & add_idle & ~mul_start);
reg out_ready_dly;
reg mask_bit;
wire mask_dis = add_out_ready_pulse;
assign out_ready_pulse = out_ready & ~out_ready_dly;

integer GNum, VNum;
`ALWAYS_COMB begin
    en_addt_next = 1'b0;
    count_next = count_reg;
    state_next = state_reg;
    state2_next = state2_reg;
    // outputs from the adder
    for (VNum = 0; VNum < 3; VNum = VNum + 1) begin
        if (add_out_ready_pulse & (add_out_tag == VNum)) begin
            add_out_next[VNum] = add_out;
        end else begin
            add_out_next[VNum] = add_out_reg[VNum];
        end
    end

    // mux for inputs to adder
    for (GNum = 0; GNum < ngates; GNum = GNum + 1) begin
        for (VNum = 0; VNum < 4; VNum = VNum + 1) begin
            if (count_reg == VNum) begin
                add_in_next[GNum] = add_in[GNum][VNum];
            end
        end
    end

    case (state2_reg)
        ST2_IDLE: begin
            if (pre_start) begin
                if (out_ready) begin
                    state2_next = ST2_START;
                end else begin
                    state2_next = ST2_WAIT;
                end
            end
        end

        ST2_WAIT: begin
            if (out_ready) begin
                state2_next = ST2_START;
            end
        end

        ST2_START: begin
            state2_next = ST2_IDLE;
        end
    endcase

    case (state_reg)
        ST_PRE_IDLE: begin
            if (add_idle & all_mul_ready & ~mul_start) begin
                state_next = ST_IDLE;
            end
        end

        ST_IDLE: begin
            if (start) begin
                count_next = 2'b00;
                en_addt_next = 1'b1;
                state_next = ST_RUNTREE;
            end
        end

        ST_RUNTREE: begin
            if (add_in_ready) begin
                count_next = count_reg + 1'b1;
                if (count_reg == 2'b11) begin
                    state_next = ST_PRE_IDLE;
                end else begin
                    en_addt_next = 1'b1;
                end
            end
        end
    endcase
end

integer VNumF;
`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        in_ready_reg <= 1'b1;
        ready_dly <= 1'b1;
        out_ready_dly <= 1'b1;
        en_addt_reg <= 1'b0;
        state_reg <= ST_IDLE;
        state2_reg <= ST2_IDLE;
        count_reg <= 2'b00;
        mask_bit <= 1'b0;
        for (VNumF = 0; VNumF < 3; VNumF = VNumF + 1) begin
            add_out_reg[VNumF] = {(`F_NBITS){1'b0}};
        end
    end else begin
        in_ready_reg <= en ? 1'b0 : (((count_reg == 2'b11) & en_addt_reg) ? 1'b1 : in_ready_reg);
        ready_dly <= all_gate_ready;
        out_ready_dly <= out_ready;
        en_addt_reg <= en_addt_next;
        state_reg <= state_next;
        state2_reg <= state2_next;
        count_reg <= count_next;
        mask_bit <= mask_dis ? 1'b1 : (mask_en ? 1'b0 : mask_bit);
        for (VNumF = 0; VNumF < 3; VNumF = VNumF + 1) begin
            add_out_reg[VNumF] = add_out_next[VNumF];
        end
    end
end

prover_adder_tree_pl
    #( .ngates          (ngates)
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

genvar GateNum;
genvar InNum;
generate
    for (GateNum = 0; GateNum < 4; GateNum = GateNum + 1) begin: MulInst
        wire [`F_NBITS-1:0] mul_out;
        wire [`F_NBITS-1:0] mul_in;
        if (GateNum < 3) begin: MulEarly
            assign mul_in = add_out_reg[GateNum];
        end else begin: MulFinal
            assign mul_in = add_out;
        end

        field_multiplier iMul
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (mul_start)
            , .a            (mul_in)
            , .b            (beta_in[GateNum])
            , .ready_pulse  ()
            , .ready        (mul_ready[GateNum])
            , .c            (mul_out)
            );
        assign v_out[GateNum] = mul_out & {(`F_NBITS){mask_bit}};
    end
    for (GateNum = 0; GateNum < ngates; GateNum = GateNum + 1) begin: CompInst
        localparam [`GATEFN_BITS-1:0] gfn = gates_fn[(GateNum*`GATEFN_BITS) +: `GATEFN_BITS];
        localparam [ninbits-1:0] gi0 = gates_in0[(GateNum*ninbits) +: ninbits];
        localparam [ninbits-1:0] gi1 = gates_in1[(GateNum*ninbits) +: ninbits];

        // make sure that gmux is at least 1 bit wide
        localparam nb = nmuxbits == 0 ? 1 : nmuxbits;
        localparam [nb-1:0] gmux = gates_mux[(GateNum*nmuxbits) +: nb];

        if (gi0 >= ninputs || gi1 >= ninputs) begin: IErr3
            Illegal_input_number_declared_for_gate __error__();
        end

        wire [`F_NBITS-1:0] in0 [3:0];
        wire [`F_NBITS-1:0] in1 [3:0];
        wire [`F_NBITS-1:0] out [3:0];
        for (InNum = 0; InNum < 4; InNum = InNum + 1) begin: InHookup
            assign in0[InNum] = v_in[gi0][InNum];
            assign in1[InNum] = v_in[gi1][InNum];
            assign add_in[GateNum][InNum] = out[InNum];
        end

        // abstract gate function
        pergate_compute_gatefn_early
           #( .gate_fn      (gfn)
            ) igatefn
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (en)
            , .mux_sel      (mux_sel[gmux])
            , .z1_chi       (z1_chi[GateNum])
            , .in0          (in0)
            , .in1          (in1)
            , .ready        (gate_ready[GateNum])
            , .gatefn       (out)
            );
    end
endgenerate

endmodule
`define __module_prover_compute_v_early_gates
`endif // __module_prover_compute_v_early_gates
