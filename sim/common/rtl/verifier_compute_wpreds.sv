// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// compute wiring predicates for one layer, then compute value given v1 and v2
// (C) 2016 Riad S. Wahby

`ifndef __module_verifier_compute_wpreds
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
`include "field_multiplier.sv"
`include "gatefn_defs.v"
`include "verifier_compute_beta.sv"
`include "verifier_compute_chi.sv"
`include "verifier_compute_chi_single.sv"
module verifier_compute_wpreds
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
   )( input                 clk
    , input                 rstb

    , input                 en
    , input  [nMuxSels-1:0] mux_sel

    , input  [`F_NBITS-1:0] z1_vals [nOutBits-1:0]
    , input  [`F_NBITS-1:0] w1_vals [nInBits-1:0]
    , input  [`F_NBITS-1:0] w2_vals [nInBits-1:0]

    , input  [`F_NBITS-1:0] z2_vals [nCopyBits-1:0]
    , input  [`F_NBITS-1:0] w3_vals [nCopyBits-1:0]

    , input  [`F_NBITS-1:0] tau_final
    , output [`F_NBITS-1:0] z1_out [nInBits-1:0]

    , input                 v1_v2_ready
    , input  [`F_NBITS-1:0] v1_val
    , input  [`F_NBITS-1:0] v2_val

    , output [`F_NBITS-1:0] v_out
    , output                ready
    );

// sanity check
generate
    if (nOutBits != $clog2(nGates)) begin: IErr1
        Error_do_not_override_nOutBits_in_verifier_compute_wpreds __error__();
    end
    if (nInBits != $clog2(nInputs)) begin: IErr2
        Error_do_not_override_nInBits_in_verifier_compute_wpreds __error__();
    end
    if (nMuxBits != $clog2(nMuxSels)) begin: IErr3
        Error_do_not_override_nMuxBits_in_verifier_compute_wpreds __error__();
    end
endgenerate

localparam nChiBits = nOutBits > nInBits ? nOutBits : nInBits;
localparam nEarlyBits = nOutBits > nInBits ? nInBits : nOutBits;
localparam nChis = 1 << nChiBits;
localparam nEarly = 1 << nEarlyBits;
localparam outBigger = nOutBits > nInBits ? 1 : 0;
localparam nInPer = 1 << (nInBits - nParBits);
localparam nOutPer = 1 << (nOutBits - nParBits);
localparam nParallel = 1 << nParBits;
localparam nCountBits = $clog2(nGates + 1) < 3 ? 3 : $clog2(nGates + 1);

reg [nCountBits-1:0] count_reg, count_next;

reg [`F_NBITS-1:0] add_in [1:0], mul_in [1:0];
wire add_ready, mul_ready;
wire [`F_NBITS-1:0] add_out, mul_out;

enum { ST_IDLE, ST_BETA_ST, ST_BETA, ST_Z0_ST, ST_Z0, ST_Z1_ST, ST_Z1, ST_Z2_ST, ST_Z2, ST_Z3_ST, ST_Z3, ST_ADDMUL_WAIT, ST_ADDMUL_ST, ST_ADDMUL, ST_INVMUL_ST, ST_INVMUL, ST_SUB_ST, ST_SUB, ST_GATE0_ST, ST_GATE0, ST_GATE1_ST, ST_GATE1, ST_GATE2_ST, ST_GATE2, ST_EVAL0_ST, ST_EVAL0, ST_EVAL1_ST, ST_EVAL1, ST_BETAMUL_ST, ST_BETAMUL } state_reg, state_next;
enum { ST2_IDLE, ST2_W1_ST, ST2_W1, ST2_W2_ST, ST2_W2, ST2_Z1_ST, ST2_Z1 } state2_reg, state2_next;

reg en_dly;
wire start = en & ~en_dly;
assign ready = (state_reg == ST_IDLE) & (state2_reg == ST_IDLE) & ~start;
wire start_chi = start & (state_reg == ST_IDLE);

