// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// constant function (used in generate block during elaboration)
// Given a number of total gates and a level of the adder tree,
// figure out how many inputs are at this level of the tree
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

//   **NOTE** Icarus 0.9.x does not support const functions; you
//   will need to use a later release!
function integer lvlNumInputs;
    input lev;
    integer lev, ng, i;
begin
    ng = ngates;
    for (i = 0; i < lev; i = i + 1) begin
        ng = (ng / 2) + (ng % 2);
    end
    lvlNumInputs = ng;
end
endfunction
