// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012

`include "simulator.v"
`include "field_arith_defs.v"
`include "lagrange_interpolate.sv"
`include "ringbuf_simple.sv"
module test ();

localparam npoints = 9;

reg clk, rstb, en, trig;
reg [`F_NBITS-1:0] yi [npoints-1:0];
wire c_wren, ready_pulse;
wire [`F_NBITS-1:0] c_data;
wire [`F_NBITS-1:0] c_all [npoints-1:0];
ringbuf_simple
  #( .nbits         (`F_NBITS)
   , .nwords        (npoints)
   ) icoeffs
   ( .clk           (clk)
   , .rstb          (rstb)
   , .en            (c_wren)
   , .wren          (c_wren)
   , .d             (c_data)
   , .q             ()
   , .q_all         (c_all)
   );

lagrange_interpolate
  #( .npoints       (npoints)
   ) iinterp
   ( .clk           (clk)
   , .rstb          (rstb)
   , .en            (en | trig)
   , .yi            (yi)
   , .c_wren        (c_wren)
   , .c_data        (c_data)
   , .ready         ()
   , .ready_pulse   (ready_pulse)
   );

integer i, rseed;
initial begin
    $dumpfile("lagrange_interpolate_test.fst");
    $dumpvars;
    for (i = 0; i < npoints; i = i + 1) begin
        $dumpvars(0, yi[i], c_all[i]);
    end
    rseed = 1;
    randomize_yi();
    clk = 0;
    rstb = 0;
    trig = 0;
    en = 0;
    #1 rstb = 1;
    clk = 1;
    #2 trig = 1;
    #2 trig = 0;
    #1000 $finish;
end

`ALWAYS_FF @(posedge clk) begin
    en <= ready_pulse;
    if (ready_pulse) begin
        check_outputs();
        randomize_yi();
    end
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

task check_outputs;
    integer i, j, k;
    reg [`F_NBITS-1:0] tmp;
begin
    for (i = 0; i < npoints; i = i + 1) begin
        tmp = c_all[npoints-1];
        for (j = npoints - 2; j >= 0; j = j - 1) begin
            tmp = $f_mul(tmp, i);
            tmp = $f_add(tmp, c_all[j]);
        end
        $display("%h %h %s", tmp, yi[i], tmp == yi[i] ? ":)" : "!!");
    end
end
endtask

task randomize_yi;
    integer i;
begin
    for (i = 0; i < npoints; i = i + 1) begin
        yi[i] = $random(rseed);
        yi[i] = {yi[i][31:0],32'b0} | $random(rseed);
    end
    $display();
end
endtask


endmodule
