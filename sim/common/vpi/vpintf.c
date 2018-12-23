// v/p intf to coordinator

#include "vpintf.h"

void vpintf_register (void) {
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

    s_vpi_systf_data vpintf_init_data =
        { .type = vpiSysFunc
        , .sysfunctype = vpiIntFunc
        , .tfname = "$vpintf_init"
        , .calltf = vpintf_init_call
        , .compiletf = vpintf_init_compile
        , .sizetf = vpintf_init_size
        , .user_data = NULL
        };
    vpi_register_systf(&vpintf_init_data);

    s_vpi_systf_data vpintf_recv_data =
        { .type = vpiSysTask
        , .sysfunctype = 0
        , .tfname = "$vpintf_recv"
        , .calltf = vpintf_recv_call
        , .compiletf = vpintf_send_compile
        , .sizetf = NULL
        , .user_data = NULL
        };
    vpi_register_systf(&vpintf_recv_data);

    s_vpi_systf_data vpintf_send_data =
        { .type = vpiSysTask
        , .sysfunctype = 0 //not a sysfunc.
        , .tfname = "$vpintf_send"
        , .calltf = vpintf_send_call
        , .compiletf = vpintf_send_compile
        , .sizetf = NULL
        , .user_data = NULL
        };
    vpi_register_systf(&vpintf_send_data);

    s_cb_data cb_data_start =
        { .reason = cbStartOfSimulation
        , .cb_rtn = vpintf_simstart
        , .obj = NULL
        , .time = NULL
        , .value = NULL
        , .user_data = NULL
        };
    vpi_register_cb(&cb_data_start);

    s_cb_data cb_data_end =
        { .reason = cbEndOfSimulation
        , .cb_rtn = vpintf_simend
        , .obj = NULL
        , .time = NULL
        , .value = NULL
        , .user_data = NULL
        };
    vpi_register_cb(&cb_data_end);
}

//
// start sim: initialize mpzs, connect to server
//
PLI_INT32 vpintf_simstart(s_cb_data *callback_data) {
    (void) callback_data;

    int sock = -1;
    mpz_init(t1);
    mpz_init(t2);

    struct addrinfo hint = {0,}, *res = NULL;
    hint.ai_family = AF_INET;
    hint.ai_socktype = SOCK_STREAM;

    char *hostname = getenv("VPINTF_HOST");
    char *portnum = getenv("VPINTF_PORT");

    if (getaddrinfo(hostname == NULL ? "localhost" : hostname, portnum == NULL ? "27352" : portnum, &hint, &res) != 0) {
        vpi_printf("ERROR: getaddrinfo failed\n");
        vpi_control(vpiFinish, 1);
    }
    if ((sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol)) < 0) {
        vpi_printf("ERROR: socket failed\n");
        vpi_control(vpiFinish, 1);
    }
    if (connect(sock, res->ai_addr, res->ai_addrlen) < 0) {
        vpi_printf("ERROR: connect failed\n");
        vpi_control(vpiFinish, 1);
    }
    int soval = 1;
    if (setsockopt(sock, SOL_TCP, TCP_NODELAY, &soval, sizeof(soval)) != 0) {
        vpi_printf("ERROR: couldn't setsockopt\n");
        vpi_control(vpiFinish, 1);
    }
    server_sock = sock;
    freeaddrinfo(res);

    return 0;
}

//
// clean up when we're done: free mem and close the socket
//
PLI_INT32 vpintf_simend(s_cb_data *callback_data) {
    (void) callback_data;

    mpz_clear(t1);
    mpz_clear(t2);
    shutdown(server_sock, SHUT_RDWR);

    return 0;
}

//
// init returns a 32-bit integer
//
PLI_INT32 vpintf_init_size(PLI_BYTE8 *user_data) {
    (void) user_data;
    return 32;
}

