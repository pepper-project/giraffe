// render PWS as SVG
// (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>

#include "pws2svg.hh"

int main(int argc, char **argv) {
    if (argc < 2) {
        cout << "Usage: " << argv[0] << " <foo.pws>" << endl;
        return 1;
    }

    mpz_t prime;
    mpz_init_set_ui(prime, 1);
    mpz_mul_2exp(prime, prime, PRIMEBITS);
    mpz_sub_ui(prime, prime, PRIMEDELTA);
    PWSCircuitParser parser(prime);

    parser.optimize(argv[1]);
    if (parser.circuitDesc.size() == 0) {
        cout << "ERROR: failed to parse " << argv[1] << endl;
        exit(1);
    }

    stringstream svgBuf;
    SVGData svg(svgBuf, parser, argv[1]);
    printSVG(svg);
    return 0;
}

// *** high-level rendering functions *** //
static void printSVG(SVGData &svg) {
    showInput(svg);
    for (unsigned j = 1; j < svg.parser.circuitDesc.size(); j++) {
        showLayer(svg, j);
    }
    cout << svg;
}

// render the input layer of a circuit
static void showInput(SVGData &svg) {
    LayerDescription &layer = svg.parser.circuitDesc[0];
    vector<string> gateVals(layer.size());
    // then initialize constants to the correct value
    for (auto it = svg.parser.inConstants.begin(); it != svg.parser.inConstants.end(); it++) {
        gateVals[it->second] = it->first;
    }

    // now go through each one
    svg.y = 3 * cellHeight / 4;

    for (unsigned j = 0; j < layer.size(); j++) {
        //GateDescription &gate = layer[j];
        unsigned xoff = outXCoord(j);
        if (gateVals[j] == "") {
            svg.buf << svgTextBig("in", xoff, svg.y + 5);
        } else {
            svg.buf << svgText(gateVals[j], xoff, 20 + 20 * (j % 2))
                    << svgTextBig("cnst", xoff, svg.y + 5);
        }
        stringstream pArray;
        pArray << "['o0_" << j << "']";
        svg.buf << svgCircle(xoff, svg.y, circleRad, pArray.str().c_str());
    }

    svg.setw(leftPad + rightPad + cellWidth * layer.size());
    svg.seth(2 * cellHeight);
}

// render a non-input layer of the circuit, drawing interconnect and then gates
static void showLayer(SVGData &svg, unsigned n) {
    LayerDescription &layer = svg.parser.circuitDesc[n];
    TrackInfo trackInfo;
    vector<TrackSpec> trackSpecs(svg.parser.circuitDesc[n-1].size());
    set<unsigned> usedTracks;

    // go through the gates, recording wiring information
    for (unsigned j = 0; j < layer.size(); j++) {
        GateDescription &gate = layer[j];

        // o1 is from previous layer, and connects to this gate's 1st input
        unsigned o1, i1, g1;
        g1 = gate.in1;
        o1 = outXCoord(g1);
        i1 = in1XCoord(j);

        usedTracks.insert(g1);
        TrackSpec &ts1 = trackSpecs[g1];
        get<1>(ts1) = o1;
        get<0>(ts1).insert(i1);
        get<3>(ts1) = g1;

        // o2 is from previous layer, and connects to this gate's 2nd input
        unsigned o2, i2, g2;
        g2 = gate.in2;
        o2 = outXCoord(g2);
        i2 = in2XCoord(j);

        usedTracks.insert(g2);
        TrackSpec &ts2 = trackSpecs[g2];
        get<1>(ts2) = o2;
        get<0>(ts2).insert(i2);
        get<3>(ts2) = g2;
    }

    // warn about unused gate outputs.
    for (unsigned j = 0; j < svg.parser.circuitDesc[n-1].size(); j++) {
        if (usedTracks.find(j) == usedTracks.end()) {
            cerr << "WARNING: output of gate " << j << " at layer " << n-1 << " was unused." << endl;
        }
    }

    // go through wiring information and allocate tracks
    unsigned maxL = 0;
    unsigned minL = -1;
    for (unsigned i = 0; i < nRandTries; i++) {
        TrackInfo tmp;
        vector<unsigned> tryOrder(usedTracks.size());
        copy(usedTracks.begin(), usedTracks.end(), tryOrder.begin());
        shuffle(tryOrder.begin(), tryOrder.end(), svg.rng);
        for (auto tryN = tryOrder.begin(); tryN != tryOrder.end(); tryN++) {
            allocateTrack(tmp, trackSpecs[*tryN]);
        }

        if (tmp.size() < minL) {
            minL = tmp.size();
            trackInfo.swap(tmp);
        }
        if (tmp.size() > maxL) {
            maxL = tmp.size();
        }
    }

    // this is the y position of the previous layer, offsetting to hit the output
    unsigned outY = outYCoord(svg);
    // now that we know how many tracks to allocate, we can set the y position for this layer
    svg.y = outY + outSpace + inSpace + (1 + trackInfo.size()) * trackdY + cellHeight / 2 - circleRad;
    // this is the y position of the current layer, offsetting to hit the input
    unsigned inY = inYCoord(svg);

    // draw the interconnect tracks for this layer
    for (auto usedI = usedTracks.begin(); usedI != usedTracks.end(); usedI++) {
        svg.buf << svgTrack(trackSpecs[*usedI], inY, outY, n - 1);
    }

    // draw the gates for this layer
    for (unsigned j = 0; j < layer.size(); j++) {
        GateDescription &gate = layer[j];
        svg.buf << svgGate(gate, svg, outXCoord(j), j, n - 1);
    }

    // extend the bbox of the SVG to encompass this layer
    svg.setw(leftPad + rightPad + cellWidth * layer.size());
    svg.seth(svg.y + cellWidth);
}

