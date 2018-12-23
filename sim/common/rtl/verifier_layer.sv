// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// one layer of verifier
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_verifier_layer
`include "simulator.v"
`include "field_arith_defs.v"
`include "verifier_compute_horner.sv"
`include "verifier_compute_wpreds.sv"
module verifier_layer
   #( parameter             nGates = 8
    , parameter             nInputs = 8
    , parameter             nMuxSels = 1

    , parameter             nCopyBits = 3
    , parameter             nParBits = 1

    , parameter [`GATEFN_BITS*nGates-1:0] gates_fn = 0

    , parameter             nOutBits = $clog2(nGates)   // do not override
    , parameter             nInBits = $clog2(nInputs)   // do not override
    , parameter             nMuxBits = $clog2(nMuxSels) // do not override

    , parameter [(nInBits*nGates)-1:0] gates_in0 = 0
    , parameter [(nInBits*nGates)-1:0] gates_in1 = 0
    , parameter [(nGates*nMuxBits)-1:0] gates_mux = 0
// NOTE do not override below this line //
    , parameter             lastCoeff = nInBits < 3 ? 3 : nInBits
   )( input                 clk
    , input                 rstb

    , input                 en
    , input                 restart
    , input  [nMuxSels-1:0] mux_sel

    , input  [`F_NBITS-1:0] c_in [lastCoeff:0]
    , input  [`F_NBITS-1:0] val_in
    , output [`F_NBITS-1:0] lay_out

    , input  [`F_NBITS-1:0] z1_vals [nOutBits-1:0]
    , input  [`F_NBITS-1:0] z2_vals [nCopyBits-1:0]

    , input  [`F_NBITS-1:0] w1_vals [nInBits-1:0]
    , input  [`F_NBITS-1:0] w2_vals [nInBits-1:0]
    , input  [`F_NBITS-1:0] w3_vals [nCopyBits-1:0]

    , input  [`F_NBITS-1:0] tau_final

    , output [`F_NBITS-1:0] tau_out     // this is the one to send to P this round after running V
    , output [`F_NBITS-1:0] z1_out [nInBits-1:0]
    , output                ok
    , output                ready
    , output                fin_layer
    );

// sanity check
generate
    if (nOutBits != $clog2(nGates)) begin: IErr1
        Error_do_not_override_nOutBits_in_verifier_layer __error__();
    end
    if (nInBits != $clog2(nInputs)) begin: IErr2
        Error_do_not_override_nInBits_in_verifier_layer __error__();
    end
    if (nMuxBits != $clog2(nMuxSels)) begin: IErr3
        Error_do_not_override_nMuxBits_in_verifier_layer __error__();
    end
endgenerate

localparam nCountBits = $clog2(nCopyBits + 2 * nInBits + 1);
reg [nCountBits-1:0] count_reg, count_next;
wire [nCountBits-1:0] next_count_val = count_reg + 1'b1;

enum { ST_IDLE, ST_KICK_ST, ST_KICK, ST_WPREDS } state_reg, state_next;
reg en_dly;
wire start = en & ~en_dly;
assign ready = (state_reg == ST_IDLE) & ~start;
assign fin_layer = ready & (count_reg == (nCopyBits + 2 * nInBits));

wire in_early = count_reg < nCopyBits;
wire in_late = count_reg < (nCopyBits + 2 * nInBits);
wire v1_v2_ready = state_reg == ST_WPREDS;

wire horner_en = state_reg == ST_KICK_ST;
wire pred_en = state_reg == ST_KICK_ST;
wire cubic = in_early;
wire round = in_early | in_late;
wire horner_ok, horner_ready, pred_ready;
wire horner_restart = count_reg == {(nCountBits){1'b0}};
reg layok_reg, layok_next;
assign ok = layok_reg & horner_ok;
wire [`F_NBITS-1:0] horner_final_out, pred_final_out, v2_val;
reg [`F_NBITS-1:0] tau_reg;
assign tau_out = tau_reg;

integer GNumC;
`ALWAYS_COMB begin
    state_next = state_reg;
    count_next = count_reg;
    layok_next = layok_reg;
    for (GNumC = 0; GNumC < (nCopyBits + 2 * nInBits + 1); GNumC = GNumC + 1) begin
        if (GNumC == count_reg) begin
            if (GNumC < nCopyBits) begin
                tau_reg = w3_vals[GNumC];
            end else if (GNumC < (nCopyBits + nInBits)) begin
                tau_reg = w1_vals[GNumC - nCopyBits];
            end else if (GNumC < (nCopyBits + 2 * nInBits)) begin
                tau_reg = w2_vals[GNumC - nCopyBits - nInBits];
            end else begin
                tau_reg = tau_final;
            end
        end
    end

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                if (restart) begin
                    count_next = {(nCountBits){1'b0}};
                    layok_next = 1'b1;
                end else begin
                    count_next = count_reg + 1;
                end
                state_next = ST_KICK_ST;
            end
        end

        ST_KICK_ST, ST_KICK: begin
            if (horner_ready) begin
                if (round) begin
                    state_next = ST_IDLE;
                end else begin
                    state_next = ST_WPREDS;
                end
            end else begin
                state_next = ST_KICK;
            end
        end

        ST_WPREDS: begin
            if (pred_ready) begin
                if (pred_final_out != horner_final_out) begin
                    layok_next = 1'b0;
                end
                state_next = ST_IDLE;
            end
        end
    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        state_reg <= ST_IDLE;
        count_reg <= {(nCountBits){1'b0}};
        layok_reg <= 1'b0;
    end else begin
        en_dly <= en;
        state_reg <= state_next;
        count_reg <= count_next;
        layok_reg <= layok_next;
    end
end

verifier_compute_wpreds
   #( .nGates           (nGates)
    , .nInputs          (nInputs)
    , .nMuxSels         (nMuxSels)
    , .nCopyBits        (nCopyBits)
    , .nParBits         (nParBits)
    , .gates_fn         (gates_fn)
    , .gates_in0        (gates_in0)
    , .gates_in1        (gates_in1)
    , .gates_mux        (gates_mux)
    ) iPreds
    ( .clk              (clk)
    , .rstb             (rstb)
    , .en               (pred_en)
    , .mux_sel          (mux_sel)
    , .z1_vals          (z1_vals)
    , .w1_vals          (w1_vals)
    , .w2_vals          (w2_vals)
    , .z2_vals          (z2_vals)
    , .w3_vals          (w3_vals)
    , .tau_final        (tau_final)
    , .z1_out           (z1_out)
    , .v1_v2_ready      (v1_v2_ready)
    , .v1_val           (c_in[0])
    , .v2_val           (v2_val)
    , .v_out            (pred_final_out)
    , .ready            (pred_ready)
    );

verifier_compute_horner
   #( .maxDegree        (nInBits)
    ) iHorner
    ( .clk              (clk)
    , .rstb             (rstb)
    , .en               (horner_en)
    , .restart          (horner_restart)
    , .cubic            (cubic)
    , .round            (round)
    , .next_lay         (1'b0)
    , .ncoeff           (nInBits)
    , .tau              (tau_reg)
    , .c_in             (c_in)
    , .val_in           (val_in)
    , .val_out          (horner_final_out)
    , .ok               (horner_ok)
    , .lay_out          (lay_out)
    , .v2_out           (v2_val)
    , .ready            (horner_ready)
    );

endmodule
`define __module_verifier_layer
`endif // __module_verifier_layer