wire inST_ADDMUL_ST = state_reg == ST_ADDMUL_ST;
wire inST_INVMUL_ST = state_reg == ST_INVMUL_ST;
wire inST_SUB_ST = state_reg == ST_SUB_ST;
wire inST_GATE0_ST = state_reg == ST_GATE0_ST;
wire inST_GATE1_ST = state_reg == ST_GATE1_ST;
wire inST_GATE2_ST = state_reg == ST_GATE2_ST;
wire inST_EVAL0_ST = state_reg == ST_EVAL0_ST;
wire inST_EVAL1_ST = state_reg == ST_EVAL1_ST;
wire inST_BETAMUL_ST = state_reg == ST_BETAMUL_ST;
wire inST_Z0_ST = state_reg == ST_Z0_ST;
wire inST_Z1_ST = state_reg == ST_Z1_ST;
wire inST_Z2_ST = state_reg == ST_Z2_ST;
wire inST_Z3_ST = state_reg == ST_Z3_ST;
wire write_znext = add_ready & (state_reg == ST_Z3);

wire add_en = inST_ADDMUL_ST | inST_INVMUL_ST | inST_SUB_ST | inST_GATE2_ST | inST_EVAL1_ST | inST_Z0_ST | inST_Z1_ST | inST_Z3_ST;
wire mul_en = inST_ADDMUL_ST | inST_GATE0_ST | inST_GATE1_ST | inST_EVAL0_ST | inST_BETAMUL_ST | inST_Z2_ST;

wire chi_ready;
wire all_chi_ready = (state2_reg == ST_IDLE) & ~start_chi;
wire select_z1_inputs = (state2_reg == ST2_Z1_ST) | (state2_reg == ST2_Z1);
wire select_w1_w2_inputs = ~select_z1_inputs;
wire select_w1_inputs = (state2_reg == ST2_W1_ST) | (state2_reg == ST2_W1);
wire update_w1_outputs = chi_ready & (state2_reg == ST2_W1);
wire update_w2_outputs = chi_ready & (state2_reg == ST2_W2);
wire chi_en = (state2_reg == ST2_W1_ST) | (state2_reg == ST2_W2_ST) | (state2_reg == ST2_Z1_ST);

wire [`F_NBITS-1:0] z1_chis [nChis-1:0];
wire [`F_NBITS-1:0] w1_w2_chis [nChis-1:0];
reg [`F_NBITS-1:0] w1_chis_reg [nInputs-1:0];
reg [`F_NBITS-1:0] w2_chis_reg [nInputs-1:0];
reg [`F_NBITS-1:0] wpred_reg [4:0], wpred_next [4:0];
reg [`F_NBITS-1:0] v1p2_reg, v1p2_next, v1x2_reg, v1x2_next, v1m2_reg, v1m2_next;
wire [`F_NBITS-1:0] wpvals [4:0];
assign wpvals[0] = v1p2_reg;
assign wpvals[1] = v1x2_reg;
assign wpvals[2] = v1m2_reg;
assign wpvals[3] = v1_val;
assign wpvals[4] = v2_val;
assign v_out = v1p2_reg;

wire [`GATEFN_BITS-1:0] gate_fn_vals [nGates-1:0];
wire [`F_NBITS-1:0] gate_in0_vals [nGates-1:0];
wire [`F_NBITS-1:0] gate_in1_vals [nGates-1:0];
wire [nGates-1:0] gate_mux_vals;

reg [`F_NBITS-1:0] gate_in0_sel, gate_in1_sel, gate_num_sel;
reg [`GATEFN_BITS-1:0] gate_fn_sel;
reg gate_mux_sel;
reg [2:0] function_select;

reg [`F_NBITS-1:0] eval_in0, eval_in1, znext_w1, znext_w2;
reg [`F_NBITS-1:0] z1_reg [nInBits-1:0], z1_next [nInBits-1:0];
assign z1_out = z1_reg;

