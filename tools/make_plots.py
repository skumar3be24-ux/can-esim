#!/usr/bin/env python3
"""
Generate figures from the eSim CAN simulation for the abstract.

Reads the ASCII ngspice raw file and produces:
  1. the differential bus waveform over a full frame
  2. a zoom on the arbitration field showing both nodes driving
  3. the control signals (clock, reset, request)
"""
import os

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

RAW = ('/home/vboxuser/eSim-Workspace/CAN_Bus_MixedSignal/'
       'can_esim_ascii.raw')
OUT = '/home/vboxuser/Documents/CAN_project/docs/waveforms'
os.makedirs(OUT, exist_ok=True)

# ---------------- parse ----------------
names = []
npts = nvars = 0
lines = open(RAW).read().splitlines()
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


def sig(nm):
    return data[names.index(nm)]


t = [x * 1e6 for x in data[0]]        # microseconds
canh = sig('v(x1.canh)')
canl = sig('v(x1.canl)')
vdiff = [a - b for a, b in zip(canh, canl)]
txa = sig('v(/txa_a)')
txb = sig('v(/txb_a)')
rx = sig('v(/rx_a)')
clk = sig('v(/clk_a)')
rst = sig('v(/rst_a)')
req = sig('v(/req_a)')

# ---------------- figure 1: the bus ----------------
fig, ax = plt.subplots(3, 1, figsize=(10, 8), sharex=True)

ax[0].plot(t, canh, lw=0.8, label='CANH')
ax[0].plot(t, canl, lw=0.8, label='CANL')
ax[0].set_ylabel('volts')
ax[0].set_title('CAN differential pair, eSim mixed-signal simulation')
ax[0].legend(loc='upper right', fontsize=8)
ax[0].grid(alpha=0.3)

ax[1].plot(t, vdiff, lw=0.8, color='tab:red')
ax[1].axhline(0.9, ls='--', lw=0.7, color='gray')
ax[1].axhline(0.5, ls='--', lw=0.7, color='gray')
ax[1].set_ylabel('CANH - CANL')
ax[1].text(t[-1] * 0.72, 1.05, 'dominant threshold 0.9 V', fontsize=7)
ax[1].text(t[-1] * 0.72, 0.15, 'recessive threshold 0.5 V', fontsize=7)
ax[1].grid(alpha=0.3)

ax[2].plot(t, rx, lw=0.8, color='tab:green')
ax[2].set_ylabel('receiver out')
ax[2].set_xlabel('time (us)')
ax[2].grid(alpha=0.3)

plt.tight_layout()
plt.savefig(os.path.join(OUT, 'can_bus_frame.png'), dpi=140)
plt.close()

# ---------------- figure 2: arbitration zoom ----------------
lo, hi = 20, 80
sel = [j for j, x in enumerate(t) if lo <= x <= hi]
if sel:
    fig, ax = plt.subplots(2, 1, figsize=(10, 5.5), sharex=True)
    ts = [t[j] for j in sel]
    ax[0].plot(ts, [txa[j] for j in sel], lw=0.9, label='node A drive')
    ax[0].plot(ts, [txb[j] for j in sel], lw=0.9, label='node B drive')
    ax[0].set_ylabel('volts')
    ax[0].set_title('Arbitration field: both nodes contend for the bus')
    ax[0].legend(loc='upper right', fontsize=8)
    ax[0].grid(alpha=0.3)

    ax[1].plot(ts, [vdiff[j] for j in sel], lw=0.9, color='tab:red')
    ax[1].axhline(0.9, ls='--', lw=0.7, color='gray')
    ax[1].set_ylabel('CANH - CANL')
    ax[1].set_xlabel('time (us)')
    ax[1].grid(alpha=0.3)

    plt.tight_layout()
    plt.savefig(os.path.join(OUT, 'can_arbitration.png'), dpi=140)
    plt.close()

# ---------------- figure 3: control signals ----------------
fig, ax = plt.subplots(figsize=(10, 3.2))
ax.plot(t, rst, lw=0.9, label='reset')
ax.plot(t, req, lw=0.9, label='transmit request')
ax.set_xlim(0, 30)
ax.set_ylabel('volts')
ax.set_xlabel('time (us)')
ax.set_title('Control signals: reset released at 2 us, request at 10 us')
ax.legend(loc='center right', fontsize=8)
ax.grid(alpha=0.3)
plt.tight_layout()
plt.savefig(os.path.join(OUT, 'can_control.png'), dpi=140)
plt.close()

print("wrote figures to", OUT)
for f in sorted(os.listdir(OUT)):
    print("   ", f)
