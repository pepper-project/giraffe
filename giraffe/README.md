# giraffe s/w impl #

(See below for info on running h/w impl)

This is an implementation of Giraffe that closely mirrors the hardware impl.
This can be used to estimate the number of field operations Giraffe executes
when outsourcing a given computation.

## Building and using ##

The code in this directory is pure Python, but to read PWS files we must compile a C++ extension.
The source for this extension lives in ../libpws.

To make all of this easy, there's a makefile in this directory that you can use. For example,
`make -j4` will do more or less what you expect.

You may need to install a few libraries before you can build libpws. ../libpws/README.md gives
some pointers and a commandline that should get you going on reasonably modern Debian-like systems.

**Note**: you do *not* need to run `make install` in ../libpws.

## Running ##

If you want to run a PWS file, you should use `run_giraffe.py` like so:

    ./run_giraffe.py -p /path/to/PWS/file -c nCopies

This will run the computation described in the PWS file with a randomly-generated input. If you'd
prefer to supply your own inputs, you can use the `-i` flag. Executing `run_giraffe.py` with
no arguments will give a short usage summary.

## Tests ##

The `giraffetests/` subdir has a pretty complete set of tests for giraffelib. (These tests
do not require building pypws.)

You can run the tests like so:

    python giraffetests/

# giraffe h/w impl #

If you want to run Giraffe's hardware, you're going to need to be able to build the software
impl (see directions above).

## Installing Icarus ##

Next, you'll need to build Icarus Verilog. I have tested with commit 7ddc514, but newer commits
may also work. To build from git you'll need autoconf, GNU Make, a C++ compiler, bison, flex,
and gperf (see README.txt in the iverilog repo for more info). Something like the following
should work on Debian-ish systems:

    apt-get install build-essential g++-5 automake bison flex gperf

Then you should be able to do something like:

    git clone https://github.com/steveicarus/iverilog
    cd iverilog
    git checkout 7ddc514518a535ef0a63674bfe03f0223bb5e55b
    autoconf
    ./configure
    make
    make check
    sudo make install

Note that installing the version that comes with your Linux distribution almost certainly
won't work---the design requires a pretty recent version of Icarus!

## Running a computation ##

For now, this is somewhat complicated, and requires a couple different terminals:

1. In first terminal:

        cd <giraffe_dir>/sim/icarus/rtl
        ../../../giraffe/run_giraffe_sv.py <pwsfile> <log #Copies>

  Note that this will not background!

  At the end of simulation, this program will dump out statistics for Native, Untrusted, and Trusted.

2. In second terminal:

        cd <giraffe_dir>/sim/icarus
        make -j<something> clean frompws

  For very large computations, you will need to choose `<something>` carefully above. The reason is
  that compiling some circuits requires substantial memory, and you risk hitting the OOM killer if
  you run with too much parallelism. For example, for a computation comprising 16 copies of a
  2^10-point NTT, a single compiler invocation might require 10 GB of RAM or more.

  If you start seeing the above make invocation die with signal 137, you're almost certainly getting
  OOM kills. Reduce `<something>` and try again.

## Running giraffe from another program ##

You can invoke Giraffe from another program by importing `run_giraffe_sv.py`,
setting the `ServerInfo` class's static members to some values, and then calling
`run_giraffe_sv.main()`.

For information on how to set up the member variables, see the `get_params()`
function; you should be able to mimic its functionality pretty easily.
Besides the settings in the `get_params()` function, you can set the following:

- `inputs`: a flat list of inputs to all copies of an arithmetic circuit
- `muxsels`: mux selector settings for gates in the AC. Please note that
   if your computation does not use muxes, you must set `muxsels` to `None`.

After running the computation, `outputs` will be set to a flat list of the
outputs from each copy of the arithmetic circuit, and `success` will be
True or False depending on the success or failure of the proof protocol.

`run_giraffe_sv` tries to set its path so that it can find all of the files
on which it depends (but it assumes that those modules are located in the
same directory as the `run_giraffe_sv.py` file).

# Questions? #

    rsw@cs.nyu.edu
