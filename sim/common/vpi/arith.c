// arith.c
// VPI module for field arithmetic
// defines two system functions: $f_add and $f_mul
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

#include "arith.h"

//
// Register $f_mul and $f_add with the Verilog simulator.
//
void arith_register(void) {

    /* ** NOTE for Icarus Verilog **
     *
     * When compiling system functions, Icarus ignores the
     * sizetf field of s_vpi_systf_data. Instead, you must
     * create an .sft file and provide it alongside the .v
     * file when compiling the latter into a .vvp file.
     *
     * For example, the .sft file corresponding to $f_add
     * and $f_mul looks like this:

       $f_add vpiSysFuncSized 61 unsigned
       $f_mul vpiSysFuncSized 61 unsigned

     * and you should invoke iverilog like so:

       iverilog -oarith.vvp arith.v arith.sft

     */

    s_vpi_systf_data add_data =
        { .type = vpiSysFunc
        , .sysfunctype = vpiSizedFunc
        , .tfname = "$f_add"
        , .calltf = add_call
        , .compiletf = add_comp
        , .sizetf = addmul_size
        , .user_data = NULL
        };
    vpi_register_systf(&add_data);

    s_vpi_systf_data mul_data =
        { .type = vpiSysFunc
        , .sysfunctype = vpiSizedFunc
        , .tfname = "$f_mul"
        , .calltf = mul_call
        , .compiletf = mul_comp
        , .sizetf = addmul_size
        , .user_data = NULL
        };
    vpi_register_systf(&mul_data);

    s_vpi_systf_data sub_data =
        { .type = vpiSysFunc
        , .sysfunctype = vpiSizedFunc
        , .tfname = "$f_sub"
        , .calltf = sub_call
        , .compiletf = add_comp // a subtract is just an add in disguise
        , .sizetf = addmul_size
        , .user_data = NULL
        };
    vpi_register_systf(&sub_data);

    s_vpi_systf_data halve_data =
        { .type = vpiSysFunc
        , .sysfunctype = vpiSizedFunc
        , .tfname = "$f_halve"
        , .calltf = halve_call
        , .compiletf = add_comp // halve is a non-black-box use of an adder
        , .sizetf = addmul_size
        , .user_data = NULL
        };
    vpi_register_systf(&halve_data);

    s_vpi_systf_data rand_data =
        { .type = vpiSysFunc
        , .sysfunctype = vpiSizedFunc
        , .tfname = "$f_rand"
        , .calltf = rand_call
        , .compiletf = rand_comp
        , .sizetf = addmul_size
        , .user_data = NULL
        };
    vpi_register_systf(&rand_data);

    s_vpi_systf_data getcnt_data =
        { .type = vpiSysTask
        , .sysfunctype = 0
        , .tfname = "$f_getcnt"
        , .calltf = getcnt_call
        , .compiletf = getcnt_comp
        , .sizetf = NULL
        , .user_data = NULL
        };
    vpi_register_systf(&getcnt_data);

    s_vpi_systf_data rstcnt_data =
        { .type = vpiSysTask
        , .sysfunctype = 0
        , .tfname = "$f_rstcnt"
        , .calltf = rstcnt_call
        , .compiletf = rand_comp
        , .sizetf = NULL
        , .user_data = NULL
        };
    vpi_register_systf(&rstcnt_data);

    s_cb_data cb_data_start =
        { .reason = cbStartOfSimulation
        , .cb_rtn = arith_simstart
        , .obj = NULL
        , .time = NULL
        , .value = NULL
        , .user_data = NULL
        };
    vpi_register_cb(&cb_data_start);

    s_cb_data cb_data_end =
        { .reason = cbEndOfSimulation
        , .cb_rtn = arith_simend
        , .obj = NULL
        , .time = NULL
        , .value = NULL
        , .user_data = NULL
        };
    vpi_register_cb(&cb_data_end);

    // not strictly necessary since it's a static variable
    // Needs to be done here and not simstart because compiletfs
    // are called before simstart!
    memset(&inst_counts, 0, sizeof(inst_counts));
}

