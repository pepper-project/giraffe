#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#     client objects for different vpintf client types

import collections
import struct

import giraffelib.circuitprover as cprv
import giraffelib.arithcircuitbuilder as abld
from giraffelib.layercompute import LayerComputeBeta
import giraffelib.util as gutil

from vpintf.defs import Defs
import vpintf.socket_nb
import vpintf.util as util

class VPIntfClient(vpintf.socket_nb.SocketNB):
    client_type = None
    client_extra = None
    client_id = 0

    @staticmethod
    def vpmsg_vector(vals, mtype=0):
        retval = chr(mtype) + chr(Defs.MSG_UINT32) + struct.pack("<L", len(vals))

        nvecs_tot = 0
        for val in vals:
            nbits = util.clog2(val + 1)
            n_vecs = nbits // 32
            if (nbits % 32) != 0:
                n_vecs += 1

            nvecs_tot += n_vecs
            retval += chr(Defs.MSG_VECTOR) + chr(n_vecs)
            for _ in range(0, n_vecs):
                assert val != 0
                thisval = 0xffffffff & val
                val = val >> 32
                retval += struct.pack("<L", thisval)
                retval += '\x00\x00\x00\x00'

            assert val == 0

        assert len(retval) == 6 + 2 * len(vals) + 8 * nvecs_tot
        return retval

    @staticmethod
    def vpmsg_bitvector(bitvals, mtype=0):
        n_vecs = len(bitvals) // 32
        if (len(bitvals) % 32) != 0:
            n_vecs += 1

        retval = chr(mtype) + chr(Defs.MSG_UINT32) + struct.pack("<L", 1) + chr(Defs.MSG_VECTOR) + chr(n_vecs)
        for _ in range(0, n_vecs):
            assert bitvals != []
            thisvec = bitvals[0:32]
            bitvals = bitvals[32:]

            retval += struct.pack("<L", sum([  b * (2 ** p) for (p, b) in enumerate(thisvec) ]))
            retval += '\x00\x00\x00\x00'

        assert bitvals == []
        assert len(retval) == 8 * n_vecs + 8
        return retval

    @staticmethod
    def vmunpack_vector(msg):
        if ord(msg[0]) != Defs.MSG_VECTOR:
            raise ValueError("Wrong value tag type decoding vector")

        retval = 0
        length = ord(msg[1])
        msg = msg[2:]
        for i in range(0, length):
            val = struct.unpack("<L", msg[:4])[0]
            retval += val * 2 ** (32 * i)
            msg = msg[8:]

        return (retval, msg)

    @staticmethod
    def vmunpack_uint32(msg):
        if ord(msg[0]) != Defs.MSG_UINT32:
            raise ValueError("Wrong value tag type decoding uint32")

        val = struct.unpack("<L", msg[1:5])[0]
        msg = msg[5:]

        return (val, msg)

    @staticmethod
    def vpmsg_unpack(msg):
        msgtype = ord(msg[0])
        (length, msg) = VPIntfClient.vmunpack_uint32(msg[1:])

        vals = []
        for _ in range(0, length):
            (val, msg) = VPIntfClient.vmunpack_vector(msg)
            vals.append(val)

        return (msgtype, vals)

    def do_handle(self):
        raise NotImplementedError("do_handle for VPIntfClient base class called")

    def post_initialize(self):
        pass

    def initialize(self):
        if not self.want_handle:
            return None

        msg = self.dequeue()
        self.client_type = ord(msg[0])

        if self.client_type < Defs.V_TYPE_LAY or self.client_type > Defs.P_TYPE_CIRCUIT:
            raise ValueError("Invalid client type initializing client")

        (self.client_extra, msg) = self.vmunpack_uint32(msg[1:])

        if msg != "":
            raise ValueError("Extraneous data in client hello message")

        out_msg = chr(Defs.VP_TYPE_ID) + chr(Defs.MSG_UINT32) + struct.pack("<L", self.client_id)
        self.enqueue(out_msg)

        self.post_initialize()


class VPIntfEchoClient(VPIntfClient):
    def do_handle(self):
        self.enqueue(self.dequeue())