//
// initialize connection to server
//
PLI_INT32 vpintf_init_call(PLI_BYTE8 *user_data) {
    (void) user_data;

    vpiHandle *arg_iter = get_arg_iter();
    int type = get_int_arg(arg_iter);
    int extra = get_int_arg(arg_iter);
    free(arg_iter);

    if ((type < V_TYPE_LAY) || (type > P_TYPE_CIRCUIT)) {
        vpi_printf("ERROR: bad type specified in $vpintf_init\n");
        vpi_control(vpiFinish, 1);
    }

    // construct and send our init message
    vpintf_message message = {0,};
    init_vpintf_message(&message);
    message.type = (uint8_t) type;
    vmpack_uint32(&message, extra);
    send_vpintf_message(&message);

    // receive server response
    recv_vpintf_message(&message);
    if (message.type != VP_TYPE_ID) {
        vpi_printf("ERROR: got type %d rather than VP_TYPE_ID in init message\n", message.type);
        vpi_control(vpiFinish, 1);
    }
    uint32_t id = vmunpack_uint32(&message);
    if (message.position != message.capacity) {
        vpi_printf("ERROR: received extraneous garbage in init message\n");
        vpi_control(vpiFinish, 1);
    }
    free_vpintf_message(&message);

    s_vpi_value retval = {0,};
    retval.format = vpiIntVal;
    vpiHandle systf_handle = vpi_handle(vpiSysTfCall, NULL);
    retval.value.integer = (int) id;
    vpi_put_value(systf_handle, &retval, NULL, vpiNoDelay);

    return 0;
}

//
// send values to server
//
PLI_INT32 vpintf_send_call(PLI_BYTE8 *user_data) {
    (void) user_data;

    vpiHandle *arg_iter = get_arg_iter();
    unsigned type = (unsigned) get_int_arg(arg_iter);
    unsigned length = (unsigned) get_int_arg(arg_iter);

    if ((type != VP_TYPE_DEBUG) && ((type < V_SEND_NOKAY) || (type > V_SEND_COUNTS)) && ((type < P_SEND_LAYVALS) || (type > P_SEND_COUNTS))) {
        vpi_printf("ERROR: invalid send type in $vpintf_send\n");
        vpi_control(vpiFinish, 1);
    }

    vpiHandle array_handle = vpi_scan(*arg_iter);
    free(arg_iter);

    vpintf_message message = {0,};
    init_vpintf_message(&message);
    message.type = (uint8_t) type;
    vmpack_uint32(&message, length);

    if (length > 0) {
        s_vpi_value arg_val = {0,};
        arg_val.format = vpiVectorVal;
        int arg_type = vpi_get(vpiType, array_handle);
        if ((arg_type == vpiNet) || (arg_type == vpiReg) || (arg_type == vpiMemoryWord)) {
            if (length != 1) {
                vpi_printf("ERROR: got length arg != 1 with non-array reg or wire in $vpintf_send.\n");
                vpi_control(vpiFinish, 1);
            } else {
                vpi_get_value(array_handle, &arg_val);
                vmpack_vector(&message, arg_val.value.vector, (uint32_t) vpi_get(vpiSize, array_handle));
            }
        } else {
            // otherwise it's a vpiRegArray, vpiNetArray, or vpiMemory
            for (unsigned i = 0; i < length; i++) {
                vpiHandle element_handle = vpi_handle_by_index(array_handle, i);
                vpi_get_value(element_handle, &arg_val);
                vmpack_vector(&message, arg_val.value.vector, (uint32_t) vpi_get(vpiSize, element_handle));
            }
        }
    }

    send_vpintf_message(&message);

    return 0;
}

//
// recv values from server
//
PLI_INT32 vpintf_recv_call(PLI_BYTE8 *user_data) {
    (void) user_data;

    vpiHandle *arg_iter = get_arg_iter();
    unsigned expect_type = (unsigned) get_int_arg(arg_iter);

    // keep a handle on length because we're going to overwrite it
    vpiHandle length_handle = vpi_scan(*arg_iter);
    s_vpi_value length_val = {0,};
    length_val.format = vpiIntVal;
    vpi_get_value(length_handle, &length_val);
    unsigned max_length = (unsigned) length_val.value.integer;

    vpiHandle array_handle = vpi_scan(*arg_iter);
    free(arg_iter);

    vpintf_message message = {0,};
    recv_vpintf_message(&message);

    if (message.type == VP_TYPE_QUIT) {
        vpi_control(vpiFinish, 0);
        return 0;
    } else if (expect_type != message.type) {
        vpi_printf("ERROR: received unexpected message type %d (wanted %d)\n", message.type, expect_type);
        vpi_control(vpiFinish, 1);
    }

    uint32_t actual_length = vmunpack_uint32(&message);
    if ((actual_length > max_length) || (actual_length == 0)) {
        vpi_printf("ERROR: got %d values (must be >0). Max length is %d\n", actual_length, max_length);
        vpi_control(vpiFinish, 1);
    }
    length_val.value.integer = actual_length;

    int arg_type = vpi_get(vpiType, length_handle);
    if (arg_type != vpiIntegerVar) {
        if (actual_length != max_length) {
            vpi_printf("WARNING: got %d values, expecting %d; can't inform call site.\n", actual_length, max_length);
        }
    } else {
        vpi_put_value(length_handle, &length_val, NULL, vpiNoDelay);
    }

    s_vpi_value vec_val = {0,};
    vec_val.format = vpiVectorVal;
    arg_type = vpi_get(vpiType, array_handle);
    if ((arg_type == vpiReg) || (arg_type == vpiMemoryWord)) {
        if (actual_length != 1) {
            vpi_printf("ERROR: got length != 1 with non-array reg or wire in $vpintf_recv.\n");
            vpi_control(vpiFinish, 1);
        } else {
            vec_val.value.vector = vmunpack_vector(&message);
            vpi_put_value(array_handle, &vec_val, NULL, vpiNoDelay);
        }
    } else {
        // otherwise it's an array
        for (unsigned i = 0; i < actual_length; i++) {
            vpiHandle element_handle = vpi_handle_by_index(array_handle, i);
            vec_val.value.vector = vmunpack_vector(&message);
            vpi_put_value(element_handle, &vec_val, NULL, vpiNoDelay);
        }
    }

    return 0;
}

