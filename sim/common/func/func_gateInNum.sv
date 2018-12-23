// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// Given gate number, figure out which input to connect to it
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

//   **NOTE** Icarus 0.9.x does not support const functions; you
//   will need to use a later release!
function integer gateInNum;
    input gnum;
    integer gnum, ni, i;
begin
    if (gnum <= nlast) begin
        gateInNum = gnum * nsteps;
    end else begin
        gateInNum = nlast * nsteps + (gnum - nlast) * (nsteps - 1);
    end
end
endfunction