class GiraffeCircuitTest(VPIntfClient):
    def post_initialize(self):
        n_copies = 16
        n_inputs = 8
        n_muxsel = 1
        muxsels = VPIntfClient.vpmsg_bitvector(util.random_bitvec(n_muxsel))
        muxsels = chr(Defs.P_RECV_MUXSEL) + muxsels[1:]
        inputs = VPIntfClient.vpmsg_vector([ util.random_felem() for _ in range(0, n_copies * n_inputs) ])
        inputs = chr(Defs.P_RECV_LAYVALS) + inputs[1:]
        self.enqueue(muxsels)
        self.enqueue(inputs)

    def do_handle(self):
        msg = self.dequeue()
        print msg, len(msg)


class GiraffeShimTest(VPIntfClient):
    def post_initialize(self):
        n_copybits = 4
        n_outbits = 3
        z1 = VPIntfClient.vpmsg_vector( [ util.random_felem() for _ in range(0, n_outbits) ])
        z1 = chr(Defs.P_RECV_Z1) + z1[1:]
        z2 = VPIntfClient.vpmsg_vector( [ util.random_felem() for _ in range(0, n_copybits) ])
        z2 = chr(Defs.P_RECV_Z2) + z2[1:]
        self.enqueue(z1)
        self.enqueue(z2)

    def do_handle(self):
        msg = self.dequeue()
        print msg, len(msg)


class GiraffePLayerTest(VPIntfClient):
    def post_initialize(self):
        n_copybits = 4
        n_copies = 1 << n_copybits
        n_inbits = 3
        n_inputs = 1 << n_inbits
        n_gates = 8
        z2v = VPIntfClient.vpmsg_vector([ util.random_felem() for _ in range(0, 2 * n_copybits) ], Defs.P_RECV_Z2VALS)
        z1x = VPIntfClient.vpmsg_vector([ util.random_felem() for _ in range(0, n_gates) ], Defs.P_RECV_Z1CHI)
        lvs = VPIntfClient.vpmsg_vector([ util.random_felem() for _ in range(0, n_copies * n_inputs)], Defs.P_RECV_LAYVALS)
        self.enqueue(z2v)
        self.enqueue(z1x)
        self.enqueue(lvs)

    def do_handle(self):
        msg = self.dequeue()
        print len(msg), ':', msg, '\n'

        tau = VPIntfClient.vpmsg_vector([ util.random_felem() ], Defs.P_RECV_TAU)
        self.enqueue(tau)


class GiraffeVLayerTest(VPIntfClient):
    def post_initialize(self):
        n_muxsel = 1
        n_outbits = 3
        n_copybits = 4
        n_coeffs = 4

        muxsels = VPIntfClient.vpmsg_bitvector(util.random_bitvec(n_muxsel), Defs.V_RECV_MUXSEL)
        expect = VPIntfClient.vpmsg_vector([ util.random_felem() ], Defs.V_RECV_EXPECT)
        z1v = VPIntfClient.vpmsg_vector([ util.random_felem() for _ in range(0, n_outbits) ], Defs.V_RECV_Z1)
        z2v = VPIntfClient.vpmsg_vector([ util.random_felem() for _ in range(0, n_copybits) ], Defs.V_RECV_Z2)
        coeff = VPIntfClient.vpmsg_vector([ util.random_felem() for _ in range(0, n_coeffs) ], Defs.V_RECV_COEFFS)

        self.enqueue(muxsels)
        self.enqueue(expect)
        self.enqueue(z1v)
        self.enqueue(z2v)
        self.enqueue(coeff)

    def do_handle(self):
        msg = self.dequeue()
        print len(msg), ':', msg, '\n'

        coeff = VPIntfClient.vpmsg_vector([ util.random_felem() for _ in range(0, 4) ], Defs.V_RECV_COEFFS)
        self.enqueue(coeff)


