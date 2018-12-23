// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// compute i/o with selectable parallelism
// (C) 2016 Riad S. Wahby

`ifndef __module_verifier_compute_io
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
`include "verifier_compute_io_elembank.sv"
module verifier_compute_io
    #( parameter                nValBits = 8
     , parameter                nParBits = 1
// NOTE do not override any parameters below this line //
     , parameter                nValues = 1 << nValBits
    )( input                    clk
     , input                    rstb

     , input                    en

     , input  [`F_NBITS-1:0]    tau [nValBits-1:0]
     , input  [`F_NBITS-1:0]    vals_in [nValues-1:0]

     , output [`F_NBITS-1:0]    mlext_out

     , output                   ready
     );

// sanity check
generate
    if (nValues != (1 << nValBits)) begin: IErr1
        Error_do_not_override_nValues_in_verifier_compute_io __error__();
    end
    if (nParBits < 0) begin: IErr2
        Error_nParBits_must_be_at_least_zero_in_verifier_compute_io __error__();
    end
    if (nValBits - nParBits < 2) begin: IErr3
        // too much parallelism introduces some weird corner cases that I don't want to handle
        Error_nValBits_must_be_at_least_two_more_than_nParBits_in_verifier_compute_io __error__();
    end
endgenerate

reg [`F_NBITS-1:0] tau_reg;
reg [nValBits-1:0] count_reg, count_next;

wire ready_add, ready_bank;
wire restart_bank = count_reg[0];
reg en_dly;
wire start = en & ~en_dly;
enum { ST_IDLE, ST_INV_ST, ST_INV, ST_BANK_ST, ST_BANK, ST_WAIT_BANK, ST_WAIT_IDLE } state_reg, state_next;
assign ready = (state_reg == ST_IDLE) & ~start;
wire en_add = state_reg == ST_INV_ST;
wire en_bank = state_reg == ST_BANK_ST;

integer GNumC;
`ALWAYS_COMB begin
    state_next = state_reg;
    count_next = count_reg;
    tau_reg = {(`F_NBITS){1'bX}};
    for (GNumC = 0; GNumC < nValBits; GNumC = GNumC + 1) begin
        if (count_reg[GNumC]) begin
            tau_reg = tau[GNumC];
        end
    end

    case (state_reg)
        ST_IDLE: begin
            if (start) begin
                count_next = {{(nValBits-1){1'b0}},1'b1};
                state_next = ST_INV_ST;
            end
        end

        ST_INV_ST, ST_INV: begin
            if (~en_add & ready_add) begin
                state_next = ST_WAIT_BANK;
            end else begin
                state_next = ST_INV;
            end
        end

        ST_WAIT_BANK: begin
            if (ready_bank) begin
                state_next = ST_BANK_ST;
            end
        end

        ST_WAIT_IDLE: begin
            if (ready_bank) begin
                state_next = ST_IDLE;
            end
        end

        ST_BANK_ST, ST_BANK: begin
            if (~en_bank) begin
                count_next = {count_reg[nValBits-2:0],1'b0};
                if (count_reg[nValBits-1]) begin
                    state_next = ST_WAIT_IDLE;
                end else begin
                    state_next = ST_INV_ST;
                end
            end else begin
                state_next = ST_BANK;
            end
        end
    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1'b1;
        state_reg <= ST_IDLE;
        count_reg <= {{(nValBits-1){1'b0}},1'b1};
    end else begin
        en_dly <= en;
        state_reg <= state_next;
        count_reg <= count_next;
    end
end

wire [`F_NBITS-1:0] m_tau_p1;
wire [`F_NBITS-1:0] add_in0 = ~tau_reg;
wire [`F_NBITS-1:0] add_in1 = `F_Q_P2_MI;
field_adder iAdd
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en_add)
    , .a            (add_in0)
    , .b            (add_in1)
    , .ready_pulse  ()
    , .ready        (ready_add)
    , .c            (m_tau_p1)
    );

verifier_compute_io_elembank
   #( .nCopyBits    (nValBits)
    , .nParBits     (nParBits)
    ) iBank
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en_bank)
    , .restart      (restart_bank)
    , .tau          (tau_reg)
    , .m_tau_p1     (m_tau_p1)
    , .in_vals      (vals_in)
    , .final_out    (mlext_out)
    , .ready        (ready_bank)
    , .ready_pulse  ()
    );

endmodule
`define __module_verifier_compute_io
`endif // __module_verifier_compute_io
