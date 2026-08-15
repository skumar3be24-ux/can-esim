# Rebuilding this project from nothing

Everything needed to get from a fresh Ubuntu install to a running
mixed-signal CAN simulation. Written so that a future reader — including
the author after a year away — does not have to reconstruct anything by
memory.

If you only want to run the VHDL testbenches or the SPICE regression,
skip to sections 5 and 6. Those need GHDL and ngspice but not eSim.

---

## 1. Environment this was built and verified on

| Component | Version | Notes |
|---|---|---|
| OS | Ubuntu 22.04 LTS | in VirtualBox |
| eSim | 2.5 | from esim.fossee.in/downloads |
| ngspice | 35 | installed by eSim, then patched by NGHDL |
| GHDL | 4.1.0 | `mcode` backend is sufficient |
| KiCad | 6.0 | bundled with eSim 2.5 |
| Python | 3.10 | system Python |

Newer versions are likely to work but were not tested. The NGHDL patches
in section 4 target the file layout of eSim 2.5; on a different release
the line numbers will differ, though the bugs and their fixes are
described well enough to reapply by hand.

---

## 2. Install eSim

Download and install eSim 2.5 from <https://esim.fossee.in/downloads>
following FOSSEE's instructions for Ubuntu. Confirm it launches:

```bash
esim
```

Then install NGHDL from within eSim, or run its installer directly. NGHDL
builds a patched ngspice, so this step takes a while and pulls in a large
source tree at `~/nghdl-simulator`.

---

## 3. Fix the missing PyQt5

NGHDL's GUI fails silently if PyQt5 is present only inside eSim's virtual
environment. Install it for the interpreter NGHDL actually runs under:

```bash
pip3 install PyQt5
```

Symptom if skipped: running `nghdl` returns to the prompt with no window
and no error.

---

## 4. Apply the patches

Five defects in eSim 2.5 and NGHDL block this project. Four have scripted
fixes in `tools/`; the fifth is avoided by how the sources are stored.

```bash
cd <repo>/tools
python3 patch_esim_microcontroller.py
python3 patch_nghdl_multifile.py
python3 patch_nghdl_ghdl_order.py
python3 patch_nghdl_no_gtkwave.py
```

Each script is idempotent and saves the original alongside as `.orig`.

**4.1 `patch_esim_microcontroller.py`**
eSim crashes with `UnboundLocalError: attr_microcontroller` when opening
any project whose `_Previous_Values.xml` predates microcontroller support
— including eSim's own bundled examples.

**4.2 `patch_nghdl_multifile.py`** — the important one
NGHDL's generated `start_server.sh` analyses a fixed list containing
exactly one uploaded VHDL file. Any model split across several files
cannot be built. A CAN controller is naturally ten files, so without this
patch the project is impossible. The fix replaces the fixed list with
GHDL make mode, which resolves dependency order itself:

```
ghdl -i *.vhdl &&
ghdl -m -Wl,ghdlserver.o <entity>_tb &&
```

**4.3 `patch_nghdl_ghdl_order.py`**
The generated script analysed sources in shell glob order, which is
locale dependent and violates VHDL's requirement that a package be
analysed before anything using it. Fails with `unit package
"vhpi_foreign" has not been analyzed`, then a socket connection timeout.

**4.4 `patch_nghdl_no_gtkwave.py`**
NGHDL launches GTKWave after every run, one window per model instance.
Four nodes means four windows on every simulation. The VCD is still
written; open it manually when wanted.

**4.5 The entity parser and comments — no patch, avoided by design**
NGHDL's `model_generation.py` scans every line of the uploaded file for
the substrings `port` and `end`, including inside comments, and corrupts
its port scan if it finds them. Our header once contained the phrase
"reformat the port list" and produced `Please check the in/out direction
of your port`.

This is why `nghdl_model/` exists: comment-stripped copies of
`vhdl/src/`. **Edit `vhdl/src/`, never `nghdl_model/`.**

---

## 5. Run the VHDL testbenches

GHDL only; no eSim needed.

```bash
cd <repo>/vhdl
python3 ../tools/crc15_ref.py      # generates crc_vectors.txt
python3 ../tools/frame_ref.py      # generates frame_vectors.txt
ghdl -i src/*.vhdl tb/*.vhdl
for f in tb/tb_*.vhdl; do
    m=$(basename "$f" .vhdl)
    ghdl -m "$m" && ./"$m" --stop-time=30ms
done
```

The two Python scripts must run first: four testbenches read vector files
produced by the reference models, and those files are deliberately not
committed because they are derived.

