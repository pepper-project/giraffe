#pragma once

// uncomment the below to use p = 2^255 - 19
// NOTE you must also `define USE_P25519 in simulator.v
//#define USE_P25519
#undef USE_P25519

#ifndef USE_P25519

// 2^61 - 1
#define PRIMEBITS 61
#define PRIMEDELTA 1
#define PRIMEC32 2

#else

#define PRIMEBITS 255
#define PRIMEDELTA 19
#define PRIMEC32 8

#endif
/*
 * NOTE
 * If you change the above, you should also modify
 * bit widths of registers set by $f_add and $f_mul,
 * and you need to update the arith.sft file to
 * reflect the width of the outputs.
 */

// the debug macro causes P and V both to dump copious messages about their communication
//#define DEBUG
