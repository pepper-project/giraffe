#!/usr/bin/python2.7
#
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# Defs for circuits

import random

class Defs(object):
    # default is a convenient Mersenne prime
    prime = 2 ** 61 - 1
    half = 2 ** 60
    nbits = 61
    third = 1537228672809129301
    rand = None

    savebits = False

    @classmethod
    def gen_random(cls):
        if cls.rand is None:
            cls.rand = random.SystemRandom()

        # random nonzero value
        return cls.rand.randint(1, cls.prime - 1)

class FArith(object):
    def __init__(self):
        self.add_count = {}
        self.mul_count = {}
        self.sub_count = {}

    def new_cat(self, cat):
        return self._FArithCat(self, cat)

    class _FArithCat(object):
        def __init__(self, parent, cat):
            self.parent = parent
            self.cat = cat

        def did_add(self, n=1):
            self.parent.add_count[self.cat] = self.parent.add_count.get(self.cat, 0) + n
        def add(self, x, y):
            self.did_add()
            return (x + y) % Defs.prime
        def add0(self, x, y):
            if x == 0:
                return y
            elif y == 0:
                return x
            else:
                self.did_add()
                return (x + y) % Defs.prime

        def did_mul(self, n=1):
            self.parent.mul_count[self.cat] = self.parent.mul_count.get(self.cat, 0) + n
        def mul(self, x, y):
            self.did_mul()
            return (x * y) % Defs.prime
        def mul0(self, x, y):
            if x == 0 or y == 0:
                return 0
            else:
                self.did_mul()
                return (x * y) % Defs.prime

        def did_sub(self, n=1):
            self.parent.sub_count[self.cat] = self.parent.sub_count.get(self.cat, 0) + n
        def sub(self, x, y):
            self.did_sub()
            return (x - y) % Defs.prime
        def sub0(self, x, y):
            if y == 0:
                return x
            else:
                self.did_sub()
                return (x - y) % Defs.prime

        def get_counts(self):
            mul = self.parent.mul_count.get(self.cat, 0)
            add = self.parent.add_count.get(self.cat, 0)
            sub = self.parent.sub_count.get(self.cat, 0)
            return (mul, add, sub)
