// arith.h
// VPI module for field arithmetic (header)
// defines two system functions: $f_add and $f_mul
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

#include <gmp.h>

#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#include <vpi_user.h>
// for ncverilog only
#ifdef HAVE_VPI_USER_CDS_H
#include <vpi_user_cds.h>
#endif

#include "vpi_util.h"

static PLI_INT32 add_comp(PLI_BYTE8 *user_data);
static PLI_INT32 mul_comp(PLI_BYTE8 *user_data);
static PLI_INT32 addmul_comp(PLI_BYTE8 *user_data);
static PLI_INT32 addmul_size(PLI_BYTE8 *user_data);
static PLI_INT32 rand_comp(PLI_BYTE8 *user_data);

static bool get_args(vpiHandle systf_handle, s_vpi_value *val);
static PLI_INT32 add_call(PLI_BYTE8 *user_data);
static PLI_INT32 sub_call(PLI_BYTE8 *user_data);
static PLI_INT32 halve_call(PLI_BYTE8 *user_data);
static PLI_INT32 mul_call(PLI_BYTE8 *user_data);
static PLI_INT32 rand_call(PLI_BYTE8 *user_data);
static PLI_INT32 rstcnt_call(PLI_BYTE8 *user_data);

static PLI_INT32 getcnt_call(PLI_BYTE8 *user_data);
static PLI_INT32 getcnt_comp(PLI_BYTE8 *user_data);

// we can reuse the same mpz_t for everything
static mpz_t p, t1, t2;
static gmp_randstate_t rstate;

void arith_register(void);
void init_logs(void);
PLI_INT32 arith_simstart(s_cb_data *callback_data);
PLI_INT32 arith_simend(s_cb_data *callback_data);

// verilog simulator will call arith_register at initialization
void (*vlog_startup_routines[])(void) = { arith_register, 0, };

// arith logging struct
typedef struct {
    unsigned count;
    unsigned size;
    uint64_t *log;
} s_arith_log;

typedef struct {
    unsigned add;
    unsigned mul;
} s_arith_insts;

#define LOG_INIT_SIZE 1024
static s_arith_log add_log, mul_log, rand_log;
static s_arith_insts inst_counts;
static void log_arith_op(s_arith_log *arith_log);
static void log_realloc(s_arith_log *arith_log, unsigned size);
static void log_dump(s_arith_log *arith_log, FILE *logfile, char *name);
