#!/usr/bin/env python3
"""
Parse the ASCII ngspice raw file from the eSim CAN simulation and
report the protocol signals.
"""
P = ('/home/vboxuser/eSim-Workspace/CAN_Bus_MixedSignal/'
     'can_esim_ascii.raw')

names = []
npts = nvars = 0
lines = open(P).read().splitlines()

i = 0
while i < len(lines):
    ls = lines[i].strip()
    if ls.startswith('No. Variables:'):
        nvars = int(ls.split(':')[1])
    elif ls.startswith('No. Points:'):
        npts = int(ls.split(':')[1])
    elif ls == 'Variables:':
        i += 1
        while len(names) < nvars and i < len(lines):
            p = lines[i].split()
            if len(p) >= 2:
                names.append(p[1])
            i += 1
        continue
    elif ls == 'Values:':
        i += 1
        break
    i += 1

# each point: "<idx> <val>" then nvars-1 lines of "<val>"
data = [[] for _ in range(nvars)]
k = 0
while i < len(lines) and k < npts:
    p = lines[i].split()
    if not p:
        i += 1
        continue
    data[0].append(float(p[-1]))
    for v in range(1, nvars):
        i += 1
        if i >= len(lines):
            break
        q = lines[i].split()
        if q:
            data[v].append(float(q[-1]))
    i += 1
    k += 1

print("parsed %d points, %d signals\n" % (len(data[0]), nvars))

t = data[0]
show = ['v(/clk_a)', 'v(/rst_a)', 'v(/req_a)', 'v(/txa_a)', 'v(/txb_a)',
        'v(/rx_a)', 'v(/vcc5)', 'v(/sel_lo_a)', 'v(/sel_hi_a)',
        'v(x1.canh)', 'v(x1.canl)']

print("%-14s %9s %9s   %s" % ("signal", "min", "max", "first >2.5 V"))
print("-" * 54)
for nm in show:
    if nm not in names:
        print("%-14s  not present" % nm)
        continue
    col = data[names.index(nm)]
    if not col:
        continue
    lo, hi = min(col), max(col)
    ft = None
    for j, v in enumerate(col):
        if v > 2.5:
            ft = t[j]
            break
    fs = ("%.2f us" % (ft * 1e6)) if ft is not None else "never"
    print("%-14s %9.4f %9.4f   %s" % (nm, lo, hi, fs))

# differential bus voltage
if 'v(x1.canh)' in names and 'v(x1.canl)' in names:
    h = data[names.index('v(x1.canh)')]
    l = data[names.index('v(x1.canl)')]
    d = [a - b for a, b in zip(h, l)]
    print("\ndifferential bus (canh - canl):")
    print("   max %.4f V   min %.4f V" % (max(d), min(d)))
    dom = sum(1 for v in d if v > 0.9)
    print("   samples above the 0.9 V dominant threshold: %d of %d"
          % (dom, len(d)))
    for j, v in enumerate(d):
        if v > 0.9:
            print("   first dominant at %.2f us" % (t[j] * 1e6))
            break