class GiraffeVInputTest(VPIntfClient):
    def post_initialize(self):
        n_inbits = 3
        n_copybits = 4
        n_inputs = 1 << n_inbits
        n_copies = 1 << n_copybits

        inputs = VPIntfClient.vpmsg_vector([ util.random_felem() for _ in range(0, n_copies * n_inputs) ], Defs.V_RECV_INPUTS)
        expect = VPIntfClient.vpmsg_vector([ util.random_felem() ], Defs.V_RECV_EXPECT)
        z1v = VPIntfClient.vpmsg_vector([ util.random_felem() for _ in range(0, n_inbits) ], Defs.V_RECV_Z1)
        z2v = VPIntfClient.vpmsg_vector([ util.random_felem() for _ in range(0, n_copybits) ], Defs.V_RECV_Z2)

        self.enqueue(inputs)
        self.enqueue(expect)
        self.enqueue(z1v)
        self.enqueue(z2v)

    def do_handle(self):
        msg = self.dequeue()
        print len(msg), ':', msg, '\n'

        self.post_initialize()


class GiraffeVOutputTest(VPIntfClient):
    def post_initialize(self):
        n_outbits = 3
        n_copybits = 4
        n_outputs = 1 << n_outbits
        n_copies = 1 << n_copybits

        outputs = VPIntfClient.vpmsg_vector([ util.random_felem() for _ in range(0, n_copies * n_outputs) ], Defs.V_RECV_OUTPUTS)
        self.enqueue(outputs)

    def do_handle(self):
        msg = self.dequeue()
        print len(msg), ':', msg, '\n'

        if ord(msg[0]) == Defs.V_SEND_Z2:
            self.post_initialize()


