// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// compute chi with selectable parallelism
// (C) 2016 Riad S. Wahby

`ifndef __module_verifier_compute_chi_elem
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_multiplier.sv"
`include "prover_compute_v_srelem.sv"
module verifier_compute_chi_elem
    #( parameter                nValBits = 2
// NOTE do not override below here //
     , parameter                nValues = 1 << nValBits
    )( input                    clk
     , input                    rstb

     , input                    en
     , input                    preload
     , input                    direct_load

     , input                    mul_invals
     , input  [`F_NBITS-1:0]    invals [1:0]
     , output                   shen_out
     , input                    shen_in

     , input  [`F_NBITS-1:0]    preload_in
     , output [`F_NBITS-1:0]    preload_out [1:0]

     , input  [`F_NBITS-1:0]    tau
     , input  [`F_NBITS-1:0]    m_tau_p1

     , output                   ready
     , output [`F_NBITS-1:0]    values_out [nValues-1:0]
     );

// sanity check
generate
    if (nValues != (1 << nValBits)) begin
        Error_do_not_override_nValues_in_verifier_compute_chi_elem __error__();
    end
endgenerate

localparam nEvenOdd = 1 << (nValBits - 1);
wire [`F_NBITS-1:0] evens [nEvenOdd-1:0];
wire [`F_NBITS-1:0] odds [nEvenOdd-1:0];

wire [1:0] mul_ready;
wire [`F_NBITS-1:0] mul_out [1:0];
wire all_mul_ready = &(mul_ready);
reg [`F_NBITS-1:0] mval_reg, mval_next;
assign preload_out = mul_out;

enum { ST_IDLE, ST_RESTART, ST_MUL1_ST, ST_MUL1, ST_BP, ST_MUL2_ST, ST_MUL2, ST_SH, ST_MUL3_ST, ST_MUL3, ST_INSH, ST_LOAD } state_reg, state_next;
reg en_dly;
wire start = en & ~en_dly;
wire ready = (state_reg == ST_IDLE) & ~start;

wire mul_en = (state_reg == ST_MUL1_ST) | (state_reg == ST_MUL2_ST) | (state_reg == ST_MUL3_ST);
wire sh_en = (state_reg == ST_SH) | (state_reg == ST_INSH) | shen_in;
wire bp_en = state_reg == ST_BP;
wire load_en = state_reg == ST_LOAD;
assign shen_out = state_reg == ST_INSH;
reg [nEvenOdd-1:0] bpsel_reg, bpsel_next;
reg [nEvenOdd-1:0] count_reg, count_next;

