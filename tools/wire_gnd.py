#!/usr/bin/env python3
"""
Move each ground symbol under the pin it grounds and wire it.

Electrically nothing changes - the GND labels already put every one
of these pins on net GND, which the netlist confirms. This is purely
so the schematic reads correctly: a ground symbol should sit at the
end of a short wire from the pin it returns.
"""
import re
import shutil
import uuid

P = ('/home/vboxuser/eSim-Workspace/CAN_Bus_MixedSignal/'
     'CAN_Bus_MixedSignal.kicad_sch')
shutil.copy(P, P + '.bak_gnd')
s = open(P).read()

# ---- ground pin offset from the symbol origin ----
libsec = s[s.index('(lib_symbols'):]
goff = None
for blk in re.split(r'\n    \(symbol "', libsec)[1:]:
    if blk.split('"')[0].startswith('eSim_Power:eSim_GND'):
        m = re.search(r'\(pin \w+ \w+ \(at ([-\d.]+) ([-\d.]+)', blk)
        if m:
            goff = (float(m.group(1)), float(m.group(2)))
if goff is None:
    print("could not find the eSim_GND pin offset")
    raise SystemExit(1)
gx, gy = goff

# pins that need a ground return, and how far below to place the symbol
targets = [
    (44.45, 97.79, 7.62),      # v1 pin 2
    (45.72, 130.81, 7.62),     # v2 pin 2
    (45.72, 162.56, 7.62),     # v3 pin 2
    (250.19, 91.44, 7.62),     # v4 pin 2
    (251.46, 124.46, 7.62),    # v5 pin 2
    (252.73, 156.21, 7.62),    # v6 pin 2
    (209.48, 119.38, 12.70),   # X1 gnd - a little lower to clear the body
]

# ---- reposition the ground symbols ----
gnds = [m for m in re.finditer(
    r'\(symbol \(lib_id "eSim_Power:eSim_GND"\) '
    r'\(at ([-\d.]+) ([-\d.]+) (\d+)\)', s)]

print("found %d ground symbols, %d pins to ground" % (len(gnds), len(targets)))

out = s
wires = []
for k, m in enumerate(gnds):
    if k >= len(targets):
        break
    px, py, drop = targets[k]
    # the symbol origin so its pin lands at (px, py + drop)
    sx = px - gx
    sy = (py + drop) + gy
    old = m.group(0)
    new = ('(symbol (lib_id "eSim_Power:eSim_GND") '
           '(at %.2f %.2f %s)' % (sx, sy, m.group(3)))
    out = out.replace(old, new, 1)
    wires.append(
        '  (wire (pts (xy %.2f %.2f) (xy %.2f %.2f))\n'
        '    (stroke (width 0) (type default) (color 0 0 0 0))\n'
        '    (uuid %s)\n  )\n'
        % (px, py, px, py + drop, uuid.uuid4()))
    print("   ground %d -> pin (%.2f, %.2f)" % (k + 1, px, py))

i = out.rstrip().rfind(')')
out = out[:i] + ''.join(wires) + out[i:]
open(P, 'w').write(out)
print("\nmoved %d ground symbols and drew their return wires" % len(wires))
