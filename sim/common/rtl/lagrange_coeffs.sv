// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// Generate Lagrange coefficients for a given degree polynomial
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

// WARNING: older versions of Icarus will go into an infinite loop
// elaborating this design.
//
// Commit a2fbdeff78ee9e1f82925510f5ac20213b920acf is known to work.

`ifndef __module_lagrange_coeffs
`include "simulator.v"
`include "field_arith_defs.v"
module lagrange_coeffs
   #( parameter npoints = 3
   )( output [`F_NBITS-1:0] coeffs [npoints-1:0] [npoints-2:0]
    );
`include "func_ithLagrangeCoeffs.sv"

genvar Group, Elem;
generate
for (Group = 0; Group < npoints; Group = Group + 1) begin: CoeffsGroup
    localparam [npoints*`F_NBITS-1:0] coeffs_wire = ithLagrangeCoeffs(Group);
    for (Elem = 1; Elem < npoints; Elem = Elem + 1) begin: CoeffsElem
        wire [`F_NBITS-1:0] coeff = coeffs_wire[`F_NBITS*(Elem+1)-1:`F_NBITS*Elem];
        assign coeffs[Group][Elem-1] = coeff;
    end
end
endgenerate

endmodule
`define __module_lagrange_coeffs
`endif // __module_lagrange_coeffs