wire sel_inval = (state_reg == ST_MUL3_ST) | (state_reg == ST_MUL3);
wire [`F_NBITS-1:0] mul_in0 [1:0], mul_in1 [1:0];
assign mul_in0[0] = sel_inval ? invals[0] : mval_reg;
assign mul_in0[1] = sel_inval ? invals[1] : mval_reg;
assign mul_in1[0] = sel_inval ? evens[0] : m_tau_p1;
assign mul_in1[1] = sel_inval ? odds[0] : tau;

`ALWAYS_COMB begin
    mval_next = mval_reg;
    state_next = state_reg;
    bpsel_next = bpsel_reg;
    count_next = count_reg;

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                count_next = {{(nEvenOdd-1){1'b0}},1'b1};
                if (preload) begin
                    mval_next = preload_in;
                end else begin
                    mval_next = evens[0];
                end
                if (direct_load) begin
                    bpsel_next = {{(nEvenOdd-2){1'b0}},2'b10};
                    state_next = ST_LOAD;
                end else if (mul_invals) begin
                    bpsel_next = {1'b1,{(nEvenOdd-1){1'b0}}};
                    state_next = ST_MUL3_ST;
                end else if (preload) begin
                    bpsel_next = {{(nEvenOdd-1){1'b0}},1'b1};
                    state_next = ST_MUL2_ST;
                end else begin
                    state_next = ST_MUL1_ST;
                end
            end
        end

        ST_RESTART: begin
            mval_next = evens[0];
            state_next = ST_MUL1_ST;
        end

        ST_MUL1_ST, ST_MUL1: begin
            if (all_mul_ready) begin
                state_next = ST_BP;
            end else begin
                state_next = ST_MUL1;
            end
        end

        ST_BP: begin
            count_next = {count_reg[nEvenOdd-2:0],1'b0};
            state_next = ST_MUL2_ST;
            mval_next = odds[0];
        end

        ST_MUL2_ST, ST_MUL2: begin
            if (all_mul_ready) begin
                state_next = ST_SH;
            end else begin
                state_next = ST_MUL2;
            end
        end

        ST_SH: begin
            count_next = {count_reg[nEvenOdd-2:0],1'b0};
            bpsel_next = {bpsel_reg[nEvenOdd-2:0],1'b0};
            if (count_reg == bpsel_reg) begin
                state_next = ST_IDLE;
            end else begin
                state_next = ST_RESTART;
            end
        end

        ST_MUL3_ST, ST_MUL3: begin
            if (all_mul_ready) begin
                state_next = ST_INSH;
            end else begin
                state_next = ST_MUL3;
            end
        end

        ST_INSH: begin
            count_next = {count_reg[nEvenOdd-2:0],1'b0};
            if (count_reg == bpsel_reg) begin
                bpsel_next = {(nEvenOdd){1'b0}};
                state_next = ST_IDLE;
            end else begin
                state_next = ST_MUL3_ST;
            end
        end

        ST_LOAD: begin
            state_next = ST_IDLE;
        end
    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        mval_reg <= {(`F_NBITS){1'b0}};
        state_reg <= ST_IDLE;
        bpsel_reg <= {(nEvenOdd){1'b0}};
        count_reg <= {(nEvenOdd){1'b0}};
    end else begin
        en_dly <= en;
        mval_reg <= mval_next;
        state_reg <= state_next;
        bpsel_reg <= bpsel_next;
        count_reg <= count_next;
    end
end

field_multiplier IMul1
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (mul_en)
    , .a            (mul_in0[0])
    , .b            (mul_in1[0])
    , .ready_pulse  ()
    , .ready        (mul_ready[0])
    , .c            (mul_out[0])
    );

field_multiplier IMul2
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (mul_en)
    , .a            (mul_in0[1])
    , .b            (mul_in1[1])
    , .ready_pulse  ()
    , .ready        (mul_ready[1])
    , .c            (mul_out[1])
    );

genvar SRNum;
generate
    for (SRNum = 0; SRNum < nValues; SRNum = SRNum + 1) begin: SRElmGen
        wire [`F_NBITS-1:0] normal, out;
        localparam thisNum = SRNum >> 1;
        localparam mulNum = SRNum % 2;
        localparam predNum = (thisNum + 1) % nEvenOdd;
        assign values_out[SRNum] = out;
        if (mulNum == 0) begin: SREvenGen
            assign evens[thisNum] = out;
            assign normal = evens[predNum];
        end else begin: SROddGen
            assign odds[thisNum] = out;
            assign normal = odds[predNum];
        end

        wire shen_sig = sh_en | (bp_en & bpsel_reg[thisNum]);

        wire [`F_NBITS-1:0] in_load;
        wire load_sig;
        if (SRNum == 0) begin
            assign in_load = m_tau_p1;
            assign load_sig = load_en;
        end else if (SRNum == 1) begin
            assign in_load = tau;
            assign load_sig = load_en;
        end else begin
            assign in_load = {(`F_NBITS){1'b0}};
            assign load_sig = 1'b0;
        end

        prover_compute_v_srelem iSRElem
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (shen_sig | load_sig)
            , .load         (load_sig)
            , .bypass       (bpsel_reg[thisNum])
            , .in_normal    (normal)
            , .in_load      (in_load)
            , .in_bypass    (mul_out[mulNum])
            , .out          (out)
            );
    end
endgenerate

endmodule
`define __module_verifier_compute_chi_elem
`endif // __module_verifier_compute_chi_elem
