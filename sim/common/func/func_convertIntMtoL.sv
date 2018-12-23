// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// return integer that corresponds to bit-reversal of input integer
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

//   **NOTE** Icarus 0.9.x does not support const functions; you
//   will need to use a later release!
function integer convertIntMtoL;
    input val;
    input nbits;
    integer val, nbits, i;
    reg [31:0] treg;
begin
    treg = 0;
    for (i = 0; i < nbits; i = i + 1) begin
        if (val & (1 << i)) begin
            treg[nbits - 1 - i] = 1'b1;
        end
    end
    convertIntMtoL = treg;
end
endfunction
