#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# Utilities

import math

from giraffelib.defs import Defs, FArith

def set_prime(p):
    Defs.prime = p
    Defs.half = invert_modp(2)
    Defs.third = invert_modp(3)
    Defs.nbits = clog2(p)

def flatten(inlists):
    outlist = []
    for inlist in inlists:
        if not isinstance(inlist, list):
            outlist.append(inlist)
            continue

        inlist = flatten(inlist)
        for elm in inlist:
            outlist.append(elm)

    return outlist

# lsb-to-msb order
def numToBin(val, bits):
    out = []
    for _ in range(0, bits):
        if val & 1:
            out.append(True)
        else:
            out.append(False)
        val = val >> 1
    return out


# reflected gray code
def numToGrayBin(val, bits):
    return numToBin(val ^ (val >> 1), bits)


# log2
def clog2(val):
    return int(math.ceil(math.log10(val)/math.log10(2)))


# chi: product over bits of x or 1-x depending on bit value
def chi(vec, vals):
    assert len(vals) <= len(vec)

    out = 1
    for (ninv, val) in zip(vec, vals):
        out *= val if ninv else (1 - val)
        out %= Defs.prime

    return out

def bit_is_set(val, bit):
    return val & (1 << bit) != 0

def bit_is_set_gray(val, bit):
    return bit_is_set(val ^ (val >> 1), bit)

def interpolate_quadratic((f0, f1, fm1)):
    # special-case interpolation for quadratic function

    # evaluated at 0, 1, and 2
    # q = -1 * f0                                       # inversion
    # a = ((f2 + q) * Defs.half) % Defs.prime           # add, mul
    # b = f1 + q                                        # add
    #
    # c0 = f0
    # c1 = (2 * b - a) % Defs.prime                     # add, sub
    # c2 = (a - b) % Defs.prime                         # sub
    #                                                   # total: 2 add, 3 sub, 1 mul

    # evaluated at 0, 1, and -1
    a = -1 * f0                                         # inversion
    c0 = f0 % Defs.prime
    c2 = (((f1 + fm1) * Defs.half) + a) % Defs.prime    # mul, 2 * add
    c1 = (f1 - c2 + a) % Defs.prime                     # sub, add

    return [c0, c1, c2]                                 # total: 2 add, 2 sub, 1 mul

def interpolate_cubic((f0, f1, fm1, f2)):
    # special-case interpolation for cubic function
    # evaluated at -1, 0, 1, 2
    a = -1 * fm1                                        # inversion
    b = ((f1 + fm1) * Defs.half) % Defs.prime           # add, mul      = c0 + c2
    c = ((f1 + a) * Defs.half) % Defs.prime             # add, mul      = c1 + c3
    d = ((f2 + a) * Defs.third) % Defs.prime            # add, mul      = c1 + c2 + 3 c3

    c0 = f0 % Defs.prime
    c2 = (b - f0) % Defs.prime                          # sub
    c3 = ((d - c - c2) * Defs.half) % Defs.prime        # 2 sub, mul
    c1 = (c - c3) % Defs.prime                          # sub

    return [c0, c1, c2, c3]                             # total: 2 add, 5 sub, 4 mul

# for interpolation after sumcheck rounds, we use the following points:

THIRD_EVAL_POINT = -1
FOURTH_EVAL_POINT = 2

def third_eval_point(val, bit):
    # eval at -1
    if bit:
        return THIRD_EVAL_POINT * val
    else:
        return (1 - THIRD_EVAL_POINT) * val

def fourth_eval_point(val, bit):
    # eval at 2
    if bit:
        return FOURTH_EVAL_POINT * val
    else:
        return (1 - FOURTH_EVAL_POINT) * val

def eval_beta_factors(bit):
    # eval at -1 and 2
    if bit:
        return (THIRD_EVAL_POINT, FOURTH_EVAL_POINT)
    else:
        return (1 - THIRD_EVAL_POINT, 1 - FOURTH_EVAL_POINT)

# given two vectors, a function, and an identity element, combine them
def proc_vecs(f, ident, a, b, rec=None):
    if rec is None:
        rec = FArith().new_cat("q")
    la = len(a)
    lb = len(b)
    lc = max(la, lb)
    ff = lambda i: f(a[i] if i < la else ident, b[i] if i < lb else ident, rec)
    c = [ ff(i) for i in range(0, lc) ]
    return c