class GiraffeCoordinator(object):
    class Computation(object):
        layers = []

    class DummyLayer(object):
        is_trusted = False
        is_native = True
        counts = None
        did_print = False
        def __init__(self, num):
            self.laynum = num
            self.counts = []
        def enqueue(self, _):
            pass
        def __repr__(self):
            return '[DummyCLayerClient (%d)]' % self.laynum

    class Prover(object):
        shim = None
        layers = []

    class Verifier(object):
        inputs = None
        outputs = None
        layers = []

    i_values = None
    n_layers = None
    n_inputs = None
    n_copies = None
    n_muxsel = None
    n_cpar = None

    debug_prv = None
    sw_ckt = None

    okay = True
    done = False

    server_info = None

    @classmethod
    def initialize(cls, coord_info, pws_parsed, server_info):
        cls.server_info = server_info
        (iv, nl, ni, ncb, nm, pb) = coord_info

        cls.okay = True
        cls.done = False
        server_info.reset()

        assert iv is None or len(iv) == ni, "Inconsistent #inputs vs length of ivalues list!"
        cls.i_values = [ x % Defs.prime if x is not None else None for x in iv ] if iv is not None else None
        cls.n_layers = nl
        cls.n_inputs = ni
        cls.n_copies = 1 << ncb
        cls.n_muxsel = nm
        cls.n_cpar = 1 << pb

        if cls.server_info.sweval:
            cls.Computation.layers = [ cls.DummyLayer(i) for i in range(0, nl) ]
        else:
            cls.Computation.layers = [None] * nl
        cls.Prover.layers = [None] * nl
        cls.Prover.shim = None
        cls.Verifier.layers = [None] * nl
        cls.Verifier.inputs = None
        cls.Verifier.outputs = None

        if cls.server_info.debug:
            p_from_pws = cprv.CircuitProver.from_pws # pylint: disable=no-member
            (_, cls.debug_prv) = p_from_pws(pws_parsed, cls.n_copies)

        if cls.server_info.sweval:
            c_from_pws = abld.ArithCircuitBuilder.from_pws # pylint: disable=no-member
            (_, cls.sw_ckt) = c_from_pws(pws_parsed, cls.n_copies)

    @classmethod
    def unflatten(cls, vals, padded=True):
        assert len(vals) / cls.n_copies == len(vals) // cls.n_copies
        ilen = len(vals) // cls.n_copies
        ilenr = 1 << util.clog2(ilen)
        rvals = [ vals[ilen*x:ilen*(x+1)] for x in range(0, cls.n_copies) ]
        assert len(rvals) == cls.n_copies
        assert all([ len(rvals[x]) == ilen for x in range(0, cls.n_copies) ])
        if padded:
            if ilen != ilenr:
                rvals = [ rvals[x] + [0] * (ilenr - ilen) for x in range(0, cls.n_copies) ]
            assert all([ len(rvals[x]) == ilenr for x in range(0, cls.n_copies) ])
        return rvals

    @classmethod
    def flatten(cls, vals):
        rval = []
        for v in vals:
            rval.extend(v)
        return rval

    @classmethod
    def is_ready(cls):
        r_clr = len(cls.Computation.layers) > 0 and all([ x is not None for x in cls.Computation.layers ])

        r_psr = cls.Prover.shim is not None
        r_plr = len(cls.Prover.layers) > 0 and all([ x is not None for x in cls.Prover.layers ])

        r_vir = cls.Verifier.inputs is not None
        r_vor = cls.Verifier.outputs is not None
        r_vlr = len(cls.Verifier.layers) > 0 and all([ x is not None for x in cls.Verifier.layers ])

        return all([r_clr, r_psr, r_plr, r_vir, r_vor, r_vlr])

    @classmethod
    def restart_computation(cls):
        cls.okay = True
        cls.done = False

    @classmethod
    def start_computation(cls):
        cls.restart_computation()

        muxsel = cls.server_info.muxsels
        inputs = cls.server_info.inputs

        if muxsel is None:
            muxsel = VPIntfClient.vpmsg_bitvector(util.random_bitvec(cls.n_muxsel))
            cls.server_info.muxsels = muxsel
        else:
            assert len(muxsel) == cls.n_muxsel, "Wrong number of muxsel bits supplied"
            muxsel = VPIntfClient.vpmsg_bitvector(muxsel)

        if inputs is None:
            if cls.i_values is None:
                ivals = [ util.random_felem() for _ in range(0, cls.n_copies * cls.n_inputs) ]
            else:
                ivals = [ x if x is not None else util.random_felem() for x in cls.i_values * cls.n_copies ]

            cls.server_info.inputs = ivals
            inputs = VPIntfClient.vpmsg_vector(ivals)
        else:
            assert len(inputs) == cls.n_copies * cls.n_inputs, "Wrong number of inputs supplied"
            ivals = inputs
            inputs = VPIntfClient.vpmsg_vector(inputs)

        if cls.debug_prv is not None:
            dv_ivals = cls.unflatten(ivals, True)
            cls.debug_prv.set_inputs(dv_ivals)

        # muxsels to all verifier layers
        muxsel = chr(Defs.V_RECV_MUXSEL) + muxsel[1:]
        for lay in cls.Verifier.layers:
            lay.enqueue(muxsel)

        # muxsels to all prover and computation layers
        muxsel = chr(Defs.P_RECV_MUXSEL) + muxsel[1:]
        for lay in cls.Computation.layers:
            lay.enqueue(muxsel)

        for lay in cls.Prover.layers:
            lay.enqueue(muxsel)

        # inputs to P circuit computation and top P layer
        inputs = chr(Defs.P_RECV_LAYVALS) + inputs[1:]
        cls.Computation.layers[cls.n_layers - 1].enqueue(inputs)
        cls.Prover.layers[cls.n_layers - 1].enqueue(inputs)
        # inputs to V input layer
        inputs = chr(Defs.V_RECV_INPUTS) + inputs[1:]
        cls.Verifier.inputs.enqueue(inputs)

        # if we're running the ckt in software, do it now
        if cls.sw_ckt is not None:
            for (idx, lcnts) in enumerate(reversed(cls.sw_ckt.get_counts())):
                nextcnt = [ lcnts[0], lcnts[1], 0, cls.n_cpar * lcnts[2], cls.n_cpar * lcnts[3], 0 ]
                cls.Computation.layers[idx].counts.append(nextcnt)

            (ckt_outputs, lay_outputs) = cls.sw_ckt.run(cls.unflatten(ivals, False), False)
            cls.server_info.outputs = cls.flatten(ckt_outputs)
            outmsg = VPIntfClient.vpmsg_vector(cls.server_info.outputs, Defs.V_RECV_OUTPUTS)
            cls.Verifier.outputs.enqueue(outmsg)

            for (idx, vals) in enumerate(reversed(lay_outputs[1:])):
                laymsg = VPIntfClient.vpmsg_vector(cls.flatten(vals), Defs.P_RECV_LAYVALS)
                cls.Prover.layers[idx].enqueue(laymsg)


