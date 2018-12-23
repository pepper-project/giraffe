#pragma once

#include <errno.h>
#include <gmp.h>
#include <netdb.h>
#include <netinet/tcp.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>

#include "vpi_util.h"

#define SERVER_PORTNUM  27352

// entity types
#define V_TYPE_LAY      0x0
#define V_TYPE_IN       0x1
#define V_TYPE_OUT      0x2
#define P_TYPE_LAY      0x3
#define P_TYPE_SHIM     0x4
#define P_TYPE_CIRCUIT  0x5
#define VP_TYPE_ID      0x6
#define VP_TYPE_QUIT    0x7
#define VP_TYPE_DEBUG   0x8

// send types, verifier
#define V_SEND_NOKAY    0x10
#define V_SEND_OKAY     0x11
#define V_SEND_TAU      0x12
#define V_SEND_EXPECT   0x13
#define V_SEND_Z1       0x14
#define V_SEND_Z2       0x15
#define V_SEND_COUNTS   0x16

// receive types, verifier
#define V_RECV_INPUTS   0x20
#define V_RECV_OUTPUTS  0x21
#define V_RECV_COEFFS   0x22
#define V_RECV_EXPECT   0x23
#define V_RECV_Z1       0x24
#define V_RECV_Z2       0x25
#define V_RECV_MUXSEL   0x26

// send types, prover
#define P_SEND_LAYVALS  0x30
#define P_SEND_Z1CHI    0x31
#define P_SEND_Z2VALS   0x32
#define P_SEND_COEFFS   0x33
#define P_SEND_RESTART  0x34
#define P_SEND_COUNTS   0x35

// recv types, prover
#define P_RECV_LAYVALS  0x40
#define P_RECV_Z1       0x41
#define P_RECV_Z2       0x42
#define P_RECV_Z1CHI    0x43
#define P_RECV_Z2VALS   0x44
#define P_RECV_TAU      0x45
#define P_RECV_MUXSEL   0x46

// serialization tags
#define MSG_UINT32      0x70
#define MSG_VECTOR      0x71

static int server_sock = -1;

static PLI_INT32 vpintf_init_call(PLI_BYTE8 *user_data);
static PLI_INT32 vpintf_send_call(PLI_BYTE8 *user_data);
static PLI_INT32 vpintf_recv_call(PLI_BYTE8 *user_data);

PLI_INT32 vpintf_init_size(PLI_BYTE8 *user_data);

PLI_INT32 vpintf_init_compile(PLI_BYTE8 *user_data);
PLI_INT32 vpintf_send_compile(PLI_BYTE8 *user_data);

static mpz_t t1, t2;

PLI_INT32 vpintf_simstart(s_cb_data *callback_data);
PLI_INT32 vpintf_simend(s_cb_data *callback_data);

void vpintf_register (void);
void (*vlog_startup_routines[])(void) = { vpintf_register, 0, };

typedef struct {
    size_t capacity;
    size_t position;
    uint8_t type;
    uint8_t *message;
} vpintf_message;

#define VPMSG_INITSIZE 4096
#define VPVEC_MAXLEN 64
// at most 64, 32-bit limbs per packed vector value

void init_vpintf_message(vpintf_message *msg);
void realloc_vpintf_message(vpintf_message *msg, size_t size);
void free_vpintf_message(vpintf_message *msg);
void fin_vpintf_message(vpintf_message *msg);

void pack_raw32(uint8_t *buf, uint32_t val);
uint32_t unpack_raw32(uint8_t *buf);

void send_vpintf_message(vpintf_message *msg);
void recv_vpintf_message(vpintf_message *msg);

void vmpack_uint32(vpintf_message *msg, uint32_t val);
void vmpack_vector(vpintf_message *msg, s_vpi_vecval *val, uint32_t nbits);

uint32_t vmunpack_uint32(vpintf_message *msg);
s_vpi_vecval *vmunpack_vector(vpintf_message *msg);
