// definitions for V/P intf with coordinator
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __include_vpintf_defs

// entity types
`define V_TYPE_LAY      32'h0
`define V_TYPE_IN       32'h1
`define V_TYPE_OUT      32'h2
`define P_TYPE_LAY      32'h3
`define P_TYPE_SHIM     32'h4
`define P_TYPE_CIRCUIT  32'h5
`define VP_TYPE_ID      32'h6
`define VP_TYPE_QUIT    32'h7
`define VP_TYPE_DEBUG   32'h8

// send types, verifier
`define V_SEND_NOKAY    32'h10
`define V_SEND_OKAY     32'h11
`define V_SEND_TAU      32'h12
`define V_SEND_EXPECT   32'h13
`define V_SEND_Z1       32'h14
`define V_SEND_Z2       32'h15
`define V_SEND_COUNTS   32'h16

// receive types, verifier
`define V_RECV_INPUTS   32'h20
`define V_RECV_OUTPUTS  32'h21
`define V_RECV_COEFFS   32'h22
`define V_RECV_EXPECT   32'h23
`define V_RECV_Z1       32'h24
`define V_RECV_Z2       32'h25
`define V_RECV_MUXSEL   32'h26

// send types, prover
`define P_SEND_LAYVALS  32'h30
`define P_SEND_Z1CHI    32'h31
`define P_SEND_Z2VALS   32'h32
`define P_SEND_COEFFS   32'h33
`define P_SEND_RESTART  32'h34
`define P_SEND_COUNTS   32'h35

// recv types, prover
`define P_RECV_LAYVALS  32'h40
`define P_RECV_Z1       32'h41
`define P_RECV_Z2       32'h42
`define P_RECV_Z1CHI    32'h43
`define P_RECV_Z2VALS   32'h44
`define P_RECV_TAU      32'h45
`define P_RECV_MUXSEL   32'h46

// serialization tags
`define MSG_UINT32      32'h70
`define MSG_VECTOR      32'h71

`define __include_vpintf_defs
`endif // __include_vpintf_defs