//
// At the start of the simulation, prepare global constants.
//
PLI_INT32 arith_simstart(s_cb_data *callback_data) {
    (void) callback_data;

    // initialize the modulus
    mpz_init_set_ui(p, 1);
    mpz_mul_2exp(p, p, PRIMEBITS);
    mpz_sub_ui(p, p, PRIMEDELTA);

    // initialize temporary GMP variables
    mpz_init2(t1, 2*(PRIMEBITS + 1));
    mpz_init2(t2, 2*(PRIMEBITS + 1));

    // initialize RNG
    // XXX this is *NOT* a csprng!
    gmp_randinit_default(rstate);

    // initialize logging for arithmetic operations
    init_logs();
    return 0;
}

//
// At the end of the simulation, report how many add and mul we used, and the timestamp of each
//
PLI_INT32 arith_simend(s_cb_data *callback_data) {
    (void) callback_data;
    vpi_printf("\n***\nArithmetic totals:\nadd %d\nmul %d\nrand %d\n(timestamps written to file)\n***\n", add_log.count, mul_log.count, rand_log.count);
    vpi_printf("***\nInstance counts:\nadd %d\nmul %d\n***\n\n", inst_counts.add, inst_counts.mul);

    FILE *logfile;
    char *fname;
    if ( (fname = getenv("ARITH_LOG_FILE")) != NULL ) {
        logfile = fopen(fname, "w");
    } else {
        //logfile = fopen("arith_log.txt", "w");
        logfile = NULL;
    }

    // dump out the logs
    log_dump(&add_log, logfile, "ADD");
    log_dump(&mul_log, logfile, "MUL");
    log_dump(&rand_log, logfile, "RAND");

    if (logfile != NULL) {
        fclose(logfile);
    }

    // deinit GMP stuff
    mpz_clear(p);
    mpz_clear(t1);
    mpz_clear(t2);
    gmp_randclear(rstate);

    return 0;
}

//
// This function is called once during elaboration to determine
// how many bits $f_add and $f_mul return.
//
static PLI_INT32 addmul_size(PLI_BYTE8 *user_data) {
    (void) user_data;

    return PRIMEBITS;
}

//
// This function is called once during elaboration for each
// instance of $f_add or $f_mul in a design. It checks that
// the arguments to that instance are well formed.
//
static PLI_INT32 mul_comp(PLI_BYTE8 *user_data) {
    inst_counts.mul++;
    return addmul_comp(user_data);
}
static PLI_INT32 add_comp(PLI_BYTE8 *user_data) {
    inst_counts.add++;
    return addmul_comp(user_data);
}
static PLI_INT32 addmul_comp(PLI_BYTE8 *user_data) {
    (void) user_data;

    vpiHandle systf_handle, arg_handle, arg_iter = NULL;
    PLI_INT32 arg_type;
    bool err = false;

    systf_handle = vpi_handle(vpiSysTfCall, NULL);
    arg_iter = vpi_iterate(vpiArgument, systf_handle);

    if (arg_iter == NULL) {
        vpi_printf("ERROR: $f_add/$f_mul takes exactly 2 arguments\n");
        err = true;
        goto ADDMUL_COMP_FINISH;
    }

    arg_handle = vpi_scan(arg_iter);
    arg_type = vpi_get(vpiType, arg_handle);
    // need a constant, an integer, a reg, or a net
    if ( (arg_type != vpiConstant) && (arg_type != vpiIntegerVar) && (arg_type != vpiReg) && (arg_type != vpiNet)  && (arg_type != vpiMemoryWord) ) {
        vpi_printf("ERROR: $f_add/$f_mul arguments must be number, variable, reg, or net\n");
        vpi_printf("arg_type: %d\n", arg_type);
        err = true;
        goto ADDMUL_COMP_FINISH;
    }

    arg_handle = vpi_scan(arg_iter);
    if (arg_handle == NULL) {
        arg_iter = NULL; // according to the standard, once vpi_scan returns NULL, the iterator is freed
        vpi_printf("ERROR: $f_add/$f_mul takes exactly 2 arguments\n");
        err = true;
        goto ADDMUL_COMP_FINISH;
    }

    arg_type = vpi_get(vpiType, arg_handle);
    if ( (arg_type != vpiConstant) && (arg_type != vpiIntegerVar) && (arg_type != vpiReg) && (arg_type != vpiNet   && (arg_type != vpiMemoryWord)) ) {
        vpi_printf("ERROR: $f_add/$f_mul arguments must be number, variable, reg, or net\n");
        err = true;
        goto ADDMUL_COMP_FINISH;
    }

    if (vpi_scan(arg_iter) != NULL) {
        vpi_printf("ERROR: $f_add/$f_mul takes exactly 2 arguments\n");
        err = true;
        goto ADDMUL_COMP_FINISH;
    } else {    // vpi_scan(arg_iter) returned NULL, so arg_iter was automatically freed
        arg_iter = NULL;
    }

ADDMUL_COMP_FINISH:
    // free the iterator unless it's already been freed
    if ( (arg_iter != NULL) && (vpi_scan(arg_iter) != NULL) ) {
        vpi_free_object(arg_iter);
    }

    if (err) {
        vpi_control(vpiFinish, 1);
    }

    return 0;
}

