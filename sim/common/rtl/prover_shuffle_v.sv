// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// shuffle outputs of prover_compute_v
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_prover_shuffle_v
`include "simulator.v"
`include "field_arith_defs.v"
`include "prover_shuffle_v_elem.sv"
module prover_shuffle_v
   #( parameter nInBits = 8
    , parameter plstages = 0        // # of _elem stages between pipeline registers
// NOTE do not override parameters below this line //
    , parameter ngates = 1 << nInBits
   )( input                 clk
    , input                 rstb

    , input                 en
    , input                 restart

    , input  [`F_NBITS-1:0] v_in [ngates-1:0]

    , output                ready_pulse
    , output                ready

    , output [`F_NBITS-1:0] v_out [ngates-1:0]
    );

// sanity check
generate
    if (ngates != (1 << nInBits)) begin: IErr1
        Error_do_not_override_ngates_in_prover_shuffle_v __error__();
    end
endgenerate

// generate enable pulse
reg en_dly;
wire inc = en & ~en_dly;

// counter register - decides which shuffle elements are active
reg [nInBits-1:0] count_reg;
// if restarting, all layers are "inactive"
// at each increment, a new layer becomes active
wire [nInBits-1:0] count_next =
    inc ? (restart ? {(nInBits){1'b0}}
                   : {1'b1,count_reg[nInBits-1:1]})
        : count_reg;

// wires for hooking up the shuffle trees
wire [`F_NBITS-1:0] layer_out [nInBits-1:-1] [ngates-1:0];

// generate ready pulse
reg ready_dly;
assign ready_pulse = ready & ~ready_dly;

// ready signal that respects the pipeline delay
generate
    if (plstages == 0) begin: RNoPipe
        assign ready = ~inc;
    end else begin: RPipe
        localparam plcount_max = nInBits / plstages;
        localparam bcount = $clog2(plcount_max + 1);    // +1 so we can store plcount

        // counter for pipeline delay
        reg [bcount-1:0] plcount_reg;
        wire plcount_done = plcount_reg == plcount_max;
        wire [bcount-1:0] plcount_next = inc ? 0 : (plcount_done ? plcount_max : plcount_reg + 1);
        assign ready = ~inc & plcount_done;

        // update pl counter
        `ALWAYS_FF @(posedge clk or negedge rstb) begin
            if (~rstb) begin
                plcount_reg <= plcount_max;
            end else begin
                plcount_reg <= plcount_next;
            end
        end
    end
endgenerate

// hookup for inputs and outputs
genvar GateNum;
generate
    // wire up inputs to the first level of the shuffle tree
    assign layer_out[-1][0] = v_in[0];

    // try to catch errors by assigning unused elements to X
    for (GateNum = 1; GateNum < ngates; GateNum = GateNum + 1) begin: SInputs
        assign layer_out[-1][GateNum] = {(`F_NBITS){1'bX}};
    end

    // wire up outputs
    for (GateNum = 0; GateNum < ngates; GateNum = GateNum + 1) begin: SRegOutputs
        assign v_out[GateNum] = layer_out[nInBits-1][GateNum];
    end
endgenerate

// shuffle tree including parameterized pipelining
genvar Layer;
generate
    // generate each layer of the shuffle tree
    for (Layer = 0; Layer < nInBits; Layer = Layer + 1) begin: SLayer // SLAYERRRRRRR
        // hookup wires for pipelining
        localparam this_ngates = 2 << Layer;
        wire [`F_NBITS-1:0] layer_pl [this_ngates-1:0];

        // if we should insert pipelining after this stage, do so
        if ((plstages != 0) && ((Layer + 1) % plstages == 0)) begin: SPipe
            // first, declare registers and their inputs
            reg [`F_NBITS-1:0] layer_reg [this_ngates-1:0];
            integer GateNumI;
            `ALWAYS_FF @(posedge clk or negedge rstb) begin
                if (~rstb) begin
                    for (GateNumI = 0; GateNumI < this_ngates; GateNumI = GateNumI + 1) begin
                        layer_reg[GateNumI] <= 0;
                    end
                end else begin
                    for (GateNumI = 0; GateNumI < this_ngates; GateNumI = GateNumI + 1) begin
                        layer_reg[GateNumI] <= layer_pl[GateNumI];
                    end
                end
            end

            // then hook up the stage outputs to these registers
            for (GateNum = 0; GateNum < this_ngates; GateNum = GateNum + 1) begin: SPipeHookup
                assign layer_out[Layer][GateNum] = layer_reg[GateNum];
            end
        end else begin: SNoPipe
            // otherwise, no registers, just wire straight through
            for (GateNum = 0; GateNum < this_ngates; GateNum = GateNum + 1) begin: SNoPipeHookup
                assign layer_out[Layer][GateNum] = layer_pl[GateNum];
            end
        end

        // connect outputs from this layer
        for (GateNum = 0; GateNum < this_ngates / 2; GateNum = GateNum + 1) begin: SGate
            prover_shuffle_v_elem ishuf
                ( .in_act       (layer_out[Layer-1][GateNum])
                , .in_nact_0    (v_in[GateNum*2])
                , .in_nact_1    (v_in[GateNum*2+1])
                , .act          (count_reg[Layer])
                , .out_0        (layer_pl[GateNum*2])
                , .out_1        (layer_pl[GateNum*2+1])
                );
        end

        // set all other outputs from this layer to X to (maybe) catch errors
        for (GateNum = this_ngates; GateNum < ngates; GateNum = GateNum + 1) begin: SDfl
            assign layer_out[Layer][GateNum] = {(`F_NBITS){1'bX}};
        end
    end
endgenerate

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1;
        ready_dly <= 1;
        count_reg <= 0;
    end else begin
        en_dly <= en;
        ready_dly <= ready;
        count_reg <= count_next;
    end
end

endmodule
`define __module_prover_shuffle_v
`endif // __module_prover_shuffle_v
