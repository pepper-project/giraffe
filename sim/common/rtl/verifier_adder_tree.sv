// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// generate adder tree to compute V(x) from components
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// After computing the contribution of each gate to V(0), V(1), or V(2),
// the Prover sums them. Here, we use an adder tree to implement this
// summation in lg(ngates) time with 2*ngates adders.

`ifndef __module_verifier_adder_tree
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
module verifier_adder_tree
   #( parameter ngates = 8      // number of gates
   )( input                 clk
    , input                 rstb

    , input                 en
    , input  [`F_NBITS-1:0] v_parts [ngates-1:0]

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] v
    );
`include "func_lvlNumInputs.sv"

// number of "levels" in the adder tree
// In this case, the same level is reused nlevels times
localparam nlevels = $clog2(ngates);

// ready signals per-level
localparam nadds = ngates / 2;
wire [nadds-1:0] add_ready;
wire all_ready = &(add_ready);
reg all_ready_dly;
wire all_ready_pulse = all_ready & ~all_ready_dly;
reg all_ready_pulse_dly;

// enable pulse
reg en_dly;
wire start = en & ~en_dly;

// counter
localparam ncbits = $clog2(nlevels + 1);
reg [ncbits-1:0] count_reg, count_next;
wire count_last = count_reg == (nlevels - 1);
wire count_done = count_reg == nlevels;

// ready
assign ready = count_done & all_ready;
reg ready_dly;
assign ready_pulse = ready & ~ready_dly;

// enable signals for the adders
wire lvl_en = start | (all_ready_pulse_dly & ~count_last);
wire [nadds-1:0] add_en_rnd [nlevels:0];
assign add_en_rnd[nlevels] = {(nadds){1'b1}};
assign add_en_rnd[nlevels-1] = {(nadds){1'b1}};
reg [nadds-1:0] en_reg, en_reg_dly;
wire [nadds-1:0] add_en = en_reg & {(nadds){lvl_en}};

// add_out holds outputs of the adders
localparam nouts = nadds + (ngates % 2);
wire [`F_NBITS-1:0] add_out [nouts-1:0];
assign v = add_out[0];

genvar IterNum;
genvar GateNum;
// figure out which gates are active each round
generate
    for (IterNum = 1; IterNum < nlevels; IterNum = IterNum + 1) begin: CompIter
        localparam nin = lvlNumInputs(IterNum) + 1;
        for (GateNum = 0; GateNum < nadds; GateNum = GateNum + 1) begin: CompIterGate
            if (GateNum < nin / 2) begin: GateEn
                assign add_en_rnd[IterNum-1][GateNum] = 1'b1;
            end else begin: GateDis
                assign add_en_rnd[IterNum-1][GateNum] = 1'b0;
            end
        end
    end
endgenerate

// generate the field adders (and maybe a buffer)
generate
    for (GateNum = 0; GateNum < nadds; GateNum = GateNum + 1) begin: IAdd
        // hook up input a to adder
        wire [`F_NBITS-1:0] add_a_cont;
        if (2*GateNum < nouts) begin
            assign add_a_cont = add_out[2*GateNum];
        end else begin
            assign add_a_cont = 0;
        end
        wire [`F_NBITS-1:0] add_a = count_done ? v_parts[2*GateNum] : add_a_cont;

        // hook up input b to adder
        wire [`F_NBITS-1:0] add_b_cont;
        if (2*GateNum + 1 < nouts) begin
            assign add_b_cont = add_out[2*GateNum+1];
        end else begin
            assign add_b_cont = 0;
        end
        wire [`F_NBITS-1:0] add_b = count_done ? v_parts[2*GateNum+1] : add_b_cont;

        // hook up adder's output, except that it becomes 0 after it's been inactive 1 cycle
        wire [`F_NBITS-1:0] add_c;
        assign add_out[GateNum] = (en_reg[GateNum] | en_reg_dly[GateNum]) ? add_c : 0;

        field_adder iadd
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (add_en[GateNum])
            , .a            (add_a)
            , .b            (add_b)
            , .ready_pulse  ()
            , .ready        (add_ready[GateNum])
            , .c            (add_c)
            );
    end
    if (ngates % 2 == 1) begin: IBuf
        reg [`F_NBITS-1:0] in_buf;
        assign add_out[nadds] = in_buf;
        `ALWAYS_FF @(posedge clk or negedge rstb) begin
            if (~rstb) begin
                in_buf <= 0;
            end else begin
                if (start) begin
                    in_buf <= v_parts[2*nadds];
                end
            end
        end
    end
endgenerate

// generate delayed lvl_ready signals to make ready pulses
`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        ready_dly <= 1;
        all_ready_dly <= 1;
        en_dly <= 1;
        all_ready_pulse_dly <= 0;
        count_reg = nlevels;
        en_reg <= {(nadds){1'b1}};
        en_reg_dly <= {(nadds){1'b1}};
    end else begin
        ready_dly <= ready;
        all_ready_dly <= all_ready;
        en_dly <= en;
        all_ready_pulse_dly <= all_ready_pulse;
        count_reg = start ? 0 : (all_ready_pulse_dly ? count_reg + 1 : count_reg);
        en_reg <= lvl_en ? add_en_rnd[count_reg] : en_reg;
        en_reg_dly <= lvl_en ? en_reg : en_reg_dly;
    end
end

endmodule
`define __module_verifier_adder_tree
`endif // __module_verifier_adder_tree
