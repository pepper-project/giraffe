// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// constant function (used in generate block during elaboration)
// find least set bit posn in input number
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

//   **NOTE** Icarus 0.9.x does not support const functions; you
//   will need to use a later release!
function integer leastSetBitPosn;
    input val;
    input nbits;
    integer val, nbits, posn, maxpos, i;
begin
    posn = nbits;
    for (i = 0; i < nbits; i = i + 1) begin
        if ((posn >= nbits) && (val & (1 << i))) begin
            posn = i;
        end
    end
    leastSetBitPosn = posn;
end
endfunction
