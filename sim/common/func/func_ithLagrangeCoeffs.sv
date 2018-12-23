// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2012
// modular reduction as a static function
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

//   **NOTE** Icarus 0.9.x does not support const functions; you
//   will need to use a later release!

// NOTE no if-guarding, needs to be instantiated *inside* a module
`include "simulator.v"
`include "field_arith_defs.v"

function reg [`F_NBITS-1:0] fieldReduce;
    input val;
    reg [2*`F_NBITS-1:0] val, tmp;
begin
    tmp = val % `F_Q;
    fieldReduce = tmp[`F_NBITS-1:0];
end
endfunction

function reg [`F_NBITS-1:0] fieldInvert;
    input val;
    reg [`F_NBITS-1:0] val;
    reg [2*`F_NBITS-1:0] s1, s2, r1, r2, t1, t2, q, tmp, tmp1, tmp2;
    integer i;
begin
    s1 = {(2*`F_NBITS){1'b0}};
    s2 = {{(2*`F_NBITS-1){1'b0}}, 1'b1};
    t1 = {{(2*`F_NBITS-1){1'b0}}, 1'b1};
    t2 = {(2*`F_NBITS){1'b0}};
    r1 = {{(`F_NBITS){1'b0}}, val};
    r2 = {{(`F_NBITS){1'b0}}, `F_Q};
    for (i = 0; r1 != {(2*`F_NBITS){1'b0}}; i++) begin
        q = r2 / r1;

        tmp1 = r1[`F_NBITS-1:0];
        tmp2 = r2[`F_NBITS-1:0];
        tmp = q[`F_NBITS-1:0] * tmp1;
        tmp = fieldReduce(tmp);
        tmp = tmp2 + `F_Q - tmp;
        tmp = fieldReduce(tmp);
        r2 = {{(`F_NBITS){1'b0}}, r1[`F_NBITS-1:0]};
        r1 = {{(`F_NBITS){1'b0}}, tmp};

        tmp1 = s1[`F_NBITS-1:0];
        tmp2 = s2[`F_NBITS-1:0];
        tmp = q[`F_NBITS-1:0] * tmp1;
        tmp = fieldReduce(tmp);
        tmp = tmp2 + `F_Q - tmp;
        tmp = fieldReduce(tmp);
        s2 = {{(`F_NBITS){1'b0}}, s1[`F_NBITS-1:0]};
        s1 = {{(`F_NBITS){1'b0}}, tmp};

        tmp1 = t1[`F_NBITS-1:0];
        tmp2 = t2[`F_NBITS-1:0];
        tmp = q[`F_NBITS-1:0] * tmp1;
        tmp = fieldReduce(tmp);
        tmp = tmp2 + `F_Q - tmp;
        tmp = fieldReduce(tmp);
        t2 = {{(`F_NBITS){1'b0}}, t1[`F_NBITS-1:0]};
        t1 = {{(`F_NBITS){1'b0}}, tmp};
    end
    fieldInvert = t2[`F_NBITS-1:0];
end
endfunction

function reg [npoints*`F_NBITS-1:0] ithLagrangeCoeffs;
    input j;
    integer j, m, i;
    reg [`F_NBITS-1:0] coeffs [npoints-1:-1], divisor;
    reg [2*`F_NBITS-1:0] tmp;
begin
    coeffs[-1] = {(`F_NBITS){1'b0}};
    coeffs[0] = {{(`F_NBITS-1){1'b0}}, 1'b1};
    for (m = 1; m < npoints; m++) begin
        coeffs[m] = {(`F_NBITS){1'b0}};
    end
    divisor = {{(`F_NBITS-1){1'b0}}, 1'b1};

    for (m = 0; m < npoints; m = m + 1) begin
        if (m != j) begin
            tmp = j + `F_Q - m;
            tmp = fieldReduce(tmp);
            tmp = tmp * divisor;
            tmp = fieldReduce(tmp);
            divisor = tmp[`F_NBITS-1:0];

            for (i = npoints - 1; i >= 0; i = i - 1) begin
                tmp = coeffs[i] * (`F_Q - m);
                tmp = fieldReduce(tmp);
                tmp = tmp + coeffs[i-1];
                tmp = fieldReduce(tmp);
                coeffs[i] = tmp[`F_NBITS-1:0];
            end
        end
    end

    ithLagrangeCoeffs = {(npoints*`F_NBITS){1'b0}};
    divisor = fieldInvert(divisor);
    for (m = 0; m < npoints; m = m + 1) begin
        tmp = coeffs[m] * divisor;
        tmp = fieldReduce(tmp);
        ithLagrangeCoeffs = ithLagrangeCoeffs | (tmp << (`F_NBITS*m));
    end
end
endfunction