//
// pack a uint32_t into message
//
void vmpack_uint32(vpintf_message *msg, uint32_t val) {
    while ((msg->position + 5) > msg->capacity) {
        realloc_vpintf_message(msg, 2 * msg->capacity);
    }
    size_t pos = msg->position;
    msg->message[pos++] = MSG_UINT32;
    pack_raw32(msg->message + pos, val);
    msg->position = pos + 4;
}

//
// pack a vpiVector into message
//
void vmpack_vector(vpintf_message *msg, s_vpi_vecval *val, uint32_t nbits) {
    uint32_t nvects = (nbits / 32) + (nbits % 32 != 0);
    if (nvects > VPVEC_MAXLEN) {
        vpi_printf("ERROR: attempting to pack a vector with more than VPVEC_MAXLEN limbs\n");
        vpi_control(vpiFinish, 1);
    }

    size_t ntotal = 8 * nvects + 2;
    while ((msg->position + ntotal) > msg->capacity) {
        realloc_vpintf_message(msg, 2 * msg->capacity);
    }

    size_t pos = msg->position;
    msg->message[pos++] = MSG_VECTOR;
    msg->message[pos++] = (uint8_t) nvects;
    for (unsigned i = 0; i < nvects; i++) {
        pack_raw32(msg->message + pos, (uint32_t) val[i].aval);
        pack_raw32(msg->message + pos + 4, (uint32_t) val[i].bval);
        pos += 8;
    }
    msg->position = pos;
}

//
// unpack a vpiVector from a message
//
s_vpi_vecval *vmunpack_vector(vpintf_message *msg) {
    static s_vpi_vecval retval[VPVEC_MAXLEN];
    memset(retval, 0, VPVEC_MAXLEN * sizeof(retval[0]));

    if ((msg->position + 2) > msg->capacity) {
        vpi_printf("ERROR: not enough bytes to extract vector header from message\n");
        vpi_control(vpiFinish, 1);
    }

    size_t pos = msg->position;
    uint8_t valtype = msg->message[pos++];
    uint8_t veclen = msg->message[pos++];
    if ((valtype != MSG_VECTOR) || (veclen > VPVEC_MAXLEN)) {
        vpi_printf("ERROR: expected MSG_VECTOR no longer than VPVEC_MAXLEN\n");
        vpi_control(vpiFinish, 1);
    }

    if ((pos + 8 * veclen) > msg->capacity) {
        vpi_printf("ERROR: not enough bytes to extract promised vector length\n");
        vpi_control(vpiFinish, 1);
    }
    for (unsigned i = 0; i < veclen; i++) {
        retval[i].aval = unpack_raw32(msg->message + pos);
        retval[i].bval = unpack_raw32(msg->message + pos + 4);
        pos += 8;
    }
    msg->position = pos;

    return retval;
}

//
// deserialize a uint32 from a message
//
uint32_t vmunpack_uint32(vpintf_message *msg) {
    if ((msg->position + 5) > msg->capacity) {
        vpi_printf("ERROR: not enough bytes to extract uint32 from message\n");
        vpi_control(vpiFinish, 1);
    }
    size_t pos = msg->position;
    uint8_t valtype = msg->message[pos++];
    if (valtype != MSG_UINT32) {
        vpi_printf("ERROR: expected MSG_UINT32 byte, got something else\n");
        vpi_control(vpiFinish, 1);
    }
    uint32_t ret = unpack_raw32(msg->message + pos);
    msg->position = pos + 4;
    return ret;
}