// compute the x coord of a gate output
static unsigned outXCoord(unsigned j) {
    return leftPad + cellWidth * j + cellWidth / 2;
}

// compute the x coord of a gate in1
// this needs to stay in sync with the gate decoration code!
static unsigned in1XCoord(unsigned j) {
    return leftPad + cellWidth * j + cellWidth / 2 - circleRad;
}

// compute the x coord of a gate in2
// this needs to stay in sync with the gate decoration code!
static unsigned in2XCoord(unsigned j) {
    return leftPad + cellWidth * j + cellWidth / 2 + circleRad;
}

// compute y coord of gate input
static unsigned inYCoord(SVGData &svg) {
    return svg.y - circleRad;
}

// compute y coord of gate output
static unsigned outYCoord(SVGData &svg) {
    return svg.y + circleRad;
}

// find the next available track
static void allocateTrack(TrackInfo &info, TrackSpec &track) {
    // figure out left and right
    HRange range = getRange(track);
    unsigned left = range.first;
    unsigned right = range.second;

    // walk the tracks, finding one that does not overlap with left or right
    unsigned trackNum;
    for (trackNum = 0; trackNum < info.size(); trackNum++) {
        bool overlaps = false;
        for (auto hRange = info[trackNum].begin(); hRange != info[trackNum].end(); hRange++) {
            // right < range_left or left > range_right means we're OK
            if ((right < hRange->first) || (left > hRange->second)) {
                continue;
            } else {
                overlaps = true;
                break;
            }
        }

        if (!overlaps) {
            break;
        }
    }

    // we've found a range, add it to the "used tracks" list
    if (trackNum == info.size()) {
        info.emplace_back();
    }
    info[trackNum].emplace_back(left, right);

    get<2>(track) = trackNum;
}

static HRange getRange(TrackSpec &track) {
    // figure out the left and right bounds of this track
    unsigned left = *(get<0>(track).begin());
    unsigned right = *(get<0>(track).rbegin());

    unsigned tOut = get<1>(track);

    if (tOut < left) {
        left = tOut;
    } else if (tOut > right) {
        right = tOut;
    }

    return HRange(left, right);
}

// *** Low-level SVG functions *** //
// draw an interconnect track
static string svgTrack(TrackSpec &track, unsigned inY, unsigned outY, unsigned layer) {
    // figure out left and right
    HRange range = getRange(track);
    unsigned left = range.first;
    unsigned right = range.second;

    unsigned trackNum = get<2>(track);
    unsigned trackY = outY + outSpace + (1 + trackNum) * trackdY;
    unsigned outX = get<1>(track);
    set<unsigned> &inXs = get<0>(track);

    stringstream s;
    s << "<path fill=\"none\" stroke-linecap=\"round\" stroke=\""
      << colors[trackNum % nColors]
      << "\" stroke-width=\""
      << trackWidth
      << "\" d=\"M "
      << outX
      << ' '
      << outY
      << " L "
      << outX
      << ' '
      << trackY
      << " M "
      << left
      << ' '
      << trackY
      << " L "
      << right
      << ' '
      << trackY;

    for (auto inX = inXs.begin(); inX != inXs.end(); inX++) {
        s << " M "
          << *inX
          << ' '
          << trackY
          << " L "
          << *inX
          << ' '
          << inY;
    }

    stringstream pName;
    pName << 'o'
          << layer
          << '_'
          << get<3>(track);

    s << "\" id=\""
      << pName.str()
      << "\" onmouseover=\"hPaths(['"
      << pName.str()
      << "'])\" onmouseout=\"uPaths(['"
      << pName.str()
      << "'])\" onclick=\"tClick(['"
      << pName.str()
      << "'])\"/>"
      << endl;
    return s.str();
}