Expected: **20 of 20 pass.**

`vhdl/scripts/run.sh <module>` is the development loop for a single
module, but it assumes `tb_<x>.vhdl` pairs with `src/<x>.vhdl`. That does
not hold for the integration testbenches (`tb_node`, `tb_skew`, `tb_arb`,
`tb_ack`, `tb_probe`, `tb_bench`, `tb_node_err`, `tb_stuff_rt`), which
exercise `can_node` and multi-module behaviour. Use the loop above for
those.

---

## 6. Run the physical-layer regression

ngspice only.

```bash
cd <repo>/spice
bash run_phy_regression.sh
```

Expected: **18 of 18 pass.** Tolerances are 0.1 per cent on voltages and
1 per cent on times. This is the guard on `docs/phy_spec.md`: if a
parameter in the transceiver model changes, this fails.

---

## 7. Restore the eSim project

eSim keeps projects in its own workspace and records that path in its
configuration, which is why the live project is not stored in this repo.
A complete copy is, in `esim_project/`.

```bash
mkdir -p ~/eSim-Workspace/CAN_Bus_MixedSignal
cp -r <repo>/esim_project/* ~/eSim-Workspace/CAN_Bus_MixedSignal/
```

---

## 8. Load the controller into NGHDL

```bash
nghdl
```

In the NGHDL window:

1. **Upload** the top entity: `nghdl_model/can_node_top.vhdl`
2. **Add Files** and select the other nine files in `nghdl_model/`
3. Build

This produces the `can_node_top` code model that the netlist instantiates
as `U3` and `U4`. Without the multi-file patch from section 4.2 this step
fails.

---

## 9. Simulate

```bash
cd ~/eSim-Workspace && esim
```

1. **Double-click** `CAN_Bus_MixedSignal` in the Projects tree. Single
   clicking selects without loading; the log must show
   `The current project is: ...`
2. Click the **purple ▶** (third icon down the left toolbar)
3. Answer **Yes** to "Do you want Ngspice plots?"

Expect several minutes. Cost scales with the number of digital events
crossing the analog/digital boundary, because each one is a socket round
trip to the GHDL server — not with the complexity of the VHDL.

**Do not click the Ki→Ng icon** (second down) unless you intend to
regenerate the netlist. It overwrites `CAN_Bus_MixedSignal.cir`.

### Plotting from ngspice

eSim opens ngspice with the `.raw` file as an argument, which ngspice
cannot parse as a netlist; it reports `No circuit loaded!`. Load it
properly at the prompt:

```
load ~/eSim-Workspace/CAN_Bus_MixedSignal/CAN_Bus_MixedSignal.raw
plot v(x1.canh) v(x1.canl)
plot v(x1.canh)-v(x1.canl)
set hcopydevtype=svg
hardcopy out.svg v(x1.canh) v(x1.canl)
```

`plot` accepts expressions. **`meas` does not** — `meas tran
v(canh)-v(canl)` fails silently and returns 0. Two days were lost to that.
ngspice also lowercases node names.

---

## 10. Regenerate the documents

```bash
cd <repo>
python3 tools/make_abstract.py
```

The technical report has **no generator**. It was produced with ReportLab
and the script was not kept. Later corrections were applied directly to
the PDF's content streams by `tools/patch_report_skew.py`, which works
but constrains replacements to the same line length. Any substantial edit
means rebuilding it from scratch.

---

## 11. Traps worth knowing before you start

Recorded because each cost real time.

- **Digital event nodes are not analog vectors.** `meas tran v(busy0_d)`
  silently returns 0 for a node driven by a `dac_bridge`. Nothing is
  wrong with the design.
- **Unresolved VHDL types allow one driver only.** `boolean` and
  `integer` signals driven from two processes fail at elaboration. This
  bug was hit twice, a day apart.
- **A truncated simulation can report PASS.** A stop time shorter than
  the testbench needs ends the run before the summary prints, and the
  harness sees success. Every testbench now has a timeout guard process.
- **Check that a measurement can distinguish pass from fail.** A window
  spanning the wrong interval returned the same value whether the fix was
  applied or not.
- **eSim reads the legacy Spice-format netlist export**, not KiCad 6's
  S-expression format. The obvious "KiCad" tab produces a file eSim
  cannot parse, with no error — just empty Source Details.
- **eSim double-applies unit suffixes.** Entering `100e-9` with unit
  "sec" emits `.tran 100e-9e-00`.
- **KiCad symbol libraries are Y-up, schematics are Y-down.** Absolute
  pin position is `(px + lx, py − ly)`.
