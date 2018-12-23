// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// help for output layer prover: compute values needed by output layer
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_prover_shim
`include "simulator.v"
`include "field_arith_defs.v"
`include "prover_compute_h_chi.sv"
`include "prover_shim_negate.sv"
module prover_shim
   #( parameter             nCopyBits = 3
    , parameter             nGateBits = 2
// NOTE do not override below this line //
    , parameter             nGates = 1 << nGateBits
   )( input                 clk
    , input                 rstb

    , input                 en

    , input  [`F_NBITS-1:0] z1 [nGateBits-1:0]
    , input  [`F_NBITS-1:0] z2 [nCopyBits-1:0]

    , output [`F_NBITS-1:0] m_z2_p1 [nCopyBits-1:0]
    , output [`F_NBITS-1:0] z1_chi [nGates-1:0]

    , output                ready
    );

// sanity check
generate
    if (nGates != (1 << nGateBits)) begin: IErr1
        Error_do_not_override_nGates_in_prover_shim __error__();
    end
endgenerate

localparam nGatesHalf = 1 << (nGateBits - 1);
localparam nCountBits = $clog2(nGateBits + 1);

enum { ST_IDLE, ST_NEGATE_ST, ST_Z1_WAIT, ST_CHI_ST, ST_CHI, ST_NEGATE_WAIT } state_reg, state_next;
reg en_dly;
wire start = en & ~en_dly;
assign ready = (state_reg == ST_IDLE) & ~start;

reg [nCountBits-1:0] count_reg, count_next;
wire chi_en = state_reg == ST_CHI_ST;
wire negate_en = state_reg == ST_NEGATE_ST;
wire chi_restart = chi_en & (count_reg == {(nCountBits){1'b0}});
wire chi_ready, z1_ready, negate_ready;
reg [`F_NBITS-1:0] tau_reg, m_tau_p1_reg;
wire [`F_NBITS-1:0] m_z1_p1 [nGateBits-1:0];

integer GNumC;
`ALWAYS_COMB begin
    state_next = state_reg;
    count_next = count_reg;
    tau_reg = {(`F_NBITS){1'bX}};
    m_tau_p1_reg = {(`F_NBITS){1'bX}};
    for (GNumC = 0; GNumC < nGateBits; GNumC = GNumC + 1) begin
        if (GNumC == count_reg) begin
            tau_reg = z1[GNumC];
            m_tau_p1_reg = m_z1_p1[GNumC];
        end
    end

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                count_next = {(nCountBits){1'b0}};
                state_next = ST_NEGATE_ST;
            end
        end

        ST_Z1_WAIT, ST_NEGATE_ST: begin
            if (z1_ready) begin
                state_next = ST_CHI_ST;
            end else begin
                state_next = ST_Z1_WAIT;
            end
        end

        ST_CHI_ST, ST_CHI: begin
            if (chi_ready) begin
                count_next = count_reg + 1;
                if (count_reg == nGateBits - 1) begin
                    state_next = ST_NEGATE_WAIT;
                end else begin
                    state_next = ST_CHI_ST;
                end
            end else begin
                state_next = ST_CHI;
            end
        end

        ST_NEGATE_WAIT: begin
            if (negate_ready) begin
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
    end else begin
        en_dly <= en;
        state_reg <= state_next;
        count_reg <= count_next;
    end
end

prover_shim_negate
   #( .nCopyBits        (nCopyBits)
    , .nGateBits        (nGateBits)
    ) iNegate
    ( .clk              (clk)
    , .rstb             (rstb)
    , .en               (negate_en)
    , .z1               (z1)
    , .z2               (z2)
    , .m_z1_p1          (m_z1_p1)
    , .m_z2_p1          (m_z2_p1)
    , .z1_ready         (z1_ready)
    , .ready            (negate_ready)
    );

wire [`F_NBITS-1:0] mvals_out_dummy [nGatesHalf-1:0];
wire [`F_NBITS-1:0] mvals_in_zero [nGates-1:0];
genvar GNum;
generate
    for (GNum = 0; GNum < nGates; GNum = GNum + 1) begin: ZeroHookup
        assign mvals_in_zero[GNum] = {(`F_NBITS){1'b0}};
    end
endgenerate
prover_compute_h_chi
   #( .npoints          (nGateBits)
    ) iChi
    ( .clk              (clk)
    , .rstb             (rstb)
    , .en               (chi_en)
    , .restart          (chi_restart)
    , .tau              (tau_reg)
    , .m_tau_p1         (m_tau_p1_reg)
    , .addt_ready       (1'b0)
    , .mvals_in         (mvals_in_zero)
    , .addt_en          ()
    , .addt_tag         ()
    , .mvals_out        (mvals_out_dummy)
    , .chi_ready        ()
    , .ready_pulse      ()
    , .ready            (chi_ready)
    , .chi_out          (z1_chi)
    );

endmodule
`define __module_prover_shim
`endif // __module_prover_shim