//
// compile $f_rand calls
//
static PLI_INT32 rand_comp(PLI_BYTE8 *user_data) {
    (void) user_data;

    // we ignore all arguments
    return 0;
}

//
// This function runs each time $f_add or $f_mul is called.
// It retrieves arguments and converts them to mpz_t.
//
static bool get_args(vpiHandle systf_handle, s_vpi_value *val) {
    vpiHandle arg_handle;
    vpiHandle arg_iter = vpi_iterate(vpiArgument, systf_handle);

    if (arg_iter == NULL) {
        vpi_printf("ERROR: $f_add/$f_mul failed to get arg handle\n");
        return true;
    }

    arg_handle = vpi_scan(arg_iter);
    vpi_get_value(arg_handle, val);
    from_vector_val(t1, val->value.vector, vpi_get(vpiSize, arg_handle));

    arg_handle = vpi_scan(arg_iter);
    vpi_get_value(arg_handle, val);
    from_vector_val(t2, val->value.vector, vpi_get(vpiSize, arg_handle));

    vpi_free_object(arg_iter);
    return false;
}

//
// $f_add function. Gets args, computes result, and returns result to simulator.
//
static PLI_INT32 add_call(PLI_BYTE8 *user_data) {
    (void) user_data;

    // increment the call counter
    log_arith_op(&add_log);

    // get arguments as hex strings
    s_vpi_value val = {0,};
    val.format = vpiVectorVal;
    vpiHandle systf_handle;

    systf_handle = vpi_handle(vpiSysTfCall, NULL);

    if (get_args(systf_handle, &val)) {
        // error getting args; abort
        vpi_control(vpiFinish, 1);
    } else {
        mpz_add(t2, t2, t1);
        mpz_mod(t2, t2, p);
        val.value.vector = to_vector_val(t2);
        vpi_put_value(systf_handle, &val, NULL, vpiNoDelay);
    }

    return 0;
}

//
// $f_sub function. Gets args, computes result, and returns result to simulator.
//
static PLI_INT32 sub_call(PLI_BYTE8 *user_data) {
    (void) user_data;

    // increment call counter --- counts as two adds
    log_arith_op(&add_log);
    log_arith_op(&add_log);

    // get arguments as hex strings
    s_vpi_value val = {0,};
    val.format = vpiVectorVal;
    vpiHandle systf_handle;

    systf_handle = vpi_handle(vpiSysTfCall, NULL);

    if (get_args(systf_handle, &val)) {
        // error getting args; abort
        vpi_control(vpiFinish, 1);
    } else {
        mpz_sub(t2, t1, t2);
        mpz_mod(t2, t2, p);
        val.value.vector = to_vector_val(t2);
        vpi_put_value(systf_handle, &val, NULL, vpiNoDelay);
    }

    return 0;
}

