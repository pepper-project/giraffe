// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// compute chi with selectable parallelism
// (C) 2016 Riad S. Wahby

`ifndef __module_verifier_compute_chi
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
`include "prover_adder_tree_pl.sv"
`include "shiftreg_simple.sv"
`include "verifier_compute_chi_elem.sv"
module verifier_compute_chi
    #( parameter                nValBits = 8
     , parameter                nParBits = 1
     , parameter                doDotProduct = 0
     , parameter                nEarlyBits = nValBits
// NOTE do not override any parameters below this line //
     , parameter                nValues = 1 << nValBits
    )( input                    clk
     , input                    rstb

     , input                    en
     , input                    early

     , input  [`F_NBITS-1:0]    tau [nValBits-1:0]
     , input  [`F_NBITS-1:0]    vals_in [nValues-1:0]

     , output [`F_NBITS-1:0]    dot_product_out
     , output [`F_NBITS-1:0]    chi_out [nValues-1:0]

     , output                   ready
     );

// sanity check
generate
    if (nValues != (1 << nValBits)) begin: IErr1
        Error_do_not_override_nValues_in_verifier_compute_chi __error__();
    end
    if (nParBits < 1) begin: IErr2
        // We could probably do away with this requirement by adding a "load-only" mode
        // to _chi_element (or just preloading "1"), but this isn't super high priority.
        Error_nParBits_must_be_at_least_one_in_verifier_compute_chi __error__();
    end
    if ((nValBits - nParBits < 2) | (nEarlyBits - nParBits < 2)) begin: IErr3
        // too much parallelism introduces some weird corner cases that I don't want to handle
        Error_nValBits_and_nEarlyBits_must_be_at_least_two_more_than_nParBits_in_verifier_compute_chi __error__();
    end
    if (nEarlyBits > nValBits) begin: IErr4
        Error_nEarlyBits_must_be_no_greater_than_nValBits_in_verifier_compute_chi __error__();
    end
endgenerate

localparam nParallel = 1 << nParBits;
localparam nValBitsPer = nValBits - nParBits;
localparam nValuesPer = 1 << nValBitsPer;
localparam nActCountBits = nParBits;