class GiraffeClient(VPIntfClient):
    counts = None
    is_trusted = False
    is_native = False
    did_print = False

    # this function re-types the GiraffeClient into the specialized subclass
    # NOTE that this is dangerous in the general case, but since we're not
    #      overriding __init__ anywhere we should be mostly OK :)
    def post_initialize(self):
        if self.client_type == Defs.V_TYPE_LAY:
            self.__class__ = GiraffeVLayerClient

        elif self.client_type == Defs.V_TYPE_IN:
            self.__class__ = GiraffeVInputClient

        elif self.client_type == Defs.V_TYPE_OUT:
            self.__class__ = GiraffeVOutputClient

        elif self.client_type == Defs.P_TYPE_LAY:
            self.__class__ = GiraffePLayerClient

        elif self.client_type == Defs.P_TYPE_SHIM:
            self.__class__ = GiraffePShimClient

        elif self.client_type == Defs.P_TYPE_CIRCUIT:
            self.__class__ = GiraffeCLayerClient

        else:
            raise ValueError("Invalid Giraffe client type %d" % self.client_type)

        self.counts = []
        self.finish_init()

    def handle_debug(self, msg):
        if ord(msg[0]) == Defs.VP_TYPE_DEBUG:
            (_, msgvals) = self.vpmsg_unpack(msg)
            print repr(self), "DEBUG: ", [ hex(x) for x in msgvals ]
            return True
        return False

    def do_handle(self):
        raise NotImplementedError("do_handle for GiraffeClient base class called")

    def finish_init(self):
        raise NotImplementedError("finish_init for GiraffeClient base class called")

    def log_counts(self, msg):
        (_, vals) = self.vpmsg_unpack(msg)
        self.counts.append(vals)

    def __repr__(self):
        return '[%s (%s)]' % (self.__class__.__name__, str(self.client_extra))

class GiraffeVLayerClient(GiraffeClient):
    to_next_layer = False

    def finish_init(self):
        self.is_trusted = True

        if self.client_extra >= GiraffeCoordinator.n_layers:
            raise ValueError("Circuit has %d layers but got verifier layer number %d" % (GiraffeCoordinator.n_layers, self.client_extra))
        if GiraffeCoordinator.Verifier.layers[self.client_extra] is not None:
            raise ValueError("Another client has already claimed verifier layer %d" % self.client_extra)
        GiraffeCoordinator.Verifier.layers[self.client_extra] = self

    def do_handle(self):
        msg = self.dequeue()
        if self.handle_debug(msg):
            return

        msgtype = ord(msg[0])
        if msgtype == Defs.V_SEND_NOKAY:
            print "WARNING: layer %d verification failed" % self.client_extra
            GiraffeCoordinator.okay = False
            self.to_next_layer = True

        elif msgtype == Defs.V_SEND_OKAY:
            self.to_next_layer = True

        elif msgtype == Defs.V_SEND_TAU:
            msg = chr(Defs.P_RECV_TAU) + msg[1:]
            GiraffeCoordinator.Prover.layers[self.client_extra].enqueue(msg)

            if GiraffeCoordinator.debug_prv is not None:
                (_, msgvals) = self.vpmsg_unpack(msg)
                assert len(msgvals) == 1

                to_layer = None
                if self.to_next_layer:
                    if self.client_extra < GiraffeCoordinator.n_layers - 1:
                        GiraffeCoordinator.debug_prv.next_layer(msgvals[0])
                        to_layer = self.client_extra + 1
                else:
                    GiraffeCoordinator.debug_prv.next_round(msgvals[0])
                    to_layer = self.client_extra

                if to_layer is not None:
                    GiraffeCoordinator.Prover.layers[to_layer].expect_vals = GiraffeCoordinator.debug_prv.get_outputs()


        elif msgtype == Defs.V_SEND_EXPECT or msgtype == Defs.V_SEND_Z1 or msgtype == Defs.V_SEND_Z2:
            msg = chr(msgtype + Defs.V_RECV_EXPECT - Defs.V_SEND_EXPECT) + msg[1:]
            if self.client_extra == GiraffeCoordinator.n_layers - 1:
                GiraffeCoordinator.Verifier.inputs.enqueue(msg)
            else:
                GiraffeCoordinator.Verifier.layers[self.client_extra + 1].enqueue(msg)

        elif msgtype == Defs.V_SEND_COUNTS:
            self.log_counts(msg)

        else:
            raise ValueError("Got invalid msgtype %d from verifier layer" % msgtype)


