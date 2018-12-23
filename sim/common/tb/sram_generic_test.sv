// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// testbench for sram_generic
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

`include "sram_generic.sv"

module sram_generic_test ();

integer i;
integer rseed;
reg rden_1, wren_1, rden_2, wren_2, clk, rstb;
reg [8:0] addr_1, addr_2;
reg [31:0] data_1, data_2, q_1, q_2;

sram_generic
   #( .nbits        (32)
    , .nwords       (512)
    ) iram
    ( .clk          (clk)
    , .rstb         (rstb)
    , .rden_1       (rden_1)
    , .wren_1       (wren_1)
    , .addr_1       (addr_1)
    , .data_1       (data_1)
    , .q_1          (q_1)
    , .rden_2       (rden_2)
    , .wren_2       (wren_2)
    , .addr_2       (addr_2)
    , .data_2       (data_2)
    , .q_2          (q_2)
    );

initial begin
    $dumpfile("sram_generic_test.vcd");
    $dumpvars;
    rseed = 1000;
    clk = 0;
    rstb = 0;
    rden_1 = 0;
    rden_2 = 0;
    wren_1 = 0;
    wren_2 = 0;
    addr_1 = 0;
    addr_2 = 0;
    data_1 = 0;
    data_2 = 0;

    #1 clk = 1;
    #1 rstb = 1;

    for (i = 0; i < 1024; i = i + 1) begin
        addr_1 = i;
        addr_2 = ~i;
        data_1 = $random(rseed);
        data_2 = $random(rseed);
        wren_1 = 1;
        rden_2 = 1;
        #2 wren_1 = 0;
        rden_2 = 0;
        rden_1 = 1;
        wren_2 = 1;
        #2 rden_1 = 0;
        wren_2 = 0;
        rden_2 = 1;
        #2 rden_2 = 0;
    end
    $finish;
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

endmodule