reg [nActCountBits-1:0] actcnt_reg, actcnt_next;
reg [nValBits-1:0] count_reg, count_next;
wire [nValBits-1:0] next_count_val = {1'b0,count_reg[nValBits-1:1]};
wire [nActCountBits-1:0] next_actcnt_val;
wire [nValBits-1:0] normal_start = {1'b1,{(nValBits-1){1'b0}}};
wire [nValBits-1:0] early_start;
generate
    if (nParBits == 1) begin: ActCntShort
        assign next_actcnt_val[0:0] = 1'b1;
    end else begin: ActCntLong
        assign next_actcnt_val[nActCountBits-1:0] = {actcnt_reg[nActCountBits-2:0],1'b1};
    end
    if (nEarlyBits == nValBits) begin: EarlyIsNorm
        assign early_start = normal_start;
    end else begin: EarlyIsEarly
        assign early_start = {{(nValBits-nEarlyBits){1'b0}},1'b1,{(nEarlyBits-1){1'b0}}};
    end
endgenerate

wire [nParallel-1:0] elem_ready;
wire all_elems_ready = &(elem_ready);

wire addt_idle, addt_in_ready, addt_out_ready_pulse, addt_out_ready;
wire [`F_NBITS-1:0] addt_in [2*nParallel-1:0];
wire addt_in_tag = count_reg == {(nValBits){1'b0}};
wire addt_out_tag;
wire [`F_NBITS-1:0] addt_out;

reg [`F_NBITS-1:0] tau_reg;
wire [`F_NBITS-1:0] m_tau_p1;
assign dot_product_out = m_tau_p1;
reg [`F_NBITS-1:0] tmp_reg, tmp_next;

reg preload_reg, preload_next;

enum { ST_IDLE, ST_INVPRE_ST, ST_INVPRE, ST_INV_ST, ST_INV, ST_GRUN_ST, ST_GRUN, ST_DOTP_ST, ST_DOTP, ST_ADDT_ST, ST_ADDT, ST_ADDT_WAIT, ST_ADDT_SH } state_reg, state_next;
reg en_dly;
wire start = en & ~en_dly;
assign ready = (state_reg == ST_IDLE) & ~start;

wire add_ready;
wire elems_en = (state_reg == ST_GRUN_ST) | (state_reg == ST_DOTP_ST);
wire mul_en = state_reg == ST_DOTP_ST;
wire shld_en = state_reg == ST_DOTP_ST;
wire addsh_en = state_reg == ST_ADDT_SH;
wire sum_restart = addt_out_tag;
wire addt_en = state_reg == ST_ADDT_ST;
wire in_addt_state = (state_reg == ST_ADDT_ST) | (state_reg == ST_ADDT) | (state_reg == ST_ADDT_WAIT) | (state_reg == ST_ADDT_SH);
wire add_en = (state_reg == ST_INVPRE_ST) | (state_reg == ST_INV_ST) | (in_addt_state & addt_out_ready_pulse);
wire do_invert = ~in_addt_state;

integer GNumC;
`ALWAYS_COMB begin
    state_next = state_reg;
    count_next = count_reg;
    actcnt_next = actcnt_reg;
    preload_next = preload_reg;
    tmp_next = tmp_reg;
    tau_reg = {(`F_NBITS){1'bX}};
    for (GNumC = 0; GNumC < nValBits; GNumC = GNumC + 1) begin
        if (count_reg[GNumC] == 1'b1) begin
            tau_reg = tau[GNumC];
        end
    end

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                preload_next = 1'b1;
                if (early) begin
                    count_next = early_start;
                end else begin
                    count_next = normal_start;
                end
                actcnt_next = {{(nActCountBits-1){1'b0}},1'b1};
                state_next = ST_INVPRE_ST;
            end
        end

        ST_INVPRE_ST, ST_INVPRE: begin
            if (add_ready) begin
                tmp_next = m_tau_p1;
                count_next = next_count_val;
                state_next = ST_INV_ST;
            end else begin
                state_next = ST_INVPRE;
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
            if (all_elems_ready) begin
                count_next = next_count_val;
                if (count_reg[0]) begin
                    if (doDotProduct == 0) begin
                        state_next = ST_IDLE;
                    end else begin
                        state_next = ST_DOTP_ST;
                    end
                end else begin
                    if (actcnt_reg == {(nActCountBits){1'b1}}) begin
                        preload_next = 1'b0;
                    end
                    actcnt_next = next_actcnt_val;
                    state_next = ST_INV_ST;
                end
            end else begin
                state_next = ST_GRUN;
            end
        end

        ST_DOTP_ST, ST_DOTP: begin
            if (all_elems_ready) begin
                state_next = ST_ADDT_ST;
            end else begin
                state_next = ST_DOTP;
            end
        end

        ST_ADDT_ST, ST_ADDT: begin
            if (addt_in_ready) begin
                state_next = ST_ADDT_SH;
            end else begin
                state_next = ST_ADDT;
            end
        end

        ST_ADDT_SH: begin
            count_next = count_reg + 1;
            if (count_reg == {{(nParBits+1){1'b0}},{(nValBitsPer-1){1'b1}}}) begin
                state_next = ST_ADDT_WAIT;
            end else begin
                state_next = ST_ADDT_ST;
            end
        end

        ST_ADDT_WAIT: begin
            if (addt_idle & add_ready) begin
                state_next = ST_IDLE;
            end
        end
    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        state_reg <= ST_IDLE;
        count_reg <= {(nValBits){1'b0}};
        preload_reg <= 1'b0;
        actcnt_reg <= {(nActCountBits){1'b0}};
        tmp_reg <= {(`F_NBITS){1'b0}};
    end else begin
        en_dly <= en;
        state_reg <= state_next;
        count_reg <= count_next;
        preload_reg <= preload_next;
        actcnt_reg <= actcnt_next;
        tmp_reg <= tmp_next;
    end
end

genvar INum;
generate
    for (INum = 0; INum < nParallel; INum = INum + 1) begin: AddTHookup
        localparam addtoffset = INum * nValuesPer;
        assign addt_in[2*INum] = chi_out[addtoffset];
        assign addt_in[2*INum + 1] = chi_out[addtoffset + 1];
    end
    if (doDotProduct == 0) begin: NoAddTree
        assign addt_idle = 1'b1;
        assign addt_in_ready = 1'b1;
        assign addt_out_ready_pulse = 1'b0;
        assign addt_out = {(`F_NBITS){1'b0}};
    end else begin: AddTree
        prover_adder_tree_pl
            #( .ngates          (2*nParallel)
             , .ntagb           (1)
             ) iAddT
             ( .clk             (clk)
             , .rstb            (rstb)
             , .en              (addt_en)
             , .in              (addt_in)
             , .in_tag          (addt_in_tag)
             , .idle            (addt_idle)
             , .in_ready_pulse  ()
             , .in_ready        (addt_in_ready)
             , .out_ready_pulse (addt_out_ready_pulse)
             , .out_ready       (addt_out_ready)
             , .out             (addt_out)
             , .out_tag         (addt_out_tag)
             );
    end
endgenerate

wire [`F_NBITS-1:0] add_in0 = do_invert ? ~tau_reg : (sum_restart ? {(`F_NBITS){1'b0}} : m_tau_p1);
wire [`F_NBITS-1:0] add_in1 = do_invert ? `F_Q_P2_MI : addt_out;
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

wire [`F_NBITS-1:0] preload_out [nParallel-1:0];
genvar GNum;
genvar SNum;
generate
    for (GNum = 0; GNum < nParallel; GNum = GNum + 1) begin: ParInst
        wire [`F_NBITS-1:0] invals_inst [1:0];
        wire shen_sig;

        if (doDotProduct == 0) begin: NoDotProduct
            assign invals_inst[0] = {(`F_NBITS){1'b0}};
            assign invals_inst[1] = {(`F_NBITS){1'b0}};
        end else begin: DotProduct
            localparam nshiftvals = 1 << (nValBitsPer - 1);
            localparam noffset = 2 * nshiftvals * GNum;
            for (SNum = 0; SNum < 2; SNum = SNum + 1) begin: SRInst
                wire [`F_NBITS-1:0] shin [nshiftvals-1:0];
                for (INum = 0; INum < nshiftvals; INum = INum + 1) begin: SRHookup
                    assign shin[INum] = vals_in[noffset + 2 * INum + SNum];
                end
                shiftreg_simple
                    #( .nbits       (`F_NBITS)
                     , .nwords      (nshiftvals)
                     ) iSR0
                     ( .clk         (clk)
                     , .rstb        (rstb)
                     , .wren        (shld_en)
                     , .shen        (shld_en | shen_sig)
                     , .d           (shin)
                     , .q           (invals_inst[SNum])
                     , .q_all       ()
                     );
             end
        end

        wire [`F_NBITS-1:0] preload_out_inst [1:0];
        if (GNum < (nParallel >> 1)) begin: PreloadHookup
            assign preload_out[2*GNum] = preload_out_inst[0];
            assign preload_out[2*GNum + 1] = preload_out_inst[1];
        end

        localparam nvaloffset = GNum * nValuesPer;
        wire [`F_NBITS-1:0] values_out_inst [nValuesPer-1:0];
        for (INum = 0; INum < nValuesPer; INum = INum + 1) begin: ValuesOutHookup
            assign chi_out[nvaloffset + INum] = values_out_inst[INum];
        end

        wire en_sig;
        wire [`F_NBITS-1:0] preload_in_inst;
        if (GNum < 2) begin: FirstHookup
            wire alt_select = actcnt_reg == {{(nActCountBits-1){1'b0}},1'b1};
            assign en_sig = elems_en & actcnt_reg[0];
            if (GNum == 0) begin: ZeroAltHookup
                assign preload_in_inst = alt_select ? tmp_reg : preload_out[GNum];
            end else begin: OneAltHookup
                wire [`F_NBITS-1:0] start_tau = early ? tau[nEarlyBits-1] : tau[nValBits-1];
                assign preload_in_inst = alt_select ? start_tau : preload_out[GNum];
            end
        end else begin: RestHookup
            localparam actBit = $clog2(GNum + 1) - 1;
            assign en_sig = elems_en & actcnt_reg[actBit];
            assign preload_in_inst = preload_out[GNum];
        end

        verifier_compute_chi_elem
            #( .nValBits        (nValBitsPer)
             ) iChiElm
             ( .clk             (clk)
             , .rstb            (rstb)
             , .en              (en_sig)
             , .preload         (preload_reg)
             , .direct_load     (1'b0)
             , .mul_invals      (mul_en)
             , .invals          (invals_inst)
             , .shen_out        (shen_sig)
             , .shen_in         (addsh_en)
             , .preload_in      (preload_in_inst)
             , .preload_out     (preload_out_inst)
             , .tau             (tau_reg)
             , .m_tau_p1        (m_tau_p1)
             , .ready           (elem_ready[GNum])
             , .values_out      (values_out_inst)
             );
    end
endgenerate

endmodule
`define __module_verifier_compute_chi
`endif // __module_verifier_compute_chi