# sum/diff two vectors elementwise
add_vecs = lambda a, b, rec=None: proc_vecs(lambda x, y, c: c.add(x, y), 0, a, b, rec)
add0_vecs = lambda a, b, rec=None: proc_vecs(lambda x, y, c: c.add0(x, y), 0, a, b, rec)
sub_vecs = lambda a, b, rec=None: proc_vecs(lambda x, y, c: c.sub(x, y), 0, a, b, rec)
# multiply two vectors, assuming 0 for left out values
mul_vecs = lambda a, b, rec=None: proc_vecs(lambda x, y, c: c.mul(x, y), 0, a, b, rec)

def mul_coeffs(a, b):
    c = [0] * (len(b) + len(a) - 1)
    for (i, ai) in enumerate(a):
        c = add_vecs(c, [ ai * x for x in [0] * i + b ])
    return c

def generate_newton_coeffs(deg):
    out = [[1]]

    for i in range(0, deg):
        out.append(mul_coeffs([-1 * i, 1], out[i]))

    return out

def invert_modp(val):
    s  = t_ = 0
    s_ = t  = 1
    r  = val
    r_ = Defs.prime

    while r != 0:
        q = r_ // r
        (r_, r) = (r, r_ - q * r)
        (s_, s) = (s, s_ - q * s)
        (t_, t) = (t, t_ - q * t)

    return t_ % Defs.prime

def divided_diffs(yvals, rec=None):
    # ASSUMPTION: y0 = f(0), y1 = f(1), y2 = f(2), ...
    # to start, generate incremental differences
    diffs = yvals

    if rec is None:
        rec = FArith().new_cat("q")

    out = [diffs[0]]
    for i in range(0, len(diffs) - 1):
        # this inversion can be stored statically, so we don't have to account its cost
        div = invert_modp(i + 1)
        assert len(diffs) > 1

        diffs = [ rec.mul(x, div) for x in sub_vecs(diffs[1:], diffs[:-1], rec) ]
        out.append(diffs[0])

    return out

def matrix_times_vector(mat, vec, rec=None):
    if rec is None:
        rec = FArith().new_cat("q")
    return reduce(lambda x, y: add0_vecs(x, y, rec), [ [ rec.mul0(x, z) for z in y ] for (x, y) in zip(vec, mat) ])

def newton_interpolate(yvals, rec=None):
    assert len(yvals) > 1
    if rec is None:
        rec = FArith().new_cat("q")

    ## step 1, generate divided differences
    diffs = divided_diffs(yvals, rec)

    ## step 2, generate coefficients
    # these can be stored statically, so no need to account their cost
    coeffs = generate_newton_coeffs(len(yvals) - 1)

    ## step 3, combine
    return matrix_times_vector(coeffs, diffs, rec)

def horner_eval(coeffs, val, rec=None):
    # coeffs are x0, x1, ... xn-1
    out = coeffs[-1]
    for elm in reversed(coeffs[:-1]):
        out *= val
        out += elm
        out %= Defs.prime

    if rec is not None:
        rec.did_mul(len(coeffs)-1)
        rec.did_add(len(coeffs)-1)

    return out

def generate_lagrange_coeffs(deg):
    # ASSUMPTION: y0 = f(0), y1 = f(1), y2 = f(2), ...
    outs = []
    for j in range(0, deg+1):
        divisor = 1
        out = [1]
        for m in range(0, deg+1):
            if m == j:
                continue
            divisor *= (j - m)
            divisor %= Defs.prime
            out = mul_coeffs([-1 * m, 1], out)
        div_inv = invert_modp(divisor)
        outs.append([ (x * div_inv) % Defs.prime for x in out ])

    return outs

def lagrange_interpolate(yvals, rec=None):
    assert len(yvals) > 1
    if rec is None:
        rec = FArith().new_cat("q")

    ## step 1: generate coefficients
    # these can be stored statically, so no need to account their cost
    coeffs = generate_lagrange_coeffs(len(yvals) - 1)

    ## step 2: dot products
    return matrix_times_vector(coeffs, yvals, rec)

# choose interpolation method
interpolate = lagrange_interpolate
