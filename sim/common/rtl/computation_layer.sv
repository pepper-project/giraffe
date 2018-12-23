// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// Compute one layer of an arithmetic circuit.
// (C) Riad S. Wahby <rsw@cs.nyu.edu>

// Given the same parameters as a prover_layer, this circuit just produces
// the output of that layer in the arithmetic circuit.

`ifndef __module_computation_layer
`include "simulator.v"
`include "field_arith_defs.v"
`include "gatefn_defs.v"
`include "computation_layer_elem.sv"
module computation_layer
   #( parameter ngates = 8
    , parameter ninputs = 8
    , parameter nmuxsels = 1                // number of entries in mux_sel

    , parameter nCopyBits = 2
    , parameter nParBits = 2

    , parameter [`GATEFN_BITS*ngates-1:0] gates_fn = 0

    , parameter ninbits = $clog2(ninputs)   // do not override
    , parameter nmuxbits = $clog2(nmuxsels < 2 ? 2 : nmuxsels) // do not override

    , parameter [(ninbits*ngates)-1:0] gates_in0 = 0
    , parameter [(ninbits*ngates)-1:0] gates_in1 = 0
    , parameter [(ngates*nmuxbits)-1:0] gates_mux = 0   // which gate goes to which mux_sel input?
// NOTE do not override below //
    , parameter nCopies = 1 << nCopyBits
   )( input                 clk
    , input                 rstb

    , input                 en
    , input  [`F_NBITS-1:0] v_in [nCopies-1:0] [ninputs-1:0]

    , input  [nmuxsels-1:0] mux_sel

    , output                ready
    , output [`F_NBITS-1:0] v_out [nCopies-1:0] [ngates-1:0]
    );

// make sure params are ok
generate
    if (ninbits != $clog2(ninputs)) begin: IErr1
        Error_do_not_override_ninbits_in_computation_layer __error__();
    end
    if (nmuxbits != $clog2(nmuxsels < 2 ? 2 : nmuxsels)) begin: IErr2
        Error_do_not_override_nmuxbits_in_computation_layer __error__();
    end
    if (nCopies != (1 << nCopyBits)) begin: IErr3
        Error_do_not_override_nCopies_in_computation_layer __error__();
    end
    if (nCopyBits < nParBits) begin: IErr4
        Error_nParBits_must_be_at_most_nCopyBits_in_computation_layer __error__();
    end
endgenerate

localparam nIters = 1 << (nCopyBits - nParBits);
localparam nParallel = 1 << nParBits;
localparam nCountBits = $clog2(nIters + 1);
reg [nCountBits-1:0] count_reg, count_next;

enum { ST_IDLE, ST_RUN_ST, ST_RUN } state_reg, state_next;
reg en_dly;
wire start = en & ~en_dly;
assign ready = (state_reg == ST_IDLE) & ~start;
wire en_gates = state_reg == ST_RUN_ST;

wire [nParallel-1:0] par_ready;
wire all_par_ready = &(par_ready);

`ALWAYS_COMB begin
    state_next = state_reg;
    count_next = count_reg;

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                count_next = {(nCountBits){1'b0}};
                state_next = ST_RUN_ST;
            end
        end

        ST_RUN_ST, ST_RUN: begin
            if (all_par_ready & ~en_gates) begin
                count_next = count_reg + 1'b1;
                if (count_reg == (nIters - 1)) begin
                    state_next = ST_IDLE;
                end else begin
                    state_next = ST_RUN_ST;
                end
            end else begin
                state_next = ST_RUN;
            end
        end
    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        state_reg <= ST_IDLE;
        count_reg <= {(nCountBits){1'b0}};
    end else begin
        en_dly <= en;
        state_reg <= state_next;
        count_reg <= count_next;
    end
end

genvar ParNum;
genvar IterNum;
genvar GateNum;
generate
    for (ParNum = 0; ParNum < nParallel; ParNum = ParNum + 1) begin: ParInst
        localparam iterOffset = ParNum * nIters;
        wire [`F_NBITS-1:0] v_in_par [nIters-1:0] [ninputs-1:0];
        wire [`F_NBITS-1:0] v_out_par [nIters-1:0] [ngates-1:0];

        for (IterNum = 0; IterNum < nIters; IterNum = IterNum + 1) begin: IterHookup
            for (GateNum = 0; GateNum < ninputs; GateNum = GateNum + 1) begin: IterHookupInput
                assign v_in_par[IterNum][GateNum] = v_in[iterOffset + IterNum][GateNum];
            end
            for (GateNum = 0; GateNum < ngates; GateNum = GateNum + 1) begin: IterHookupOutput
                assign v_out[iterOffset + IterNum][GateNum] = v_out_par[IterNum][GateNum];
            end
        end
        computation_layer_elem
           #( .ngates           (ngates)
            , .ninputs          (ninputs)
            , .nmuxsels         (nmuxsels)
            , .nIters           (nIters)
            , .nCountBits       (nCountBits)
            , .gates_fn         (gates_fn)
            , .gates_in0        (gates_in0)
            , .gates_in1        (gates_in1)
            , .gates_mux        (gates_mux)
            ) iElem
            ( .clk              (clk)
            , .rstb             (rstb)
            , .en               (en_gates)
            , .v_in             (v_in_par)
            , .count_in         (count_reg)
            , .mux_sel          (mux_sel)
            , .ready            (par_ready[ParNum])
            , .v_out            (v_out_par)
            );
    end
endgenerate

endmodule
`define __module_computation_layer
`endif // __module_computation_layer