//
// $f_halve function. Note that the second arg is ignored!!!
// We implement this here because it cannot be implemented from
// field add in a black box way, but it *can* be implemented
// from the adder that lives inside a field add.
//
static PLI_INT32 halve_call(PLI_BYTE8 *user_data) {
    (void) user_data;

    // increment the call counter
    log_arith_op(&add_log);    // halve can be done in a non-black-box way with an adder

    // get argument
    s_vpi_value val = {0,};
    val.format = vpiVectorVal;
    vpiHandle systf_handle;

    systf_handle = vpi_handle(vpiSysTfCall, NULL);

    if (get_args(systf_handle, &val)) {
        // error getting args; abort
        vpi_control(vpiFinish, 1);
    } else {
        if (mpz_odd_p(t1)) {
            mpz_add(t1, t1, p);
        }
        mpz_divexact_ui(t1, t1, 2);
        mpz_mod(t1, t1, p);
        val.value.vector = to_vector_val(t1);
        vpi_put_value(systf_handle, &val, NULL, vpiNoDelay);
    }

    return 0;
}

//
// $f_mul function. Gets args, computes result, and returns result to simulator.
//
static PLI_INT32 mul_call(PLI_BYTE8 *user_data) {
    (void) user_data;

    // increment the call counter
    log_arith_op(&mul_log);

    // get arguments as hex strings
    s_vpi_value val = {0,};
    val.format = vpiVectorVal;
    vpiHandle systf_handle;

    systf_handle = vpi_handle(vpiSysTfCall, NULL);

    if (get_args(systf_handle, &val)) {
        // error getting args; abort
        vpi_control(vpiFinish, 1);
    } else {
        mpz_mul(t2, t2, t1);
        mpz_mod(t2, t2, p);
        val.value.vector = to_vector_val(t2);
        vpi_put_value(systf_handle, &val, NULL, vpiNoDelay);
    }

    return 0;
}

//
// $f_rand function.
//
static PLI_INT32 rand_call(PLI_BYTE8 *user_data) {
    (void) user_data;

    // increment the call counter
    log_arith_op(&rand_log);

    // random value < p
    mpz_urandomm(t1, rstate, p);

    s_vpi_value val = {0,};
    val.format = vpiVectorVal;
    vpiHandle systf_handle = vpi_handle(vpiSysTfCall, NULL);

    val.value.vector = to_vector_val(t1);
    vpi_put_value(systf_handle, &val, NULL, vpiNoDelay);

    return 0;
}

//
// reset counts for field arith
//
static PLI_INT32 rstcnt_call(PLI_BYTE8 *user_data) {
    (void) user_data;

    log_dump(&add_log, NULL, "");
    log_dump(&mul_log, NULL, "");
    log_dump(&rand_log, NULL, "");
    init_logs();
    return 0;
}

//
// initialize logs
//
void init_logs(void) {
    memset(&add_log, 0, sizeof(add_log));
    memset(&mul_log, 0, sizeof(mul_log));
    memset(&rand_log, 0, sizeof(rand_log));
    log_realloc(&add_log, LOG_INIT_SIZE);
    log_realloc(&mul_log, LOG_INIT_SIZE);
    log_realloc(&rand_log, LOG_INIT_SIZE);
}

//
// log an arithmetic operation
//
static void log_arith_op(s_arith_log *arith_log) {
    // increment the counter
    arith_log->count++;
    if (arith_log->count >= arith_log->size) {
        log_realloc(arith_log, arith_log->size * 2);
    }

    // now store the timestamp
    s_vpi_time time_s = { .type = vpiSimTime, .high = 0, .low = 0, .real = 0 };
    vpi_get_time(NULL, &time_s);
    arith_log->log[arith_log->count - 1] = ((uint64_t) time_s.high << 32) | time_s.low;
}

//
// reallocate memory in arith log
//
static void log_realloc(s_arith_log *arith_log, unsigned size) {
    if ((arith_log->log = realloc(arith_log->log, size * sizeof(uint64_t))) == NULL) {
        vpi_printf("ERROR: cannot alloc memory for arith log\n");
        vpi_control(vpiFinish, 1);
    }
    arith_log->size = size;
}