class GiraffeVInputClient(GiraffeClient):
    def finish_init(self):
        self.is_trusted = True

        if GiraffeCoordinator.Verifier.inputs is not None:
            raise ValueError("Another client has already claimed verifier input layer")
        GiraffeCoordinator.Verifier.inputs = self

    def do_handle(self):
        msg = self.dequeue()
        if self.handle_debug(msg):
            return

        msgtype = ord(msg[0])
        if msgtype == Defs.V_SEND_NOKAY:
            print "WARNING: V input check failed"
            GiraffeCoordinator.okay = False
            GiraffeCoordinator.done = True

        elif msgtype == Defs.V_SEND_OKAY:
            GiraffeCoordinator.done = True

        elif msgtype == Defs.V_SEND_COUNTS:
            self.log_counts(msg)

        else:
            raise ValueError("Got invalid msgtype %d from verifier input" % msgtype)


class GiraffeVOutputClient(GiraffeClient):
    z1 = None
    z2 = None
    expect = None

    def finish_init(self):
        self.is_trusted = True

        if GiraffeCoordinator.Verifier.outputs is not None:
            raise ValueError("Another client has already claimed verifier output layer")
        GiraffeCoordinator.Verifier.outputs = self

    def do_handle(self):
        msg = self.dequeue()
        if self.handle_debug(msg):
            return

        msgtype = ord(msg[0])
        if msgtype == Defs.V_SEND_EXPECT:
            msg = chr(Defs.V_RECV_EXPECT) + msg[1:]
            GiraffeCoordinator.Verifier.layers[0].enqueue(msg)

            if GiraffeCoordinator.debug_prv is not None:
                (_, msgvals) = self.vpmsg_unpack(msg)
                assert len(msgvals) == 1
                self.expect = msgvals[0]

        elif msgtype == Defs.V_SEND_Z1 or msgtype == Defs.V_SEND_Z2:
            msg = chr(msgtype + Defs.V_RECV_Z1 - Defs.V_SEND_Z1) + msg[1:]
            GiraffeCoordinator.Verifier.layers[0].enqueue(msg)

            msg = chr(msgtype + Defs.P_RECV_Z1 - Defs.V_SEND_Z1) + msg[1:]
            GiraffeCoordinator.Prover.shim.enqueue(msg)

            if GiraffeCoordinator.debug_prv is not None:
                (_, msgvals) = self.vpmsg_unpack(msg)
                if msgtype == Defs.V_SEND_Z1:
                    assert self.z1 is None
                    self.z1 = msgvals

                elif msgtype == Defs.V_SEND_Z2:
                    assert self.z2 is None
                    self.z2 = msgvals

                if self.z1 is not None and self.z2 is not None and self.expect is not None:
                    GiraffeCoordinator.debug_prv.set_z(self.z1, self.z2)
                    GiraffeCoordinator.Prover.layers[0].expect_vals = GiraffeCoordinator.debug_prv.get_outputs()

                    output_mlext_mults = LayerComputeBeta(len(self.z1) + len(self.z2), self.z1 + self.z2)
                    flat_outputs = gutil.flatten(GiraffeCoordinator.debug_prv.ckt_outputs)
                    assert len(output_mlext_mults.outputs) == len(flat_outputs)
                    expect_recompute = sum(gutil.mul_vecs(flat_outputs, output_mlext_mults.outputs)) % Defs.prime
                    assert self.expect == expect_recompute

                    z1chi_vals = LayerComputeBeta(len(self.z1), self.z1)
                    GiraffeCoordinator.Prover.shim.z1_chi_expect = z1chi_vals.outputs

                    mz2_vals = []
                    for v in self.z2:
                        mz2_vals.append((1 - v) % Defs.prime)

                    GiraffeCoordinator.Prover.shim.z2_expect = self.z2 + mz2_vals


        elif msgtype == Defs.V_SEND_COUNTS:
            self.log_counts(msg)

        else:
            raise ValueError("Got invalid msgtype %d from verifier input" % msgtype)


