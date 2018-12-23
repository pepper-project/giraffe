// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// help for output layer prover: negate z1 and z2 to prep for computing z1_chi, beta
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __module_prover_shim_negate
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_one_minus.sv"
module prover_shim_negate
   #( parameter             nCopyBits = 3
    , parameter             nGateBits = 2
   )( input                 clk
    , input                 rstb

    , input                 en

    , input  [`F_NBITS-1:0] z1 [nGateBits-1:0]
    , input  [`F_NBITS-1:0] z2 [nCopyBits-1:0]

    , output [`F_NBITS-1:0] m_z1_p1 [nGateBits-1:0]
    , output [`F_NBITS-1:0] m_z2_p1 [nCopyBits-1:0]

    , output                z1_ready
    , output                ready
    );

localparam nInvs = nCopyBits > nGateBits ? nCopyBits : nGateBits;

enum { ST_IDLE, ST_Z1_ST, ST_Z1, ST_Z2_ST, ST_Z2 } state_reg, state_next;
reg en_dly;
wire start = en & ~en_dly;
assign ready = (state_reg == ST_IDLE) & ~start;
assign z1_ready = (state_reg == ST_Z2_ST) | (state_reg == ST_Z2);

wire z1_sel = (state_reg == ST_Z1_ST) | (state_reg == ST_Z1);
wire z2_sel = ~z1_sel;
wire inv_en = (state_reg == ST_Z1_ST) | (state_reg == ST_Z2_ST);
wire [nInvs-1:0] inv_ready;
wire all_inv_ready = &(inv_ready);
wire update_z1 = (state_reg == ST_Z1) & all_inv_ready;

wire [`F_NBITS-1:0] inv_out [nInvs-1:0];
wire [`F_NBITS-1:0] m_z1_p1_val [nGateBits-1:0];
wire [`F_NBITS-1:0] m_z2_p1_val [nCopyBits-1:0];
reg [`F_NBITS-1:0] m_z1_p1_reg [nGateBits-1:0];
assign m_z1_p1 = m_z1_p1_reg;
assign m_z2_p1 = m_z2_p1_val;

`ALWAYS_COMB begin
    state_next = state_reg;

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                state_next = ST_Z1_ST;
            end
        end

        ST_Z1_ST, ST_Z1: begin
            if (all_inv_ready) begin
                state_next = ST_Z2_ST;
            end else begin
                state_next = ST_Z1;
            end
        end

        ST_Z2_ST, ST_Z2: begin
            if (all_inv_ready) begin
                state_next = ST_IDLE;
            end else begin
                state_next = ST_Z2;
            end
        end
    endcase
end

integer GNumF;
`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        state_reg <= ST_IDLE;
        for (GNumF = 0; GNumF < nGateBits; GNumF = GNumF + 1) begin
            m_z1_p1_reg[GNumF] <= {(`F_NBITS){1'b0}};
        end
    end else begin
        en_dly <= en;
        state_reg <= state_next;
        for (GNumF = 0; GNumF < nGateBits; GNumF = GNumF + 1) begin
            m_z1_p1_reg[GNumF] <= update_z1 ? m_z1_p1_val[GNumF] : m_z1_p1_reg[GNumF];
        end
    end
end

genvar GNum;
generate
    for (GNum = 0; GNum < nInvs; GNum = GNum + 1) begin: InvInst
        wire [`F_NBITS-1:0] z1_in, z2_in;
        wire en_z1, en_z2;
        if (GNum < nGateBits) begin
            assign z1_in = z1[GNum];
            assign en_z1 = inv_en & z1_sel;
            assign m_z1_p1_val[GNum] = inv_out[GNum];
        end else begin
            assign z1_in = {(`F_NBITS){1'b0}};
            assign en_z1 = 1'b0;
        end
        if (GNum < nCopyBits) begin
            assign z2_in = z2[GNum];
            assign en_z2 = inv_en & z2_sel;
            assign m_z2_p1_val [GNum] = inv_out[GNum];
        end else begin
            assign z2_in = {(`F_NBITS){1'b0}};
            assign en_z2 = 1'b0;
        end
        wire [`F_NBITS-1:0] inv_in = z1_sel ? z1_in : z2_in;
        wire en_sig = en_z1 | en_z2;

        field_one_minus iOneM
            ( .clk      (clk)
            , .rstb     (rstb)
            , .en       (en_sig)
            , .a        (inv_in)
            , .ready_pulse ()
            , .ready    (inv_ready[GNum])
            , .c        (inv_out[GNum])
            );
    end
endgenerate

endmodule
`define __module_prover_shim_negate
`endif // __module_prover_shim_negate
