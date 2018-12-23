#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#     this code is derived from libmu, https://github.com/excamera/mu/

import collections
import socket
import struct
import traceback

from vpintf.defs import Defs

# wrapper around socket-like objects to handle
# non-blocking reading and writing in correct format
class SocketNB(object):
    def __init__(self, sock):
        if isinstance(sock, SocketNB):
            self.sock = sock.sock
            self.want_write = sock.want_write
            self.want_handle = sock.want_handle
            self.expectlen = sock.expectlen
            self.recv_queue = sock.recv_queue
            self.send_queue = sock.send_queue
            self.recv_buf = sock.recv_buf
            self.send_buf = sock.send_buf

        else:
            self.sock = sock
            self.want_write = False
            self.want_handle = False
            self.expectlen = None
            self.recv_queue = collections.deque()
            self.send_queue = collections.deque()
            self.recv_buf = ""
            self.send_buf = None

        self._fileno = sock.fileno()

    def fileno(self):
        return self._fileno

    def getsockname(self):
        return self.getsockname()

    def getpeername(self):
        return self.getpeername()

    @staticmethod
    def shutdown(*_):
        pass

    def close(self):
        if self.sock is None:
            return

        if Defs.debug:
            print "CLOSING SOCKET %s" % traceback.format_exc()

        try:
            self.sock.shutdown(socket.SHUT_RDWR)
            self.sock.close()
        except:
            pass

        self.sock = None

    def _fill_recv_buf(self):
        start_len = len(self.recv_buf)
        while True:
            try:
                nbuf = self.sock.recv(16384)
                if len(nbuf) == 0:
                    break
                else:
                    self.recv_buf += nbuf
            except:
                break

        if len(self.recv_buf) == start_len:
            self.close()

    def do_read(self):
        if self.sock is None:
            return

        self._fill_recv_buf()
        if len(self.recv_buf) == 0:
            return

        while True:
            if self.expectlen is None:
                if len(self.recv_buf) >= 4:
                    # NOTE exception will bubble out to calling function!
                    self.expectlen = struct.unpack("<L", self.recv_buf[0:4])[0]
                    self.recv_buf = self.recv_buf[4:]
                else:
                    break

            # expectlen indicates how much we want, so get it
            else:
                if len(self.recv_buf) >= self.expectlen:
                    self.recv_queue.append(self.recv_buf[:self.expectlen])
                    self.recv_buf = self.recv_buf[self.expectlen:]
                    self.expectlen = None
                else:
                    break

        self.update_flags()

    def update_flags(self):
        self.want_handle = len(self.recv_queue) > 0
        self.want_write = len(self.send_queue) > 0 or self.send_buf is not None

    def enqueue(self, msg):
        self.send_queue.append(self.format_message(msg))
        self.update_flags()

    @staticmethod
    def format_message(msg):
        return struct.pack("<L", len(msg)) + msg

    def dequeue(self):
        if len(self.recv_queue) == 0:
            return None

        ret = self.recv_queue.popleft()
        self.update_flags()
        return ret

    def _fill_send_buf(self):
        self.send_buf = '' if self.send_buf is None else self.send_buf

        # if we have multiple messages enqueued, put them all in the buffer
        while len(self.send_queue) > 0:
            self.send_buf += self.send_queue.popleft()

        if len(self.send_buf) == 0:
            self.send_buf = None

    def _send_raw(self):
        while True:
            slen = 0
            try:
                slen = self.sock.send(self.send_buf)
            except (socket.error, OSError):
                break

            self.send_buf = self.send_buf[slen:]
            if len(self.send_buf) < 1:
                self.send_buf = None
                break

    def do_write(self):
        if self.sock is None:
            return

        self._fill_send_buf()
        if self.send_buf is not None:
            self._send_raw()

        self.update_flags()
