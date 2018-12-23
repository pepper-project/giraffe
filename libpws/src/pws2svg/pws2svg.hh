// render PWS as SVG
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <gmp.h>
#include <iostream>
#include <numeric>
#include <random>
#include <sstream>
#include <set>
#include <tuple>
#include <utility>
#include <vector>

#include "pws_circuit_parser.hh"
#include "math.hh"
#include "poly_utils.hh"

#include "util.h"

using namespace std;

// interconnect routing typedefs
typedef pair<unsigned,unsigned> HRange;
typedef vector<HRange> HTrack;
typedef vector<HTrack> TrackInfo;
typedef tuple<set<unsigned>, unsigned, unsigned, unsigned> TrackSpec;
            //in coords      out coord  track#   out #

class SVGData {
    public:
        unsigned w;
        unsigned h;
        unsigned y;
        char *title;
        stringstream &buf;
        PWSCircuitParser &parser;
        default_random_engine rng;

        SVGData(stringstream &b, PWSCircuitParser &p, char *t)
            : w(0)
            , h(0)
            , y(0)
            , title(t)
            , buf(b)
            , parser(p)
        {
            random_device rd;
            rng.seed(rd());
        }

        void setw(unsigned wd) { w = wd > w ? wd : w; }
        void seth(unsigned ht) { h = ht > h ? ht : h; }

        friend ostream &operator<<(ostream &os, const SVGData &svg);
};

// high-level rendering functions
static void showInput(SVGData &svg);
static void showLayer(SVGData &svg, unsigned n);
static void printSVG(SVGData &svg);
ostream &operator<<(ostream &os, const SVGData &svg);

// track drawing functions
static unsigned outXCoord(unsigned i);
static unsigned in1XCoord(unsigned j);
static unsigned in2XCoord(unsigned j);
static unsigned inYCoord(SVGData &svg);
static unsigned outYCoord(SVGData &svg);
static void allocateTrack(TrackInfo &info, TrackSpec &track);

// low-level SVG functions
static string svgCircle(unsigned x, unsigned y, unsigned r, const char *pArray);
static string svgText(string s, unsigned x, unsigned y);
static string svgTextBig(const char *s, unsigned x, unsigned y);
static string svgTextSize(const char *str, unsigned x, unsigned y, unsigned size);
static string svgGate(GateDescription &gate, SVGData &svg, unsigned x, unsigned gateNum, unsigned layer);
static HRange getRange(TrackSpec &track);
static string svgTrack(TrackSpec &spec, unsigned inY, unsigned outY, unsigned layer);

// SVG definitions
static const unsigned cellWidth = 100;
static const unsigned cellHeight = 100;
static const unsigned circleRad = 25;
static const unsigned symbLen = 10;
static const unsigned outSpace = 10;
static const unsigned inSpace = 30;
static const unsigned trackdY = 15;
static const unsigned trackWidth = 2;

static const unsigned leftPad = 50;
static const unsigned rightPad = 50;

static const char *colors[] = {"red", "green", "darkorange", "blue", "fuchsia", "darkviolet"};
static const unsigned nColors = 6;

static const unsigned fontSize = 16;
static const unsigned fontSizeBig = 24;
static const unsigned strokeWidth = 3;
static const char *font = "monospace";

static const unsigned nRandTries = 300;

static const char *javascript = R"(
<script>
    var hStrokeWidth = 6;
    var uStrokeWidth = 2;
    var highlights = [];
    function hPath(n) {
        var p = document.getElementById(n);
        p.setAttribute("stroke-width", hStrokeWidth);
    }
    function uPath(n) {
        var p = document.getElementById(n);
        p.setAttribute("stroke-width", uStrokeWidth);
    }
    function hPaths(a) {
        a.forEach(hPath);
    }
    function uPaths(a) {
        a.forEach(uPath);
        hPaths(highlights);
    }
    function tClick(a) {
        if (a.reduce(function (p, c, i, a) { return p &amp;&amp; (highlights.indexOf(c) >= 0); }, true)) {
            highlights = highlights.filter(function (e) { return a.indexOf(e) &lt; 0; });
            uPaths(a);
        } else {
            highlights = highlights.concat(a);
            hPaths(highlights);
        }
    }
</script>
)";
