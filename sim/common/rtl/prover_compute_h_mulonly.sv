// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// array of multipliers plus state machine to drive them
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_prover_compute_h_mulonly
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_multiplier.sv"
module prover_compute_h_mulonly
   #( parameter npoints = 3
// NOTE do not override parameters below this line //
    , parameter ninputs = 1 << npoints
    , parameter ngates = 1 << (npoints - 1)
   )( input                 clk
    , input                 rstb

    , input                 en

    // hookups for external adder tree s.t. we can share one tree
    , input                 addt_ready
    , input  [`F_NBITS-1:0] chi_in [ninputs-1:0]
    , input  [`F_NBITS-1:0] mvals_in [ninputs-1:0]

    , output                addt_en
    , output                addt_tag
    , output [`F_NBITS-1:0] mvals_out [ngates-1:0]

    , output                ready_pulse
    , output                ready
    );

// sanity checking
generate
    if (npoints < 2) begin: IErr1
        Error_npoints_must_be_at_least_two_in_prover_compute_h_mulonly __error__();
    end
    if (npoints != $clog2(ninputs)) begin: IErr2
        Error_do_not_override_ninputs_in_prover_compute_h_mulonly __error__();
    end
    if (npoints != $clog2(ngates) + 1) begin: IErr3
        Error_do_not_override_ngates_in_prover_compute_h_mulonly __error__();
    end
endgenerate

// rounds and states
enum { ST_IDLE, ST_TMUL1, ST_TMUL2 } state_reg, state_next;
wire inST_IDLE = state_reg == ST_IDLE;
wire inST_TMUL2 = state_reg == ST_TMUL2;
assign addt_tag = state_reg != ST_TMUL1;

// edge detect for enable
reg en_dly, ready_dly;
wire start = en & ~en_dly;
assign ready = inST_IDLE & ~start;
assign ready_pulse = ready & ~ready_dly;

// multiplier and adder hookup
reg mul_en_reg, mul_en_next;
reg addt_en_reg, addt_en_next;
assign addt_en = addt_en_reg;
wire [`F_NBITS-1:0] mul_out [ngates-1:0];
wire [ngates-1:0] mul_ready;
wire mul_idle = &(mul_ready);
// instantiate multipliers and adders
genvar GateNum;
generate
    for (GateNum = 0; GateNum < ngates; GateNum = GateNum + 1) begin: MulAddGen
        // mul hookups: select input and enable wires
        localparam integer in_0 = 2 * GateNum;
        localparam integer in_1 = 2 * GateNum + 1;
        wire [`F_NBITS-1:0] mul_in0 = inST_TMUL2 ? chi_in[in_0] : chi_in[in_1];
        wire [`F_NBITS-1:0] mul_in1 = inST_TMUL2 ? mvals_in[in_0] : mvals_in[in_1];
        wire mul_en = mul_en_reg;

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
    state_next = state_reg;
    mul_en_next = 1'b0;
    addt_en_next = 1'b0;

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                mul_en_next = 1'b1;
                state_next = ST_TMUL2;
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
        state_reg <= ST_IDLE;
        mul_en_reg <= 1'b0;
        addt_en_reg <= 1'b0;
    end else begin
        en_dly <= en;
        ready_dly <= ready;
        state_reg <= state_next;
        mul_en_reg <= mul_en_next;
        addt_en_reg <= addt_en_next;
    end
end

endmodule
`define __module_prover_compute_h_mulonly
`endif // __module_prover_compute_h_mulonly
