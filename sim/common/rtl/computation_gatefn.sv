// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// compute a given gate's function
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_computation_gatefn
`include "simulator.v"
`include "field_arith_defs.v"
`include "gatefn_defs.v"
`include "field_adder.sv"
`include "field_multiplier.sv"
`include "field_mux.sv"
`include "field_subtract.sv"
module computation_gatefn
   #( parameter [`GATEFN_BITS-1:0] gate_fn = 0
   )( input                 clk
    , input                 rstb

    , input                 en
    , input                 mux_sel
    , input  [`F_NBITS-1:0] in0
    , input  [`F_NBITS-1:0] in1

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] out
    );

generate
    case (gate_fn)
        `GATEFN_ADD: begin: IAdd
            // adder
            field_adder iadd
                ( .clk          (clk)
                , .rstb         (rstb)
                , .en           (en)
                , .a            (in0)
                , .b            (in1)
                , .ready_pulse  (ready_pulse)
                , .ready        (ready)
                , .c            (out)
                );
        end

        `GATEFN_MUL: begin: IMul
            // multiplier
            field_multiplier imul
                ( .clk          (clk)
                , .rstb         (rstb)
                , .en           (en)
                , .a            (in0)
                , .b            (in1)
                , .ready_pulse  (ready_pulse)
                , .ready        (ready)
                , .c            (out)
                );
        end

        `GATEFN_SUB: begin: ISub
            // subtraction
            field_subtract isub
                ( .clk          (clk)
                , .rstb         (rstb)
                , .en           (en)
                , .a            (in0)
                , .b            (in1)
                , .ready_pulse  (ready_pulse)
                , .ready        (ready)
                , .c            (out)
                );
        end

        `GATEFN_MUX: begin: IMux
            // multiplexer
            field_mux imux
                ( .clk          (clk)
                , .rstb         (rstb)
                , .en           (en)
                , .sel          (mux_sel)
                , .a            (in0)
                , .b            (in1)
                , .ready_pulse  (ready_pulse)
                , .ready        (ready)
                , .c            (out)
                );
        end

        default: begin: IErr1
            Error_attempt_to_instantiate_undefined_gatefn __error__();
        end
    endcase
endgenerate

endmodule
`define __module_computation_gatefn
`endif // __module_computation_gatefn
