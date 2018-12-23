# makefile for Giraffe
# build pylibpws solib

all: pypws/pylibpws.so

pypws/pylibpws.so: ../libpws/src/pylibpws/.libs/pylibpws.so
	@mkdir -p $(dir $@)
	@cp $< $@

../libpws/src/pylibpws/.libs/pylibpws.so: ../libpws/src/pylibpws/pylibpwsmodule.cc
	@echo "Building pylibpws"
	@cd ../libpws && ./autogen.sh && ./configure
	@+$(MAKE) -C ../libpws

clean:
	@+$(MAKE) -C ../libpws distclean
	@rm -f pypws/pylibpws.so
