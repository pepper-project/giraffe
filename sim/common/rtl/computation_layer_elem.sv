// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// Compute one layer of an arithmetic circuit.
// (C) Riad S. Wahby <rsw@cs.nyu.edu>

// One copy of an AC layer

`ifndef __module_computation_layer_elem
`include "simulator.v"
`include "field_arith_defs.v"
`include "gatefn_defs.v"
`include "computation_gatefn.sv"
`include "ringbuf_simple.sv"
module computation_layer_elem
   #( parameter ngates = 8
    , parameter ninputs = 8
    , parameter nmuxsels = 1                // number of entries in mux_sel

    , parameter nIters = 1
    , parameter nCountBits = 1

    , parameter [`GATEFN_BITS*ngates-1:0] gates_fn = 0

    , parameter ninbits = $clog2(ninputs)   // do not override
    , parameter nmuxbits = $clog2(nmuxsels < 2 ? 2 : nmuxsels) // do not override

    , parameter [(ninbits*ngates)-1:0] gates_in0 = 0
    , parameter [(ninbits*ngates)-1:0] gates_in1 = 0
    , parameter [(ngates*nmuxbits)-1:0] gates_mux = 0   // which gate goes to which mux_sel input?
// NOTE do not override below //
   )( input                 clk
    , input                 rstb

    , input                 en
    , input  [`F_NBITS-1:0] v_in [nIters-1:0] [ninputs-1:0]

    , input  [nCountBits-1:0] count_in
    , input  [nmuxsels-1:0] mux_sel

    , output                ready
    , output [`F_NBITS-1:0] v_out [nIters-1:0] [ngates-1:0]
    );

// make sure params are ok
generate
    if (ninbits != $clog2(ninputs)) begin: IErr1
        Error_do_not_override_ninbits_in_computation_layer_elem __error__();
    end
    if (nmuxbits != $clog2(nmuxsels < 2 ? 2 : nmuxsels)) begin: IErr2
        Error_do_not_override_nmuxbits_in_computation_layer_elem __error__();
    end
endgenerate

wire [ngates-1:0] gate_ready;
assign ready = &(gate_ready);

genvar GateNum;
generate
    for (GateNum = 0; GateNum < ngates; GateNum = GateNum + 1) begin: CompInst
        localparam [`GATEFN_BITS-1:0] gfn = gates_fn[(GateNum*`GATEFN_BITS) +: `GATEFN_BITS];
        localparam [ninbits-1:0] gi0 = gates_in0[(GateNum*ninbits) +: ninbits];
        localparam [ninbits-1:0] gi1 = gates_in1[(GateNum*ninbits) +: ninbits];

        // make sure that gmux is at least 1 bit wide
        localparam nb = nmuxbits == 0 ? 1 : nmuxbits;
        localparam [nmuxbits-1:0] gmux = gates_mux[(GateNum*nmuxbits) +: nb];

        if (gi0 >= ninputs || gi1 >= ninputs) begin: IErr4
            Illegal_input_number_declared_for_gate __error__();
        end

        reg [`F_NBITS-1:0] vin0, vin1;
        integer INumC;
        `ALWAYS_COMB begin
            vin0 = {(`F_NBITS){1'bX}};
            vin1 = {(`F_NBITS){1'bX}};
            for (INumC = 0; INumC < nIters; INumC = INumC + 1) begin
                if (INumC == count_in) begin
                    vin0 = v_in[INumC][gi0];
                    vin1 = v_in[INumC][gi1];
                end
            end
        end

        wire [`F_NBITS-1:0] gate_out;
        wire gate_ready_pulse;
        computation_gatefn
           #( .gate_fn      (gfn)
            ) igatefn
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (en)
            , .mux_sel      (mux_sel[gmux])
            , .in0          (vin0)
            , .in1          (vin1)
            , .ready_pulse  (gate_ready_pulse)
            , .ready        (gate_ready[GateNum])
            , .out          (gate_out)
            );
        if (nIters == 1) begin: NoRingBuf
            assign v_out[0][GateNum] = gate_out;
        end else begin: RingBuf
            wire [`F_NBITS-1:0] sr_out [nIters-1:0];
            ringbuf_simple
               #( .nbits    (`F_NBITS)
                , .nwords   (nIters)
                ) ibuf
                ( .clk      (clk)
                , .rstb     (rstb)
                , .en       (gate_ready_pulse)
                , .wren     (gate_ready_pulse)
                , .d        (gate_out)
                , .q        ()
                , .q_all    (sr_out)
                );
            for (IterNum = 0; IterNum < nIters; IterNum = IterNum + 1) begin: OutRegHookup
                assign v_out[IterNum][GateNum] = sr_out[IterNum];
            end
        end
    end
endgenerate

endmodule
`define __module_computation_layer_elem
`endif // __module_computation_layer_elem
