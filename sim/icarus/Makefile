# icarus/Makefile
# (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

VPIMODULES = arith
SIMULATOR = vvp

VERBOSE ?= 1
ifeq ($(VERBOSE),1)
	SIMULATOR += -v
endif

USEINTF ?= 0
ifeq ($(USEINTF),1)
	VPIMODULES += vpintf
endif

DEBUG ?= 0
export DEBUG

.PHONY: clean links vpi

all:
	echo "You probably want to make sim_foo"

links:
	+make -C vpi links
	+make -C rtl links

.PRECIOUS: rtl/%.vvp
rtl/%.vvp:
	+make -C rtl $(notdir $@)

vpi:
	+make -C vpi

sim_%: vpi rtl/%.vvp
	$(eval TARG := $(@:sim_%=%))
	$(SIMULATOR) -Mvpi $(VPIMODULES:%=-m%) rtl/$(TARG).vvp -fst

FPFILES:=$(subst .sv,.vvp,$(wildcard rtl/frompws_*.sv))
frompws: MAKEFLAGS :=
frompws: vpi $(FPFILES)
	$(MAKE) USEINTF=1 -j $(FPFILES:rtl/%.vvp=sim_%)

clean:
	+make -C vpi clean
	+make -C rtl clean
	rm -f *.vcd *.vcd.hier *.fst *.fst.hier arith_log.txt
	rm -f rtl/cmt_top.sv rtl/cmt_top_pl.sv rtl/layergen.sv rtl/prover_synth_test.sv
