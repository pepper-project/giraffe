// syntax VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// gate prover for late gates
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_pergate_compute_late
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
`include "field_multiplier.sv"
`include "pergate_compute_gatefn.sv"
module pergate_compute_late
    #( parameter [`GATEFN_BITS-1:0] gate_fn = `GATEFN_ADD
     , parameter                    nidbits = 4
     , parameter [nidbits-1:0]      id_vec = 0
    )( input                    clk
     , input                    rstb

     , input                    en
     , input                    restart

     , input  [`F_NBITS-1:0]    tau
     , input  [`F_NBITS-1:0]    m_tau_p1

     , input  [`F_NBITS-1:0]    z1_chi

     , input                    mux_sel
     , input  [`F_NBITS-1:0]    in0 [1:0]
     , input  [`F_NBITS-1:0]    in1

     , output                   ready
     , output [`F_NBITS-1:0]    gate_out [2:0]
     );

// sanity
generate
    if (nidbits < 4) begin: IErr1
        Error_nidbits_must_be_at_least_four_in_pergate_compute_late __error__();
    end
    if ((nidbits % 2) != 0) begin: IErr2
        Error_nidbits_must_be_even_in_pergate_compute_late __error__();
    end
endgenerate

localparam ncountbits = $clog2(nidbits + 1);

reg [ncountbits-1:0] count_reg, count_next;
reg [`F_NBITS-1:0] gate_out_reg [2:0], gate_out_next [2:0];
assign gate_out = gate_out_reg;
reg [nidbits-1:0] id_reg, id_next;
reg [`F_NBITS-1:0] wpred_reg, wpred_next;

reg en_dly;
wire start = en & ~en_dly;
enum { ST_IDLE, ST_FN_PRED, ST_THIRD_PT, ST_THIRD_OUT } state_reg, state_next;
assign ready = (state_reg == ST_IDLE) & ~start;

reg [`F_NBITS-1:0] fn_in0 [1:0], fn_in1 [1:0];
reg en_fn_reg, en_fn_next;
wire fn_ready;
wire [`F_NBITS-1:0] fn_out [1:0];

reg [`F_NBITS-1:0] mul_in0, mul_in1;
reg en_mul_reg, en_mul_next;
wire [`F_NBITS-1:0] mul_out;
wire mul_ready;

reg [`F_NBITS-1:0] add_in0, add_in1;
reg en_add_reg, en_add_next;
wire [`F_NBITS-1:0] add_out;
wire add_ready;

integer GateNumC;
`ALWAYS_COMB begin
    state_next = state_reg;
    id_next = id_reg;
    wpred_next = wpred_reg;
    en_fn_next = 1'b0;
    en_mul_next = 1'b0;
    en_add_next = 1'b0;
    count_next = count_reg;
    for (GateNumC = 0; GateNumC < 3; GateNumC = GateNumC + 1) begin
        gate_out_next[GateNumC] = gate_out_reg[GateNumC];
    end
    mul_in0 = {(`F_NBITS){1'bX}};
    mul_in1 = {(`F_NBITS){1'bX}};
    add_in0 = {(`F_NBITS){1'bX}};
    add_in1 = {(`F_NBITS){1'bX}};
    if (count_reg < (nidbits >> 1)) begin
        fn_in0[0] = in0[0];
        fn_in0[1] = in0[1];
        fn_in1[0] = in1;
        fn_in1[1] = in1;
    end else begin
        fn_in0[0] = in1;
        fn_in0[1] = in1;
        fn_in1[0] = in0[0];
        fn_in1[1] = in0[1];
    end

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                en_fn_next = 1'b1;
                if (restart) begin
                    count_next = {(ncountbits){1'b0}};
                end else begin
                    en_mul_next = 1'b1;
                end
                state_next = ST_FN_PRED;
            end
        end

        ST_FN_PRED: begin
            mul_in0 = wpred_reg;
            mul_in1 = id_reg[0] ? tau : m_tau_p1;
            if (mul_ready & fn_ready) begin
                if (restart) begin
                    wpred_next = z1_chi;
                    id_next = id_vec;
                end else begin
                    wpred_next = mul_out;
                    id_next = {1'b0,id_reg[nidbits-1:1]};
                end
                en_mul_next = 1'b1;
                en_add_next = 1'b1;
                state_next = ST_THIRD_PT;
            end
        end

        ST_THIRD_PT: begin
            mul_in0 = wpred_reg;
            mul_in1 = fn_out[0];
            add_in0 = id_reg[0] ? ~wpred_reg : {wpred_reg[`F_NBITS-2:0],1'b0};
            add_in1 = id_reg[0] ? `F_Q_P1_MI : (wpred_reg[`F_NBITS-1] ? `F_I : {(`F_NBITS){1'b0}});
            if (add_ready & mul_ready) begin
                gate_out_next[0] = id_reg[0] ? {(`F_NBITS){1'b0}} : mul_out;
                gate_out_next[1] = id_reg[0] ? mul_out : {(`F_NBITS){1'b0}};
                en_mul_next = 1'b1;
                state_next = ST_THIRD_OUT;
            end
        end

        ST_THIRD_OUT: begin
            mul_in0 = add_out;
            mul_in1 = fn_out[1];
            if (mul_ready) begin
                gate_out_next[2] = mul_out;
                count_next = count_reg + 1'b1;
                state_next = ST_IDLE;
            end
        end
    endcase
end

integer GateNumF;
`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        state_reg <= ST_IDLE;
        id_reg <= {(nidbits){1'b0}};
        wpred_reg <= {(`F_NBITS){1'b0}};
        en_fn_reg <= 1'b0;
        en_mul_reg <= 1'b0;
        en_add_reg <= 1'b0;
        count_reg <= 1'b0;
        for (GateNumF = 0; GateNumF < 3; GateNumF = GateNumF + 1) begin
            gate_out_reg[GateNumF] <= {(`F_NBITS){1'b0}};
        end
    end else begin
        en_dly <= en;
        state_reg <= state_next;
        id_reg <= id_next;
        wpred_reg <= wpred_next;
        en_fn_reg <= en_fn_next;
        en_mul_reg <= en_mul_next;
        en_add_reg <= en_add_next;
        count_reg <= count_next;
        for (GateNumF = 0; GateNumF < 3; GateNumF = GateNumF + 1) begin
            gate_out_reg[GateNumF] <= gate_out_next[GateNumF];
        end
    end
end

field_adder iAdd
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en_add_reg)
    , .a            (add_in0)
    , .b            (add_in1)
    , .ready_pulse  ()
    , .ready        (add_ready)
    , .c            (add_out)
    );

field_multiplier iMul
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en_mul_reg)
    , .a            (mul_in0)
    , .b            (mul_in1)
    , .ready_pulse  ()
    , .ready        (mul_ready)
    , .c            (mul_out)
    );

pergate_compute_gatefn
    #( .gate_fn     (gate_fn)
     , .nVals       (2)
     ) iFn
     ( .clk         (clk)
     , .rstb        (rstb)
     , .en          (en_fn_reg)
     , .mux_sel     (mux_sel)
     , .in0         (fn_in0)
     , .in1         (fn_in1)
     , .ready_pulse ()
     , .ready       (fn_ready)
     , .gatefn      (fn_out)
     );

endmodule
`define __module_pergate_compute_late.sv
`endif // __module_pergate_compute_late.sv