static void log_dump(s_arith_log *arith_log, FILE *logfile, char *name) {
    if (arith_log->log != NULL) {
        if (logfile != NULL) {
            fprintf(logfile, "%s timestamps (%d): ", name, arith_log->count);
            for (unsigned i = 0; i < arith_log->count; i++) {
                fprintf(logfile, "%" PRIu64 ", ", arith_log->log[i]);
            }
            fprintf(logfile, "\n");
        }
        free(arith_log->log);
        arith_log->log = NULL;
    }
}

//
// check call site for getcnt
//
PLI_INT32 getcnt_comp(PLI_BYTE8 *user_data) {
    (void) user_data;

    vpiHandle systf_handle, arg_handle, arg_iter;
    PLI_INT32 arg_type;
    bool err = false;

    systf_handle = vpi_handle(vpiSysTfCall, NULL);
    arg_iter = vpi_iterate(vpiArgument, systf_handle);

    if (arg_iter == NULL) {
        vpi_printf("ERROR: $f_getcnt takes exactly 1 argument\n");
        err = true;
        goto INIT_COMP_FINISH;
    }

    //scan for first argument
    arg_handle = vpi_scan(arg_iter);
    arg_type = vpi_get(vpiType, arg_handle);
    if ( (arg_type != vpiMemory) && (arg_type != vpiRegArray) ) {
        vpi_printf("ERROR: Arg to $f_getcnt must be memory or register array.\n");
        err = true;
        goto INIT_COMP_FINISH;
    }

    if (vpi_scan(arg_iter) != NULL) {
        vpi_printf("ERROR: $f_getcnt takes exactly 1 argument");
        err = true;
    } else {    // vpi_scan(arg_iter) returned NULL, so arg_iter was automatically freed
        arg_iter = NULL;
    }

INIT_COMP_FINISH:
    // free the iterator unless it's already been freed
    if ( (arg_iter != NULL) && (vpi_scan(arg_iter) != NULL) ) {
        vpi_free_object(arg_iter);
    }

    if (err) {
        vpi_control(vpiFinish, 1);
        return 1;
    }

    return 0;
}

//
// getcnt
//
PLI_INT32 getcnt_call(PLI_BYTE8 *user_data) {
    (void) user_data;

    vpiHandle systf_handle, arg_handle, arg_iter, elem_handle;
    systf_handle = vpi_handle(vpiSysTfCall, NULL);
    arg_iter = vpi_iterate(vpiArgument, systf_handle);
    arg_handle = vpi_scan(arg_iter);

    s_vpi_vecval outvec[2];
    memset(outvec, 0, 2 * sizeof(outvec[0]));
    s_vpi_value vec_val = {0,};
    vec_val.format = vpiVectorVal;
    vec_val.value.vector = outvec;

    outvec[0].aval = (PLI_INT32) add_log.count;
    elem_handle = vpi_handle_by_index(arg_handle, 0);
    vpi_put_value(elem_handle, &vec_val, NULL, vpiNoDelay);

    outvec[0].aval = (PLI_INT32) mul_log.count;
    elem_handle = vpi_handle_by_index(arg_handle, 1);
    vpi_put_value(elem_handle, &vec_val, NULL, vpiNoDelay);

    outvec[0].aval = (PLI_INT32) rand_log.count;
    elem_handle = vpi_handle_by_index(arg_handle, 2);
    vpi_put_value(elem_handle, &vec_val, NULL, vpiNoDelay);

    outvec[0].aval = (PLI_INT32) inst_counts.add;
    elem_handle = vpi_handle_by_index(arg_handle, 3);
    vpi_put_value(elem_handle, &vec_val, NULL, vpiNoDelay);

    outvec[0].aval = (PLI_INT32) inst_counts.mul;
    elem_handle = vpi_handle_by_index(arg_handle, 4);
    vpi_put_value(elem_handle, &vec_val, NULL, vpiNoDelay);

    s_vpi_time time_s = { .type = vpiSimTime, .high = 0, .low = 0, .real = 0 };
    vpi_get_time(NULL, &time_s);
    outvec[0].aval = time_s.low;
    outvec[1].aval = time_s.high;
    elem_handle = vpi_handle_by_index(arg_handle, 5);
    vpi_put_value(elem_handle, &vec_val, NULL, vpiNoDelay);

    return 0;
}
