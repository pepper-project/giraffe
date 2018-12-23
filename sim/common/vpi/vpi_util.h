#pragma once

#include <gmp.h>
#include <stdlib.h>
#include <string.h>

#include <vpi_user.h>
// for ncverilog only
#ifdef HAVE_VPI_USER_CDS_H
#include <vpi_user_cds.h>
#endif

#include "util.h"

void from_vector_val(mpz_t n, s_vpi_vecval *val, int nbits);
s_vpi_vecval *to_vector_val(mpz_t n);

vpiHandle* get_arg_iter(void);
int get_int_arg(vpiHandle* arg_iter);

