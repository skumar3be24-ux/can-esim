#!/usr/bin/env python3
"""
Correct the three passages in the technical report that still say the
oscillator-independence gap is open. It was closed on Day 43 by the
skew sweep in vhdl/tb/tb_skew.vhdl.

The report was produced with ReportLab and the generator script was not
kept, so the PDF is patched in place at the content-stream level.

Two constraints follow from that:
  1. ReportLab positions every line absolutely, so a replacement longer
     than the original overlaps the line after it. Lengths are matched.
  2. The embedded fonts are subsets. A character that appears nowhere
     else in the document renders blank, which is why the replacements
     spell out "per cent" instead of using a percent sign.

Run:  python3 patch_report_skew.py <in.pdf> <out.pdf>
"""
import sys
import pikepdf

# (page, original, replacement)
EDITS = [
    # --- section 4, the "what is not modelled" table ---
    (5,
     b'Shared clock',
     b'Now verified'),
    (5,
     b'Resynchronisation is implemented and unit-tested but exercising it needs deliberate skew',
     b'Resynchronisation verified over a 0 to 6 per cent skew sweep; the netlist shares a clock'),

    # --- section 16, coverage table ---
    (26,
     b'not exercised',
     b'now verified'),
    (26,
     b'resync is built and unit-tested but needs deliberate skew',
     b'correct to 3 per cent skew; detects and rejects beyond that'),

    # --- section 21.2, limitations ---
    (29,
     b'All nodes share a clock.',
     b'One clock in the netlist.'),
    (29,
     b' The resynchronisation logic is implemented and unit-tested, including the asymmetry',
     b' Resynchronisation is verified against independent oscillators in VHDL simulation,'),
    (29,
     b'between positive and negative phase error and the SJW cap, but it is never exercised against genuinely independent',
     b'sweeping node B from 0 to 6 per cent skew. Reception stays correct to 3 per cent, three times the 0.98 per cent'),
    (29,
     b'oscillators. This is the most significant gap: it means the hardest part of bit timing is verified in isolation but not in the',
     b'bound derived from SJW. Above the threshold the receiver flags an error and rejects the frame rather than accepting corrupt'),
    (29,
     b'system.',
     b'data.'),
]


def main(src, dst):
    pdf = pikepdf.open(src)
    applied = failed = 0

    for pgno in sorted({e[0] for e in EDITS}):
        page = pdf.pages[pgno - 1]
        data = page.Contents.read_bytes()

        for p, old, new in EDITS:
            if p != pgno:
                continue
            n = data.count(old)
            if n == 0:
                print("  MISS  p%-3d %r" % (pgno, old[:55]))
                failed += 1
                continue
            if n > 1:
                print("  AMBIG p%-3d %d matches %r" % (pgno, n, old[:45]))
                failed += 1
                continue
            data = data.replace(old, new, 1)
            delta = len(new) - len(old)
            print("  ok    p%-3d %+3d  %r" % (pgno, delta, new[:55]))
            applied += 1

        page.Contents = pdf.make_stream(data)

    pdf.save(dst)
    print("\napplied %d, failed %d -> %s" % (applied, failed, dst))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1], sys.argv[2]))
