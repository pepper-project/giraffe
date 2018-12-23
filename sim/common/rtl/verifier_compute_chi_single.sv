// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// compute chi with selectable parallelism
// (C) 2016 Riad S. Wahby

`ifndef __module_verifier_compute_chi_single
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
`include "verifier_compute_chi_elem.sv"
module verifier_compute_chi_single
    #( parameter                nValBits = 8
     , parameter                nEarlyBits = nValBits
// NOTE do not override any parameters below this line //
     , parameter                nValues = 1 << nValBits
    )( input                    clk
     , input                    rstb

     , input                    en
     , input                    early

     , input  [`F_NBITS-1:0]    tau [nValBits-1:0]

     , output [`F_NBITS-1:0]    chi_out [nValues-1:0]

     , output                   ready
     );

// sanity check
generate
    if (nValues != (1 << nValBits)) begin: IErr1
        Error_do_not_override_nValues_in_verifier_compute_chi_single __error__();
    end
    if (nEarlyBits > nValBits) begin: IErr4
        Error_nEarlyBits_must_be_no_greater_than_nValBits_in_verifier_compute_chi_single __error__();
    end
endgenerate

reg [nValBits-1:0] count_reg, count_next;
wire [nValBits-1:0] next_count_val = {1'b0,count_reg[nValBits-1:1]};
wire [nValBits-1:0] normal_start = {1'b1,{(nValBits-1){1'b0}}};
wire [nValBits-1:0] early_start;
generate
    if (nEarlyBits == nValBits) begin: EarlyIsNorm
        assign early_start = normal_start;
    end else begin: EarlyIsEarly
        assign early_start = {{(nValBits-nEarlyBits){1'b0}},1'b1,{(nEarlyBits-1){1'b0}}};
    end
endgenerate

wire elem_ready;

reg [`F_NBITS-1:0] tau_reg;
wire [`F_NBITS-1:0] m_tau_p1;

enum { ST_IDLE, ST_INVPRE_ST, ST_INVPRE, ST_LOAD_ST, ST_LOAD, ST_INV_ST, ST_INV, ST_GRUN_ST, ST_GRUN } state_reg, state_next;
reg en_dly;
wire start = en & ~en_dly;
assign ready = (state_reg == ST_IDLE) & ~start;

wire add_ready;
wire elem_en = (state_reg == ST_GRUN_ST) | (state_reg == ST_LOAD_ST);
wire add_en = (state_reg == ST_INVPRE_ST) | (state_reg == ST_INV_ST);
wire direct_en = (state_reg == ST_LOAD_ST) | (state_reg == ST_LOAD);

integer GNumC;
`ALWAYS_COMB begin
    state_next = state_reg;
    count_next = count_reg;
    tau_reg = {(`F_NBITS){1'bX}};
    for (GNumC = 0; GNumC < nValBits; GNumC = GNumC + 1) begin
        if (count_reg[GNumC] == 1'b1) begin
            tau_reg = tau[GNumC];
        end
    end

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                if (early) begin
                    count_next = early_start;
                end else begin
                    count_next = normal_start;
                end
                state_next = ST_INVPRE_ST;
            end
        end

        ST_INVPRE_ST, ST_INVPRE: begin
            if (add_ready) begin
                state_next = ST_LOAD_ST;
            end else begin
                state_next = ST_INVPRE;
            end
        end

        ST_LOAD_ST, ST_LOAD: begin
            if (elem_ready) begin
                count_next = next_count_val;
                state_next = ST_INV_ST;
            end else begin
                state_next = ST_LOAD;
            end
        end

        ST_INV_ST, ST_INV: begin
            if (add_ready) begin
                state_next = ST_GRUN_ST;
            end else begin
                state_next = ST_INV;
            end
        end

        ST_GRUN_ST, ST_GRUN: begin
            if (elem_ready) begin
                count_next = next_count_val;
                if (count_reg[0]) begin
                    state_next = ST_IDLE;
                end else begin
                    state_next = ST_INV_ST;
                end
            end else begin
                state_next = ST_GRUN;
            end
        end
    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        state_reg <= ST_IDLE;
        count_reg <= {(nValBits){1'b0}};
    end else begin
        en_dly <= en;
        state_reg <= state_next;
        count_reg <= count_next;
    end
end

wire [`F_NBITS-1:0] add_in0 = ~tau_reg;
wire [`F_NBITS-1:0] add_in1 = `F_Q_P2_MI;
field_adder iAdd
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (add_en)
    , .a            (add_in0)
    , .b            (add_in1)
    , .ready_pulse  ()
    , .ready        (add_ready)
    , .c            (m_tau_p1)
    );

wire [`F_NBITS-1:0] invals_zero [1:0];
assign invals_zero[0] = {(`F_NBITS){1'b0}};
assign invals_zero[1] = {(`F_NBITS){1'b0}};
verifier_compute_chi_elem
    #( .nValBits        (nValBits)
     ) iChiElm
     ( .clk             (clk)
     , .rstb            (rstb)
     , .en              (elem_en)
     , .preload         (1'b0)
     , .direct_load     (direct_en)
     , .mul_invals      (1'b0)
     , .invals          (invals_zero)
     , .shen_out        ()
     , .shen_in         (1'b0)
     , .preload_in      ({(`F_NBITS){1'b0}})
     , .preload_out     ()
     , .tau             (tau_reg)
     , .m_tau_p1        (m_tau_p1)
     , .ready           (elem_ready)
     , .values_out      (chi_out)
     );

endmodule
`define __module_verifier_compute_chi_single
`endif // __module_verifier_compute_chi_single