wire beta_ready;
wire beta_restart;
wire [`F_NBITS-1:0] beta_out;

wire beta_en = state_reg == ST_BETA_ST;

integer GNumC;
`ALWAYS_COMB begin
    state2_next = state2_reg;
    state_next = state_reg;
    count_next = count_reg;
    v1p2_next = v1p2_reg;
    v1m2_next = v1m2_reg;
    v1x2_next = v1x2_reg;
    add_in[0] = {(`F_NBITS){1'bX}};
    add_in[1] = {(`F_NBITS){1'bX}};
    mul_in[0] = {(`F_NBITS){1'bX}};
    mul_in[1] = {(`F_NBITS){1'bX}};
    gate_in0_sel = {(`F_NBITS){1'bX}};
    gate_in1_sel = {(`F_NBITS){1'bX}};
    gate_fn_sel = {(`GATEFN_BITS){1'bX}};
    gate_mux_sel = 1'bX;
    eval_in0 = {(`F_NBITS){1'bX}};
    eval_in1 = {(`F_NBITS){1'bX}};
    for (GNumC = 0; GNumC < nGates; GNumC = GNumC + 1) begin
        if (GNumC == count_reg) begin
            gate_num_sel = z1_chis[GNumC];
            gate_in0_sel = gate_in0_vals[GNumC];
            gate_in1_sel = gate_in1_vals[GNumC];
            gate_mux_sel = gate_mux_vals[GNumC];
            gate_fn_sel = gate_fn_vals[GNumC];
        end
    end
    for (GNumC = 0; GNumC < 5; GNumC = GNumC + 1) begin
        wpred_next[GNumC] = wpred_reg[GNumC];
    end
    for (GNumC = 0; GNumC < 5; GNumC = GNumC + 1) begin
        if (count_reg == GNumC) begin
            eval_in0 = wpred_reg[GNumC];
            eval_in1 = wpvals[GNumC];
        end
    end
    for (GNumC = 0; GNumC < nInBits; GNumC = GNumC + 1) begin
        if (count_reg == GNumC) begin
            znext_w1 = w1_vals[GNumC];
            znext_w2 = w2_vals[GNumC];
        end
    end
    for (GNumC = 0; GNumC < nInBits; GNumC = GNumC + 1) begin
        if ((count_reg == GNumC) & write_znext) begin
            z1_next[GNumC] = add_out;
        end else begin
            z1_next[GNumC] = z1_reg[GNumC];
        end
    end

    //function_select = 3'b000;
    case (gate_fn_sel)
        `GATEFN_ADD: begin
            function_select = 3'b000;
        end
        `GATEFN_MUL: begin
            function_select = 3'b001;
        end
        `GATEFN_SUB: begin
            function_select = 3'b010;
        end
        `GATEFN_MUX: begin
            if (gate_mux_sel) begin
                function_select = 3'b100;
            end else begin
                function_select = 3'b011;
            end
        end
    endcase

    // this state machine just computes the values for the chis
    case (state2_reg)
        ST2_IDLE: begin
            if (start_chi) begin
                state2_next = ST2_W1_ST;
            end
        end

        ST2_W1_ST, ST2_W1: begin
            if (chi_ready) begin
                state2_next = ST2_W2_ST;
            end else begin
                state2_next = ST2_W1;
            end
        end

        ST2_W2_ST, ST2_W2: begin
            if (chi_ready) begin
                state2_next = ST2_Z1_ST;
            end else begin
                state2_next = ST2_W2;
            end
        end

        ST2_Z1_ST, ST2_Z1: begin
            if (chi_ready) begin
                state2_next = ST2_IDLE;
            end else begin
                state2_next = ST2_Z1;
            end
        end
    endcase

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                for (GNumC = 0; GNumC < 5; GNumC = GNumC + 1) begin
                    wpred_next[GNumC] = {(`F_NBITS){1'b0}};
                end
                count_next = {(nCountBits){1'b0}};
                state_next = ST_BETA_ST;
            end
        end

        ST_BETA_ST, ST_BETA: begin
            if (beta_ready) begin
                state_next = ST_Z0_ST;
            end else begin
                state_next = ST_BETA;
            end
        end

        ST_Z0_ST, ST_Z0: begin
            add_in[0] = ~znext_w1;
            add_in[1] = `F_Q_P1_MI;
            if (add_ready) begin
                state_next = ST_Z1_ST;
            end else begin
                state_next = ST_Z0;
            end
        end

        ST_Z1_ST, ST_Z1: begin
            add_in[0] = znext_w2;
            add_in[1] = add_out;
            if (add_ready) begin
                state_next = ST_Z2_ST;
            end else begin
                state_next = ST_Z1;
            end
        end

        ST_Z2_ST, ST_Z2: begin
            mul_in[0] = add_out;
            mul_in[1] = tau_final;
            if (mul_ready) begin
                state_next = ST_Z3_ST;
            end else begin
                state_next = ST_Z2;
            end
        end

        ST_Z3_ST, ST_Z3: begin
            add_in[0] = znext_w1;
            add_in[1] = mul_out;
            if (add_ready) begin
                if (count_reg == (nInBits - 1)) begin
                    count_next = {(`F_NBITS){1'b0}};
                    state_next = ST_ADDMUL_WAIT;
                end else begin
                    count_next = count_reg + 1'b1;
                    state_next = ST_Z0_ST;
                end
            end else begin
                state_next = ST_Z3;
            end
        end

        ST_ADDMUL_WAIT: begin
            if (v1_v2_ready) begin
                state_next = ST_ADDMUL_ST;
            end
        end

        ST_ADDMUL_ST, ST_ADDMUL: begin
            add_in[0] = v1_val;
            add_in[1] = v2_val;
            mul_in[0] = v1_val;
            mul_in[1] = v2_val;
            if (add_ready) begin
                v1p2_next = add_out;
                state_next = ST_INVMUL_ST;
            end else begin
                state_next = ST_ADDMUL;
            end
        end

        ST_INVMUL_ST, ST_INVMUL: begin
            add_in[0] = `F_Q_P1_MI;
            add_in[1] = ~v2_val;
            if (add_ready & mul_ready) begin
                v1x2_next = mul_out;
                state_next = ST_SUB_ST;
            end else begin
                state_next = ST_INVMUL;
            end
        end

        ST_SUB_ST, ST_SUB: begin
            add_in[0] = v1_val;
            add_in[1] = add_out;
            if (add_ready & all_chi_ready) begin
                v1m2_next = add_out;
                state_next = ST_GATE0_ST;
            end else begin
                state_next = ST_SUB;
            end
        end

        ST_GATE0_ST, ST_GATE0: begin
            mul_in[0] = gate_num_sel;
            mul_in[1] = gate_in0_sel;
            if (mul_ready) begin
                state_next = ST_GATE1_ST;
            end else begin
                state_next = ST_GATE0;
            end
        end

        ST_GATE1_ST, ST_GATE1: begin
            mul_in[0] = mul_out;
            mul_in[1] = gate_in1_sel;
            if (mul_ready) begin
                state_next = ST_GATE2_ST;
            end else begin
                state_next = ST_GATE1;
            end
        end

        ST_GATE2_ST, ST_GATE2: begin
            add_in[0] = wpred_reg[function_select];
            add_in[1] = mul_out;
            if (add_ready) begin
                wpred_next[function_select] = add_out;
                if (count_reg == nGates - 1) begin
                    count_next = {(`F_NBITS){1'b0}};
                    state_next = ST_EVAL0_ST;
                end else begin
                    count_next = count_reg + 1'b1;
                    state_next = ST_GATE0_ST;
                end
            end else begin
                state_next = ST_GATE2;
            end
        end

        ST_EVAL0_ST, ST_EVAL0: begin
            mul_in[0] = eval_in0;
            mul_in[1] = eval_in1;
            if (mul_ready) begin
                state_next = ST_EVAL1_ST;
            end else begin
                state_next = ST_EVAL0;
            end
        end

        ST_EVAL1_ST, ST_EVAL1: begin
            add_in[0] = (count_reg == {(nCountBits){1'b0}}) ? {(`F_NBITS){1'b0}} : add_out;
            add_in[1] = mul_out;
            if (add_ready) begin
                count_next = count_reg + 1'b1;
                if (count_reg == 3'b100) begin
                    state_next = ST_BETAMUL_ST;
                end else begin
                    state_next = ST_EVAL0_ST;
                end
            end else begin
                state_next = ST_EVAL1;
            end
        end

        ST_BETAMUL_ST, ST_BETAMUL: begin
            mul_in[0] = add_out;
            mul_in[1] = beta_out;
            if (mul_ready) begin
                v1p2_next = mul_out;
                state_next = ST_IDLE;
            end else begin
                state_next = ST_BETAMUL;
            end
        end
    endcase
end

integer GNumF;
`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        state_reg <= ST_IDLE;
        state2_reg <= ST2_IDLE;
        count_reg <= {(nCountBits){1'b0}};
        v1p2_reg <= {(`F_NBITS){1'b0}};
        v1m2_reg <= {(`F_NBITS){1'b0}};
        v1x2_reg <= {(`F_NBITS){1'b0}};
        for (GNumF = 0; GNumF < nInputs; GNumF = GNumF + 1) begin
            w1_chis_reg[GNumF] <= {(`F_NBITS){1'b0}};
            w2_chis_reg[GNumF] <= {(`F_NBITS){1'b0}};
        end
        for (GNumF = 0; GNumF < 5; GNumF = GNumF + 1) begin
            wpred_reg[GNumF] <= {(`F_NBITS){1'b0}};
        end
        for (GNumF = 0; GNumF < nInBits; GNumF = GNumF + 1) begin
            z1_reg[GNumF] <= {(`F_NBITS){1'b0}};
        end
    end else begin
        en_dly <= en;
        state_reg <= state_next;
        state2_reg <= state2_next;
        count_reg <= count_next;
        v1p2_reg <= v1p2_next;
        v1m2_reg <= v1m2_next;
        v1x2_reg <= v1x2_next;
        for (GNumF = 0; GNumF < nInputs; GNumF = GNumF + 1) begin
            w1_chis_reg[GNumF] <= update_w1_outputs ? w1_w2_chis[GNumF] : w1_chis_reg[GNumF];
            w2_chis_reg[GNumF] <= update_w2_outputs ? w1_w2_chis[GNumF] : w2_chis_reg[GNumF];
        end
        for (GNumF = 0; GNumF < 5; GNumF = GNumF + 1) begin
            wpred_reg[GNumF] <= wpred_next[GNumF];
        end
        for (GNumF = 0; GNumF < nInBits; GNumF = GNumF + 1) begin
            z1_reg[GNumF] <= z1_next[GNumF];
        end
    end
end

// gate hookup
genvar GNum;
generate
    for (GNum = 0; GNum < nGates; GNum = GNum + 1) begin
        localparam [nInBits-1:0] gi0 = gates_in0[(GNum*nInBits) +: nInBits];
        localparam [nInBits-1:0] gi1 = gates_in1[(GNum*nInBits) +: nInBits];

        assign gate_fn_vals[GNum] = gates_fn[(GNum*`GATEFN_BITS) +: `GATEFN_BITS];
        assign gate_in0_vals[GNum] = w1_chis_reg[gi0];
        assign gate_in1_vals[GNum] = w2_chis_reg[gi1];
    end
endgenerate

// hook up chi computation
wire [`F_NBITS-1:0] chis_in [nChiBits-1:0];
wire [`F_NBITS-1:0] chis_out [nChis-1:0];
wire chi_early;
genvar PNum;
genvar INum;
generate
    if (outBigger) begin
        assign chi_early = select_w1_w2_inputs;
    end else begin
        assign chi_early = select_z1_inputs;
    end
    for (INum = 0; INum < nChiBits; INum = INum + 1) begin: ChiInHookup
        wire [`F_NBITS-1:0] w1_w2_input;
        wire [`F_NBITS-1:0] z1_input;
        assign chis_in[INum] = select_w1_w2_inputs ? w1_w2_input : z1_input;
        if (INum >= nOutBits) begin: OutZeros
            assign z1_input = {(`F_NBITS){1'b0}};
        end else begin: OutHookup
            assign z1_input = z1_vals[INum];
        end
        if (INum >= nInBits) begin: InZeros
            assign w1_w2_input = {(`F_NBITS){1'b0}};
        end else begin: InHookup
            assign w1_w2_input = select_w1_inputs ? w1_vals[INum] : w2_vals[INum];
        end
    end
    for (PNum = 0; PNum < nParallel; PNum = PNum + 1) begin: ChiOutHookup
        if (outBigger) begin: InHookup
            localparam big_offset = PNum * nOutPer;
            localparam small_offset = PNum * nInPer;
            for (INum = 0; INum < nInPer; INum = INum + 1) begin: InAssign
                assign w1_w2_chis[small_offset + INum] = chis_out[big_offset + INum];
            end
            for (INum = 0; INum < nChis; INum = INum + 1) begin: ChiAssign
                assign z1_chis[INum] = chis_out[INum];
            end
        end else begin: OutHookup
            localparam big_offset = PNum * nInPer;
            localparam small_offset = PNum * nOutPer;
            for (INum = 0; INum < nOutPer; INum = INum + 1) begin: OutAssign
                assign z1_chis[small_offset + INum] = chis_out[big_offset + INum];
            end
            for (INum = 0; INum < nChis; INum = INum + 1) begin: ChiAssign
                assign w1_w2_chis[INum] = chis_out[INum];
            end
        end
    end
endgenerate

verifier_compute_beta
   #( .nCopyBits        (nCopyBits)
    ) iBeta
    ( .clk              (clk)
    , .rstb             (rstb)
    , .en               (beta_en)
    , .w_vals           (w3_vals)
    , .z_vals           (z2_vals)
    , .add_en_ext       (add_en)
    , .add_in_ext       (add_in)
    , .add_out_ext      (add_out)
    , .add_ready_ext    (add_ready)
    , .mul_en_ext       (mul_en)
    , .mul_in_ext       (mul_in)
    , .mul_out_ext      (mul_out)
    , .mul_ready_ext    (mul_ready)
    , .ready            (beta_ready)
    , .beta_out         (beta_out)
    );

generate
    if (nParBits == 0) begin: ChiSingle
        verifier_compute_chi_single
           #( .nValBits         (nChiBits)
            , .nEarlyBits       (nEarlyBits)
            ) iChi
            ( .clk              (clk)
            , .rstb             (rstb)
            , .en               (chi_en)
            , .early            (chi_early)
            , .tau              (chis_in)
            , .chi_out          (chis_out)
            , .ready            (chi_ready)
            );
    end else begin: ChiParallel
        wire [`F_NBITS-1:0] vals_in_zeros [nChis-1:0];
        for (INum = 0; INum < nChis; INum = INum + 1) begin: ZeroHookup
            assign vals_in_zeros[INum] = {(`F_NBITS){1'b0}};
        end
        verifier_compute_chi
           #( .nValBits         (nChiBits)
            , .nParBits         (nParBits)
            , .doDotProduct     (0)
            , .nEarlyBits       (nEarlyBits)
            ) iChi
            ( .clk              (clk)
            , .rstb             (rstb)
            , .en               (chi_en)
            , .early            (chi_early)
            , .tau              (chis_in)
            , .vals_in          (vals_in_zeros)
            , .dot_product_out  ()
            , .chi_out          (chis_out)
            , .ready            (chi_ready)
            );
    end
endgenerate

endmodule
`define __module_verifier_compute_wpreds
`endif // __module_verifier_compute_wpreds
