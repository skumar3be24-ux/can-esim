#!/usr/bin/env python3
"""
Draw real point-to-point wires between the blocks.

Signal nets are wired. GND stays as ground symbols with labels, which
is standard practice - ground is never routed across a sheet.

Crossings are harmless: KiCad only joins wires where there is an
explicit junction. The previous attempt failed because stubs ENDED on
neighbouring pins, which does connect. Every route here ends only on
its intended pin.
"""
import re
import shutil
import uuid

P = ('/home/vboxuser/eSim-Workspace/CAN_Bus_MixedSignal/'
     'CAN_Bus_MixedSignal.kicad_sch')
shutil.copy(P, P + '.bak_nowires')
s = open(P).read()

# strip any wires/junctions from previous attempts
s = re.sub(r'  \(wire \(pts[^)]*\)[^)]*\)\n(?:    \([^)]*\)\n)*  \)\n',
           '', s)
s = re.sub(r'  \(junction[^)]*\)\n(?:    \([^)]*\)\n)*  \)\n', '', s)

wires, juncs = [], []


def W(*pts):
    for a, b in zip(pts, pts[1:]):
        wires.append(
            '  (wire (pts (xy %.2f %.2f) (xy %.2f %.2f))\n'
            '    (stroke (width 0) (type default) (color 0 0 0 0))\n'
            '    (uuid %s)\n  )\n' % (a[0], a[1], b[0], b[1], uuid.uuid4()))


def J(x, y):
    juncs.append('  (junction (at %.2f %.2f) (diameter 0) '
                 '(color 0 0 0 0)\n    (uuid %s)\n  )\n'
                 % (x, y, uuid.uuid4()))


# ---------------- pin coordinates (measured) ----------------
# sources
V1 = (44.45, 74.93)          # clock out
V2 = (45.72, 107.95)         # reset out
V3 = (45.72, 139.70)         # request out
V4 = (250.19, 68.58)         # 5 V for the PHY
V5 = (251.46, 101.60)        # id_sel low
V6 = (252.73, 133.35)        # id_sel high

# adc_bridge_4  (U2)
A4I = [(63.50, 97.79), (63.50, 100.33), (63.50, 102.87), (63.50, 105.41)]
A4O = [(91.44, 97.79), (91.44, 100.33), (91.44, 102.87), (91.44, 105.41)]

# adc_bridge_2  (U1)
A2I = [(60.96, 132.08), (60.96, 134.62)]
A2O = [(90.17, 132.08), (90.17, 134.62)]

# can_node_top A (U3) inputs 1..6, output 7
NA = [(115.50, 97.06), (115.50, 99.60), (115.50, 102.14),
      (115.50, 104.68), (115.50, 107.22), (115.50, 109.76)]
NAO = (141.03, 97.06)

# can_node_top B (U4)
NB = [(115.50, 130.08), (115.50, 132.62), (115.50, 135.16),
      (115.50, 137.70), (115.50, 140.24), (115.50, 142.78)]
NBO = (141.03, 130.08)

# dac_bridge_2 (U5)
D2I = [(158.75, 118.11), (158.75, 120.65)]
D2O = [(184.15, 118.11), (184.15, 120.65)]

# can_phy (X1)
PHY_TXA = (209.48, 111.76)
PHY_TXB = (209.48, 114.30)
PHY_RXO = (235.01, 115.57)
PHY_VCC = (209.48, 116.84)

# ---------------- sources into the input bridge ----------------
W(V1, (54.0, 74.93), (54.0, 97.79), A4I[0])          # clock
W(V2, (56.5, 107.95), (56.5, 100.33), A4I[1])        # reset
W(V3, (59.0, 139.70), (59.0, 102.87), A4I[2])        # request

# bus level fed back from the comparator, routed above the sheet
W(PHY_RXO, (243.0, 115.57), (243.0, 60.0), (52.0, 60.0),
  (52.0, 105.41), A4I[3])

# ---------------- bridge outputs to both nodes ----------------
# each net leaves the bridge, runs to a vertical trunk, then branches
# up to node A and down to node B
for k, (out, na, nb, tx) in enumerate([
        (A4O[0], NA[0], NB[0], 96.0),     # CLK
        (A4O[1], NA[1], NB[1], 99.0),     # RST
        (A4O[2], NA[3], NB[3], 102.0),    # REQ  -> in4
        (A4O[3], NA[2], NB[2], 105.0)]):  # RX   -> in3
    W(out, (tx, out[1]))
    W((tx, out[1]), (tx, na[1]), na)
    W((tx, out[1]), (tx, nb[1]), nb)
    J(tx, out[1])

# ---------------- node identities ----------------
# SEL_LO reaches A.in5, A.in6 and B.in5
W(A2O[0], (108.0, 132.08))
W((108.0, 132.08), (108.0, 107.22), NA[4])
W((108.0, 107.22), (108.0, 109.76), NA[5])
W((108.0, 132.08), (108.0, 140.24), NB[4])
J(108.0, 132.08)
J(108.0, 107.22)
# SEL_HI reaches B.in6 only
W(A2O[1], (111.0, 134.62), (111.0, 142.78), NB[5])

# id_sel sources
W(V5, (258.0, 101.60), (258.0, 55.0), (49.0, 55.0),
  (49.0, 132.08), A2I[0])
W(V6, (261.0, 133.35), (261.0, 52.0), (46.0, 52.0),
  (46.0, 134.62), A2I[1])

# ---------------- node outputs to the bus driver ----------------
W(NAO, (149.0, 97.06), (149.0, 118.11), D2I[0])
W(NBO, (152.0, 130.08), (152.0, 120.65), D2I[1])

# ---------------- driver to the transceiver ----------------
W(D2O[0], (195.0, 118.11), (195.0, 111.76), PHY_TXA)
W(D2O[1], (199.0, 120.65), (199.0, 114.30), PHY_TXB)

# ---------------- PHY supply ----------------
W(V4, (204.0, 68.58), (204.0, 116.84), PHY_VCC)

# ---------------- emit ----------------
i = s.rstrip().rfind(')')
s = s[:i] + ''.join(wires) + ''.join(juncs) + s[i:]
open(P, 'w').write(s)
print("drew %d wire segments and %d junctions" % (len(wires), len(juncs)))
print("backup: CAN_Bus_MixedSignal.kicad_sch.bak_nowires")