//
// write 32 bits into buf (NOTE: no bounds checking!)
//
void pack_raw32(uint8_t *buf, uint32_t val) {
    for (unsigned i = 0; i < 4; i++) {
        buf[i] = (uint8_t) (val & 0x000000ff);
        val = val >> 8;
    }
}

//
// unpack 32 bits from buf into a uint32_t
//
uint32_t unpack_raw32(uint8_t *buf) {
    uint32_t ret = 0;
    for (unsigned i = 0; i < 4; i++) {
        uint32_t tmp = ((uint8_t) buf[i]) << (8 * i);
        ret = ret | tmp;
    }

    return ret;
}

//
// initialize a message to send
//
void init_vpintf_message(vpintf_message *msg) {
    realloc_vpintf_message(msg, VPMSG_INITSIZE);
    msg->position = 5;
}

//
// finalize a message to send
//
void fin_vpintf_message(vpintf_message *msg) {
    pack_raw32(msg->message, (uint32_t) msg->position - 4);
    msg->message[4] = msg->type;
}

//
// free a message
//
void free_vpintf_message(vpintf_message *msg) {
    if (msg->message != NULL) {
        free(msg->message);
        msg->message = NULL;
        msg->capacity = 0;
        msg->position = 0;
        msg->type = 0;
    }
}

//
// allocate message buffer
//
void realloc_vpintf_message(vpintf_message *msg, size_t size) {
    if ((msg->message = (uint8_t *)realloc(msg->message, size)) == NULL) {
        vpi_printf("ERROR: could not alloc message\n");
        vpi_control(vpiFinish, 1);
    }
    msg->capacity = size;
}

//
// send a message
//
void send_vpintf_message(vpintf_message *msg) {
    fin_vpintf_message(msg);

    size_t size = msg->position;
    size_t posn = 0;
    ssize_t send_len;
    while ((send_len = send(server_sock, msg->message + posn, size, 0))) {
        if (send_len == 0) {
            break;
        } else if (send_len < 0) {
            vpi_printf("ERROR: sending message: %s\n", strerror(errno));
            vpi_control(vpiFinish, 1);
            return;
        } else {
            posn += send_len;
            size -= send_len;
            if (size == 0) { break; }
        }
    }

    if ((send_len == 0) && (size != 0)) {
        vpi_printf("ERROR: zero length send (client disconnected?)\n");
        vpi_control(vpiFinish, 1);
    }
}

//
// recv a message
//
void recv_vpintf_message(vpintf_message *msg) {
    uint8_t buf[5];
    if (recv(server_sock, buf, 5, 0) != 5) {
        vpi_printf("ERROR: recv'ing message header\n");
        vpi_control(vpiFinish, 1);
    }

    size_t size = unpack_raw32(buf);
    realloc_vpintf_message(msg, 4 + size);
    size -= 1;
    memcpy(msg->message, buf, 5);
    msg->type = (uint8_t) buf[4];
    msg->position = 5;
    size_t posn = 5;

    ssize_t recv_len;
    while ((recv_len = recv(server_sock, msg->message + posn, size, 0))) {
        if (recv_len == 0) {
            break;
        } else if (recv_len < 0) {
            vpi_printf("ERROR: recv'ing message: %s\n", strerror(errno));
            vpi_control(vpiFinish, 1);
            return;
        } else {
            posn += recv_len;
            size -= recv_len;
            if (size == 0) { break; }
        }
    }

    if ((recv_len == 0) && (size != 0)) {
        vpi_printf("ERROR: zero length read (client disconnected?)\n");
        vpi_control(vpiFinish, 1);
    }

    msg->position = 5;
}

