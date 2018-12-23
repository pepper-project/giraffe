// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// test the vpintf code
// (C) 2016 Riad S. Wahby <rsw@cs.stanford.edu>

`include "simulator.v"
`include "field_arith_defs.v"
`include "vpintf_defs.v"

module test ();

integer rseed;

initial begin
    rseed = 3;
    test_vpintf_task();
    $finish;
end

task test_vpintf_task;
    reg [`F_NBITS-1:0] inval, outval;
    reg [`F_NBITS-1:0] inarr [7:0];
    reg [`F_NBITS-1:0] outarr [7:0];
    integer i;
begin
    for (i = 0; i < 8; i = i + 1) begin
        inarr[i] = random_value();
    end
    inval = random_value();

    $display("initializing: id %d", $vpintf_init(`V_TYPE_LAY, 10));

    $vpintf_send(`V_SEND_Z1, 8, inarr);
    $vpintf_recv(`V_SEND_Z1, 8, outarr);
    for (i = 0; i < 8; i = i + 1) begin
        $display("%h %h %s", inarr[i], outarr[i], inarr[i] == outarr[i] ? ":)" : "!!!!!!");
    end

    $display("single test");
    $vpintf_send(`V_SEND_TAU, 1, inval);
    $vpintf_recv(`V_SEND_TAU, 1, outval);
    $display("%h %h %s", inval, outval, inval == outval ? ":)" : "!!!!!!");
end
endtask

function [`F_NBITS-1:0] random_value;
    integer i;
    reg [`F_NBITS-1:0] tmp;
begin
    tmp = $random(rseed);
    for (i = 0; i < (`F_NBITS / 32) + 1; i = i + 1) begin
        tmp = {tmp[`F_NBITS-33:0],32'b0} | $random(rseed);
    end
    random_value = tmp;
end
endfunction


endmodule
