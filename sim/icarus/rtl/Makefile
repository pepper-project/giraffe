# icarus/rtl/Makefile
# (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

SFTFILES = arith.sft sendrcv.sft vpiserver.sft
MODULES = hello arith field_adder_ns field_multiplier_ns field_arith_ns sendrcv
COMPILER = iverilog -g2012 -Wall -Wno-sensitivity-entire-array

DEBUG ?= 0
ifeq ($(DEBUG),1)
COMPILER += -delaborate
endif

ifdef NCOMPS
	COMPILER += -DCMT_TOP_PL_NCOMPS=$(NCOMPS)
endif

.PHONY: clean links
.SUFFIXES: .vvp .v .sv

all: $(MODULES:=.vvp)

links:
	find . -mindepth 1 -maxdepth 1 -type l -print0 | xargs -0 rm
	find ../../common/[rtf]* -type f -print0 | xargs -0 ln -t . -s

.v.vvp:
	$(eval BASE := $(@:.vvp=))
	$(COMPILER) -o$@ $< $(SFTFILES)

.sv.vvp:
	$(eval BASE := $(@:.vvp=))
	$(COMPILER) -o$@ $< $(SFTFILES)

clean:
	rm -f *.vvp a.out