//
// check args to init
//
PLI_INT32 vpintf_init_compile(PLI_BYTE8 * user_data) {
    (void) user_data;

    vpiHandle systf_handle, arg_handle, arg_iter = NULL;
    PLI_INT32 arg_type;
    bool err = false;

    systf_handle = vpi_handle(vpiSysTfCall, NULL);
    arg_iter = vpi_iterate(vpiArgument, systf_handle);

    if (arg_iter == NULL) {
        vpi_printf("ERROR: $vpintf_init takes exactly 2 arguments\n");
        err = true;
        goto INIT_COMP_FINISH;
    }

    //scan for first argument
    arg_handle = vpi_scan(arg_iter);
    arg_type = vpi_get(vpiType, arg_handle);
    if ( (arg_type != vpiConstant) && (arg_type != vpiIntegerVar) && (arg_type != vpiParameter) ) {
        vpi_printf("ERROR: First arg to $vpintf_init is entity type.\n");
        err = true;
        goto INIT_COMP_FINISH;
    }

    //scan for second arguement
    arg_handle = vpi_scan(arg_iter);
    if (arg_handle == NULL) {
        arg_iter = NULL; // according to the standard, once vpi_scan returns NULL, the iterator is freed
        vpi_printf("ERROR: $vpintf_init takes exactly 2 arguments\n");
        err = true;
        goto INIT_COMP_FINISH;
    }

    arg_type = vpi_get(vpiType, arg_handle);
    if ( (arg_type != vpiConstant) && (arg_type != vpiIntegerVar) && (arg_type != vpiParameter) ) {
        vpi_printf("ERROR: Second arg to $vpintf_init should specify extra info (e.g., layer number)\n");
        err = true;
        goto INIT_COMP_FINISH;
    }

    if (vpi_scan(arg_iter) != NULL) {
        vpi_printf("ERROR: $vpintf_init takes exactly 2 arguments");
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
    }

    return 0;
}

//
// check arguments for vpintf_send and vpintf_recv
//
PLI_INT32 vpintf_send_compile(PLI_BYTE8 * user_data) {
    (void) user_data;

    vpiHandle systf_handle, arg_handle, arg_iter = NULL;
    PLI_INT32 arg_type;
    bool err = false;

    systf_handle = vpi_handle(vpiSysTfCall, NULL);
    arg_iter = vpi_iterate(vpiArgument, systf_handle);

    if (arg_iter == NULL) {
        vpi_printf("ERROR: $vpintf_send/recv takes exactly 3 arguments\n");
        err = true;
        goto REQUEST_COMP_FINISH;
    }

    //scan for first argument
    arg_handle = vpi_scan(arg_iter);
    arg_type = vpi_get(vpiType, arg_handle);

    if ( (arg_type != vpiConstant) && (arg_type != vpiIntegerVar) && (arg_type != vpiReg) && (arg_type != vpiNet) ) {
        vpi_printf("ERROR: first arg to $vpintf_send/recv should be the request type.\n");
        err = true;
        goto REQUEST_COMP_FINISH;
    }

    //scan for second argument
    arg_handle = vpi_scan(arg_iter);
    if (arg_handle == NULL) {
        arg_iter = NULL; // according to the standard, once vpi_scan returns NULL, the iterator is freed
        vpi_printf("ERROR: $vpintf_send/recv takes exactly 3 arguments\n");
        err = true;
        goto REQUEST_COMP_FINISH;
    }

    arg_type = vpi_get(vpiType, arg_handle);
    if ( (arg_type != vpiConstant) && (arg_type != vpiIntegerVar) && (arg_type != vpiReg) && (arg_type != vpiNet) && (arg_type != vpiParameter) ) {
        vpi_printf("ERROR: second arg to $vpintf_send/recv should be the request length (%d)\n", arg_type);
        err = true;
        goto REQUEST_COMP_FINISH;
    }

    //scan for third argument
    arg_handle = vpi_scan(arg_iter);
    if (arg_handle == NULL) {
        arg_iter = NULL; // according to the standard, once vpi_scan returns NULL, the iterator is freed
        vpi_printf("ERROR: $vpintf_send/recv takes exactly 3 arguments\n");
        err = true;
        goto REQUEST_COMP_FINISH;
    }

    arg_type = vpi_get(vpiType, arg_handle);
    if ( (arg_type != vpiReg) && (arg_type != vpiMemory) && (arg_type != vpiMemoryWord) && (arg_type != vpiRegArray) && (arg_type != vpiNetArray) && (arg_type != vpiNet) ) {
        vpi_printf("ERROR: third arg to $vpintf_send/recv should be a vector of values to send (%d)\n", arg_type);
        err = true;
        goto REQUEST_COMP_FINISH;
    }

    if (vpi_scan(arg_iter) != NULL) {
        vpi_printf("ERROR: $vpintf_send/recv takes exactly 3 arguments");
        err = true;
    } else {    // vpi_scan(arg_iter) returned NULL, so arg_iter was automatically freed
        arg_iter = NULL;
    }

REQUEST_COMP_FINISH:
    // free the iterator unless it's already been freed
    if ( (arg_iter != NULL) && (vpi_scan(arg_iter) != NULL) ) {
        vpi_free_object(arg_iter);
    }

    if (err) {
        vpi_control(vpiFinish, 1);
    }

    return 0;
}