// draw a circle with the given center and radius
static string svgCircle(unsigned x, unsigned y, unsigned r, const char *pArray) {
    stringstream s;
    s << "<circle cx=\""
      << x
      << "\" cy=\""
      << y
      << "\" r=\""
      << r
      << "\" stroke-width=\""
      << strokeWidth
      << "\" stroke=\"black\" fill=\"white\" fill-opacity=\"0\" onmouseover=\"hPaths("
      << pArray
      << ")\" onmouseout=\"uPaths("
      << pArray
      << ")\" onclick=\"tClick("
      << pArray
      << ")\"/>"
      << endl;
    return s.str();
}

// render svg text in small font
static string svgText(string s, unsigned x, unsigned y) {
    return svgTextSize(s.c_str(), x, y, fontSize);
}

// render SVG text in big font
static string svgTextBig(const char *s, unsigned x, unsigned y) {
    return svgTextSize(s, x, y, fontSizeBig);
}

// generic SVG text renderer
static string svgTextSize(const char *str, unsigned x, unsigned y, unsigned size) {
    stringstream s;
    s << "<text text-anchor=\"middle\" x=\""
      << x
      << "\" y=\""
      << y
      << "\" font-family=\""
      << font
      << "\" font-size=\""
      << size
      << "\">"
      << str
      << "</text>"
      << endl;
    return s.str();
}

// render a gate from the circuit
static string svgGate(GateDescription &gate, SVGData &svg, unsigned x, unsigned gateNum, unsigned layer) {
    unsigned y = svg.y;
    const char *pStart = "<path fill=\"none\" stroke=\"black\" stroke-width=\"";
    const char *pCont = "\" d=\"M ";
    const char *pEnd = "\"/>";

    // draw the gate operation: +, -, or x
    stringstream s, s2;
    GateDescription::OpType t = gate.op;
    switch (t) {
        case GateDescription::ADD:
            // a vertical '|'
            s << pStart
              << strokeWidth
              << pCont
              << x
              << ' '
              << y - symbLen
              << " l 0 "
              << 2 * symbLen
              << pEnd;
        case GateDescription::SUB:
            // a horizontal '-'
            s << pStart
              << strokeWidth
              << pCont
              << x - symbLen
              << ' '
              << y
              << " l "
              << 2 * symbLen
              << " 0"
              << pEnd;
            break;

        case GateDescription::MUL:
            // a slash like '\'
            s << pStart
              << strokeWidth
              << pCont
              << x - symbLen
              << ' '
              << y - symbLen
              << " l "
              << 2 * symbLen
              << ' '
              << 2 * symbLen
              << pEnd

            // a slash like '/'
              << pStart
              << strokeWidth
              << pCont
              << x - symbLen
              << ' '
              << y + symbLen
              << " l "
              << 2 * symbLen
              << " -"
              << 2 * symbLen
              << pEnd;
            break;

        case GateDescription::MUX:
            s2 << svg.parser.muxGates[gate.pos.layer].at(gate.pos.name);
            s << svgTextBig("MUX", x, y + 5);
            s << svgText(s2.str(), x, y - 3 * symbLen);
            break;

        default:
            cerr << "Could not parse gate!" << endl;
            exit(-1);
    }

    // construct the pArray
    stringstream pArray;
    pArray << "['o"
           << layer
           << '_'
           << gate.in1
           << "', 'o"
           << layer
           << '_'
           << gate.in2
           << "', 'o"
           << layer + 1
           << '_'
           << gateNum
           << "']";

    // draw a circle with little horns on it
    s << endl
      << svgCircle(x, y, circleRad, pArray.str().c_str())
    // left decorator
      << pStart
      << strokeWidth
      << pCont
      << x - (circleRad * 0.707)
      << ' '
      << y - (circleRad * 0.707)
      << " l -"
      << circleRad * 0.293
      << " -"
      << circleRad * 0.293
      << pEnd
    // right decorator
      << pStart
      << strokeWidth
      << pCont
      << x + (circleRad * 0.707)
      << ' '
      << y - (circleRad * 0.707)
      << " l "
      << circleRad * 0.293
      << " -"
      << circleRad * 0.293
      << pEnd
      << endl;

    return s.str();
}

ostream &operator<<(ostream &os, const SVGData &svg) {
    os << "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\""
       << svg.w
       << "\" height=\""
       << svg.h
       << "\" viewbox=\"0 0 "
       << svg.w
       << ' '
       << svg.h
       << "\"><title>Arithmetic circuit: "
       << svg.title
       << "</title>"
       << javascript
       << svg.buf.str()
       << endl
       << "</svg>"
       << endl;

    return os;
}
