// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// Instance of arith. ckt for final rounds (stateful gates)
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_prover_compute_v_late_gates
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_multiplier.sv"
`include "pergate_compute_late.sv"
`include "prover_adder_tree_pl.sv"
`include "prover_interpolate_quadratic.sv"
module prover_compute_v_late_gates
    #( parameter                ngates = 8
     , parameter                ninputs = 8
     , parameter                nmuxsels = 1

     , parameter [`GATEFN_BITS*ngates-1:0] gates_fn = 0

     , parameter                ninbits = $clog2(ninputs) // do not override
     , parameter                nmuxbits = $clog2(nmuxsels < 2 ? 2 : nmuxsels) // do not override

     , parameter [(ninbits*ngates)-1:0] gates_in0 = 0
     , parameter [(ninbits*ngates)-1:0] gates_in1 = 0
     , parameter [(ngates*nmuxbits)-1:0] gates_mux = 0
    )( input                    clk
     , input                    rstb

     , input                    en
     , input                    restart

     , input  [`F_NBITS-1:0]    tau
     , input  [`F_NBITS-1:0]    m_tau_p1

     , input  [`F_NBITS-1:0]    v_in0 [ninputs-1:0] [1:0]   // from the shuffle tree
     , input  [`F_NBITS-1:0]    v_in1 [ninputs-1:0]         // raw inputs (first g rds) or V(w1,p2) (second g rds)
     , input  [`F_NBITS-1:0]    z1_chi [ngates-1:0]
     , input  [`F_NBITS-1:0]    beta_in

     , input  [nmuxsels-1:0]    mux_sel

     , output                   ready
     , output                   ready_pulse

     , output [`F_NBITS-1:0]    c_out [2:0]
     );

// make sure params are ok
generate
    if (ninbits != $clog2(ninputs)) begin: IErr1
        Error_do_not_override_ninbits_in_prover_compute_v_late_gates __error__();
    end
    if (nmuxbits != $clog2(nmuxsels < 2 ? 2 : nmuxsels)) begin: IErr2
        Error_do_not_override_nmuxbits_in_prover_compute_v_late_gates __error__();
    end
endgenerate

localparam ncountbits = $clog2(2*ninbits + 1);

reg [ncountbits-1:0] count_reg, count_next;
wire in_first_half = (count_reg < ninbits);

reg restart_reg, restart_next;
wire [ngates-1:0] fn_ready;
wire all_fn_ready = &(fn_ready);

wire add_idle, add_in_ready, add_out_ready_pulse;
wire [1:0] add_out_tag;
wire [`F_NBITS-1:0] add_in [ngates-1:0] [2:0];
reg [`F_NBITS-1:0] add_in_sel [ngates-1:0];
reg [1:0] add_in_tag;
wire [`F_NBITS-1:0] add_out;
reg [`F_NBITS-1:0] add_out_reg [1:0], add_out_next [1:0];

wire interp_ready;
wire [2:0] mul_ready;
wire all_mul_ready = &(mul_ready);
wire [`F_NBITS-1:0] mul_out [2:0];

enum { ST_IDLE, ST_FN_ST, ST_FN, ST_ADD0_ST, ST_ADD0, ST_ADD1_ST, ST_ADD1, ST_ADD2_ST, ST_ADD2, ST_MUL_ST, ST_MUL, ST_INTERP_ST, ST_INTERP } state_reg, state_next;

wire en_fn = state_reg == ST_FN_ST;
wire en_add = (state_reg == ST_ADD0_ST) | (state_reg == ST_ADD1_ST) | (state_reg == ST_ADD2_ST);
wire en_interp = state_reg == ST_INTERP_ST;
wire en_mul = state_reg == ST_MUL_ST;

reg en_dly, ready_dly;
wire start = en & ~en_dly;
assign ready = (state_reg == ST_IDLE) & ~start;
assign ready_pulse = ready & ~ready_dly;

integer InNumC;
`ALWAYS_COMB begin
    count_next = count_reg;
    restart_next = restart_reg;
    for (InNumC = 0; InNumC < ngates; InNumC = InNumC + 1) begin
        add_in_sel[InNumC] = {(`F_NBITS){1'bX}};
    end
    add_in_tag = 2'bXX;
    state_next = state_reg;
    if (add_out_ready_pulse & (add_out_tag == 2'b00)) begin
        add_out_next[0] = add_out;
    end else begin
        add_out_next[0] = add_out_reg[0];
    end
    if (add_out_ready_pulse & (add_out_tag == 2'b01)) begin
        add_out_next[1] = add_out;
    end else begin
        add_out_next[1] = add_out_reg[1];
    end

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                if (restart) begin
                    count_next = 1'b0;
                    restart_next = 1'b1;
                end else begin
                    count_next = count_reg + 1'b1;
                    restart_next = 1'b0;
                end
                state_next = ST_FN_ST;
            end
        end

        ST_FN_ST, ST_FN: begin
            if (all_fn_ready) begin
                state_next = ST_ADD0_ST;
            end else begin
                state_next = ST_FN;
            end
        end

        ST_ADD0_ST, ST_ADD0: begin
            for (InNumC = 0; InNumC < ngates; InNumC = InNumC + 1) begin
                add_in_sel[InNumC] = add_in[InNumC][0];
            end
            add_in_tag = 2'b00;
            if (add_in_ready) begin
                state_next = ST_ADD1_ST;
            end else begin
                state_next = ST_ADD0;
            end
        end

        ST_ADD1_ST, ST_ADD1: begin
            for (InNumC = 0; InNumC < ngates; InNumC = InNumC + 1) begin
                add_in_sel[InNumC] = add_in[InNumC][1];
            end
            add_in_tag = 2'b01;
            if (add_in_ready) begin
                state_next = ST_ADD2_ST;
            end else begin
                state_next = ST_ADD1;
            end
        end

        ST_ADD2_ST, ST_ADD2: begin
            for (InNumC = 0; InNumC < ngates; InNumC = InNumC + 1) begin
                add_in_sel[InNumC] = add_in[InNumC][2];
            end
            add_in_tag = 2'b10;
            if (add_idle) begin
                state_next = ST_MUL_ST;
            end else begin
                state_next = ST_ADD2;
            end
        end

        ST_MUL_ST, ST_MUL: begin
            if (all_mul_ready) begin
                state_next = ST_INTERP_ST;
            end else begin
                state_next = ST_MUL;
            end
        end

        ST_INTERP_ST, ST_INTERP: begin
            if (interp_ready) begin
                state_next = ST_IDLE;
            end else begin
                state_next = ST_INTERP;
            end
        end
    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        ready_dly <= 1'b1;
        state_reg <= ST_IDLE;
        count_reg <= {(ncountbits){1'b0}};
        restart_reg <= 1'b0;
        add_out_reg[0] <= {(`F_NBITS){1'b0}};
        add_out_reg[1] <= {(`F_NBITS){1'b0}};
    end else begin
        en_dly <= en;
        ready_dly <= ready;
        state_reg <= state_next;
        count_reg <= count_next;
        restart_reg <= restart_next;
        add_out_reg[0] <= add_out_next[0];
        add_out_reg[1] <= add_out_next[1];
    end
end

prover_adder_tree_pl
    #( .ngates          (ngates)
     , .ntagb           (2)
     ) iAddT
     ( .clk             (clk)
     , .rstb            (rstb)
     , .en              (en_add)
     , .in              (add_in_sel)
     , .in_tag          (add_in_tag)
     , .idle            (add_idle)
     , .in_ready_pulse  ()
     , .in_ready        (add_in_ready)
     , .out_ready_pulse (add_out_ready_pulse)
     , .out_ready       ()
     , .out             (add_out)
     , .out_tag         (add_out_tag)
     );

prover_interpolate_quadratic iInterp
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en_interp)
    , .y_in         (mul_out)
    , .c_out        (c_out)
    , .ready_pulse  ()
    , .ready        (interp_ready)
    );

genvar GateNum;
genvar InNum;
generate
    for (GateNum = 0; GateNum < 3; GateNum = GateNum + 1) begin: MulInst
        wire [`F_NBITS-1:0] mul_in;
        if (GateNum < 2) begin
            assign mul_in = add_out_reg[GateNum];
        end else begin
            assign mul_in = add_out;
        end
        field_multiplier iMul
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (en_mul)
            , .a            (beta_in)
            , .b            (mul_in)
            , .ready_pulse  ()
            , .ready        (mul_ready[GateNum])
            , .c            (mul_out[GateNum])
            );
    end
    for (GateNum = 0; GateNum < ngates; GateNum = GateNum + 1) begin: GateInst
        localparam [`GATEFN_BITS-1:0] gfn = gates_fn[(GateNum*`GATEFN_BITS) +: `GATEFN_BITS];
        localparam [ninbits-1:0] gi0 = gates_in0[(GateNum*ninbits) +: ninbits];
        localparam [ninbits-1:0] gi1 = gates_in1[(GateNum*ninbits) +: ninbits];

        // make sure that gmux is at least 1 bit wide
        localparam nb = nmuxbits == 0 ? 1 : nmuxbits;
        localparam [nb-1:0] gmux = gates_mux[(GateNum*nmuxbits) +: nb];

        if (gi0 >= ninputs || gi1 >= ninputs) begin: IErr3
            Illegal_input_number_declared_for_gate __error__();
        end

        wire [`F_NBITS-1:0] in0 [1:0];
        wire [`F_NBITS-1:0] in1;
        wire [`F_NBITS-1:0] out [2:0];
        assign in0[0] = in_first_half ? v_in0[gi0][0] : v_in0[gi1][0];
        assign in0[1] = in_first_half ? v_in0[gi0][1] : v_in0[gi1][1];
        assign in1 = in_first_half ? v_in1[gi1] : v_in1[0];
        for (InNum = 0; InNum < 3; InNum = InNum + 1) begin
            assign add_in[GateNum][InNum] = out[InNum];
        end

        // instantiate gate function
        pergate_compute_late
            #( .gate_fn     (gfn)
             , .nidbits     (2*ninbits)
             , .id_vec      ({gi1, gi0})
             ) igatefn
             ( .clk         (clk)
             , .rstb        (rstb)
             , .en          (en_fn)
             , .restart     (restart_reg)
             , .tau         (tau)
             , .m_tau_p1    (m_tau_p1)
             , .z1_chi      (z1_chi[GateNum])
             , .mux_sel     (mux_sel[gmux])
             , .in0         (in0)
             , .in1         (in1)
             , .ready       (fn_ready[GateNum])
             , .gate_out    (out)
             );
    end
endgenerate

endmodule
`define __module_prover_compute_v_late_gates
`endif // __module_prover_compute_v_late_gates

