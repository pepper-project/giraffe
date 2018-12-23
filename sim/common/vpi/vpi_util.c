#include "vpi_util.h"

//
// Low-level conversion of vpiVectorVal to mpz_t.
//
void from_vector_val(mpz_t n, s_vpi_vecval *val, int nbits) {
    // how many 32-bit ints does it take to store nbits?
    int nvects = (nbits / 32) + (nbits % 32 != 0);

    // pull in from the vpi_vecval
    mpz_import(n, nvects, -1, sizeof(val[0]), 0, 8*(sizeof(val[0]) - sizeof(val[0].bval)), val);
}

//
// Low-level conversion of mpz_t to vpiVectorVal.
//
s_vpi_vecval *to_vector_val(mpz_t n) {
    // one extra slot in case PRIMEC32 is odd and mp_bits_per_limb == 64
    static s_vpi_vecval retval[PRIMEC32 + 1];
    memset(retval, 0, (PRIMEC32 + 1) * sizeof(retval[0]));

    // push bits into vpi_vecval
    mpz_export(retval, NULL, -1, sizeof(retval[0]), 0, 8*(sizeof(retval[0]) - sizeof(retval[0].bval)), n);
    return retval;
}


vpiHandle* get_arg_iter() {
    vpiHandle systf_handle;
    systf_handle = vpi_handle(vpiSysTfCall, NULL);


    vpiHandle* arg_iter = malloc(sizeof(vpiHandle));
    *arg_iter = vpi_iterate(vpiArgument, systf_handle);

    if (arg_iter == NULL ) {
        vpi_printf("ERROR: $recieve failed to get arg handle\n");
    }

    return arg_iter;
}

int get_int_arg(vpiHandle* arg_iter) {

    s_vpi_value arg_val = {0,};
    vpiHandle arg_handle = NULL;

    arg_handle = vpi_scan(*arg_iter);
    arg_val.format = vpiIntVal;
    vpi_get_value(arg_handle, &arg_val);

    return arg_val.value.integer;

}
