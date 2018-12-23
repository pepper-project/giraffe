#!/usr/bin/perl -w
# generate a random PWS with specified number of gates at each layer
# (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

if (scalar @ARGV < 2) {
    print "Usage: $0 [n0 n1 [n2 [...]]]\n\n";
    print "Generate a random PWS file.\n";
    print "n0 is #inputs, n1 is #gates in 1st layer, n2 is #gates in 2nd layer, etc\n";
    exit(-1);
}

my $varnum = 0;
my $lastlen = 0;
my $bitnum = 0;
for (my $j = 0; $j < scalar @ARGV; $j++) {
    my $arg = int($ARGV[$j]);
    if ($arg < 4) {
        print "ERROR: #inputs must be >= 4, and each layer must have at least 4 gates.\n";
    }

    my $vname = "V";
    if ($j + 1 == scalar @ARGV) {
        $vname = "O";
    }
    if ($lastlen == 0) {    # first layer
        my $nconsts = 0;
        for (my $i = 0; $i < $arg; $i++) {
            if ($i != 0 && int(rand($arg)) < 2) {
                $nconsts++;
                next;
            } else {
                my $j = $i - $nconsts;
                print "P V$j = I$j E\n";
            }
        }
        for (my $i = 0; $i < $nconsts; $i++) {
            print "P V" . ($arg - $nconsts + $i) . " = " . int(rand(1048576)) . " E\n";
        }

        $lastlen = $arg;
        $varnum = $arg;
    } else {
        for (my $i = 0; $i < $arg; $i++) {
            my $num = $varnum + $i;
            my $in1 = $varnum - $lastlen + int(rand($lastlen));
            my $in2 = $varnum - $lastlen + int(rand($lastlen));
            my $type = int(rand(4));

            if ($type == 0) {
                print "MUX $vname$num = V$in1 mux V$in2 bit $bitnum\n";
                $bitnum++;
            } else {
                print "P $vname$num = V$in1 ";

                if ($type == 1) {
                    print "*";
                } elsif ($type == 2) {
                    print "+";
                } else {
                    print "minus";
                }

                print " V$in2 E\n";
            }
        }
        $varnum += $arg;
        $lastlen = $arg;
    }
}
