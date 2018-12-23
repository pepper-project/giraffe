#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#     this code is derived from libmu, https://github.com/excamera/mu/

class Defs(object):
    timeout = 300
    debug = False
    prime = 2 ** 61 - 1

    V_TYPE_LAY      = 0x0
    V_TYPE_IN       = 0x1
    V_TYPE_OUT      = 0x2
    P_TYPE_LAY      = 0x3
    P_TYPE_SHIM     = 0x4
    P_TYPE_CIRCUIT  = 0x5
    VP_TYPE_ID      = 0x6
    VP_TYPE_QUIT    = 0x7
    VP_TYPE_DEBUG   = 0x8

    V_SEND_NOKAY    = 0x10
    V_SEND_OKAY     = 0x11
    V_SEND_TAU      = 0x12
    V_SEND_EXPECT   = 0x13
    V_SEND_Z1       = 0x14
    V_SEND_Z2       = 0x15
    V_SEND_COUNTS   = 0x16

    V_RECV_INPUTS   = 0x20
    V_RECV_OUTPUTS  = 0x21
    V_RECV_COEFFS   = 0x22
    V_RECV_EXPECT   = 0x23
    V_RECV_Z1       = 0x24
    V_RECV_Z2       = 0x25
    V_RECV_MUXSEL   = 0x26

    P_SEND_LAYVALS  = 0x30
    P_SEND_Z1CHI    = 0x31
    P_SEND_Z2VALS   = 0x32
    P_SEND_COEFFS   = 0x33
    P_SEND_RESTART  = 0x34
    P_SEND_COUNTS   = 0x35

    P_RECV_LAYVALS  = 0x40
    P_RECV_Z1       = 0x41
    P_RECV_Z2       = 0x42
    P_RECV_Z1CHI    = 0x43
    P_RECV_Z2VALS   = 0x44
    P_RECV_TAU      = 0x45
    P_RECV_MUXSEL   = 0x46

    MSG_UINT32      = 0x70
    MSG_VECTOR      = 0x71