class GiraffePLayerClient(GiraffeClient):
    expect_vals = None
    saved_inputs = None
    saved_muxsels = None
    send_in_immed = False
    send_mux_immed = False

    def finish_init(self):
        if self.client_extra >= GiraffeCoordinator.n_layers:
            raise ValueError("Circuit has %d layers but got prover layer number %d" % (GiraffeCoordinator.n_layers, self.client_extra))
        if GiraffeCoordinator.Prover.layers[self.client_extra] is not None:
            raise ValueError("Another client has already claimed prover layer %d" % self.client_extra)
        GiraffeCoordinator.Prover.layers[self.client_extra] = self
        self.saved_inputs = collections.deque()
        self.saved_muxsels = collections.deque()

    def do_handle(self):
        msg = self.dequeue()
        if self.handle_debug(msg):
            return

        msgtype = ord(msg[0])
        if msgtype == Defs.P_SEND_Z1CHI or msgtype == Defs.P_SEND_Z2VALS:
            if self.client_extra == GiraffeCoordinator.n_layers - 1:
                #raise ValueError("Final P layer sent z1chi. This shouldn't happen!")
                pass
            else:
                msg = chr(msgtype + Defs.P_RECV_Z1CHI - Defs.P_SEND_Z1CHI) + msg[1:]
                GiraffeCoordinator.Prover.layers[self.client_extra + 1].enqueue(msg)

                if GiraffeCoordinator.debug_prv is not None:
                    (_, msgvals) = self.vpmsg_unpack(msg)

                    if msgtype == Defs.P_SEND_Z1CHI:
                        cz1x = GiraffeCoordinator.debug_prv.layers[-(2+self.client_extra)].compute_z1chi.outputs
                        assert len(msgvals) <= len(cz1x)
                        assert msgvals == cz1x[:len(msgvals)]

                    else:
                        lz2 = len(msgvals)
                        assert lz2 % 2 == 0
                        expect_z2 = GiraffeCoordinator.debug_prv.layers[-(2+self.client_extra)].z2_save
                        z2 = msgvals[:lz2//2]
                        mz2p1 = msgvals[lz2//2:]

                        assert all([ ((1 - z2[i]) % Defs.prime) == mz2p1[i] for i in range(0, lz2 // 2) ])
                        assert z2 == expect_z2


        elif msgtype == Defs.P_SEND_COEFFS:
            msg = chr(Defs.V_RECV_COEFFS) + msg[1:]
            GiraffeCoordinator.Verifier.layers[self.client_extra].enqueue(msg)

            if GiraffeCoordinator.debug_prv is not None:
                assert self.expect_vals is not None
                (_, msgvals) = self.vpmsg_unpack(msg)
                assert msgvals == self.expect_vals

        elif msgtype == Defs.P_SEND_RESTART:
            if len(self.saved_inputs) < 1:
                if self.send_in_immed or self.send_mux_immed:
                    raise ValueError("Duplicate P_SEND_RESTART detected")
                else:
                    self.send_in_immed = True
                    return

            super(GiraffePLayerClient, self).enqueue(self.saved_inputs.popleft())

            if len(self.saved_muxsels) < 1:
                if self.send_mux_immed:
                    raise ValueError("Duplicate P_SEND_RESTART detected")
                else:
                    self.send_in_immed = False
                    self.send_mux_immed = True
                    return

            super(GiraffePLayerClient, self).enqueue(self.saved_muxsels.popleft())

        elif msgtype == Defs.P_SEND_COUNTS:
            self.log_counts(msg)

        else:
            raise ValueError("Got invalid msgtype %d from prover layer" % msgtype)

    def enqueue(self, msg):
        msgtype = ord(msg[0])
        if msgtype == Defs.P_RECV_LAYVALS:
            if not self.send_in_immed:
                self.saved_inputs.append(msg)
                return
            else:
                self.send_in_immed = False

        elif msgtype == Defs.P_RECV_MUXSEL:
            if not self.send_mux_immed:
                self.saved_muxsels.append(msg)
                return
            else:
                self.send_mux_immed = False

        super(GiraffePLayerClient, self).enqueue(msg)


class GiraffePShimClient(GiraffeClient):
    z1_chi_expect = None
    z2_expect = None

    def finish_init(self):
        if GiraffeCoordinator.Prover.shim is not None:
            raise ValueError("Another client has already claimed prover shim layer")
        GiraffeCoordinator.Prover.shim = self

    def do_handle(self):
        msg = self.dequeue()
        if self.handle_debug(msg):
            return

        msgtype = ord(msg[0])
        if msgtype == Defs.P_SEND_Z1CHI or msgtype == Defs.P_SEND_Z2VALS:
            msg = chr(msgtype + Defs.P_RECV_Z1CHI - Defs.P_SEND_Z1CHI) + msg[1:]
            GiraffeCoordinator.Prover.layers[0].enqueue(msg)

            if GiraffeCoordinator.debug_prv is not None:
                (_, msgvals) = self.vpmsg_unpack(msg)

                if msgtype == Defs.P_SEND_Z1CHI:
                    assert msgvals == self.z1_chi_expect
                else:
                    assert msgvals == self.z2_expect

        elif msgtype == Defs.P_SEND_COUNTS:
            self.log_counts(msg)

        else:
            raise ValueError("Got invalid msgtype %d from prover shim" % msgtype)


class GiraffeCLayerClient(GiraffeClient):
    def finish_init(self):
        self.is_native = True

        if self.client_extra >= GiraffeCoordinator.n_layers:
            raise ValueError("Circuit has %d layers but got comp. layer number %d" % (GiraffeCoordinator.n_layers, self.client_extra))
        if GiraffeCoordinator.Computation.layers[self.client_extra] is not None:
            raise ValueError("Another client has already claimed computation layer %d" % self.client_extra)
        GiraffeCoordinator.Computation.layers[self.client_extra] = self

    def do_handle(self):
        msg = self.dequeue()
        if self.handle_debug(msg):
            return

        msgtype = ord(msg[0])
        if msgtype == Defs.P_SEND_COUNTS:
            self.log_counts(msg)
            return

        elif msgtype != Defs.P_SEND_LAYVALS:
            raise ValueError("Got invalid msgtype %d from prover circuit" % msgtype)

        # if this is the output, send to V outputs and save in ServerInfo
        if self.client_extra == 0:
            msg = chr(Defs.V_RECV_OUTPUTS) + msg[1:]
            GiraffeCoordinator.Verifier.outputs.enqueue(msg)
            (_, GiraffeCoordinator.server_info.outputs) = self.vpmsg_unpack(msg)

        # otherwise, send to appropriate P layer
        else:
            msg = chr(Defs.P_RECV_LAYVALS) + msg[1:]
            GiraffeCoordinator.Computation.layers[self.client_extra - 1].enqueue(msg)
            GiraffeCoordinator.Prover.layers[self.client_extra - 1].enqueue(msg)

        if GiraffeCoordinator.debug_prv is not None:
            (_, msgvals) = self.vpmsg_unpack(msg)
            msgvals = GiraffeCoordinator.unflatten(msgvals)

            if self.client_extra == 0:
                assert GiraffeCoordinator.debug_prv.ckt_outputs == msgvals

            else:
                assert GiraffeCoordinator.debug_prv.layers[-self.client_extra].inputs == msgvals
