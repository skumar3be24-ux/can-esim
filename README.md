# CAN 2.0A/B Protocol — Circuit-Level Modelling & Verification in eSim

Complete Controller Area Network node — physical layer and protocol controller —
modelled and verified at circuit level using open-source EDA tools.

**FOSSEE eSim Semester Long Internship, Autumn 2026 — Task 2**

---

## What this is

A mixed-signal simulation of a CAN bus in which:

- The **physical layer** is a real analog circuit in ngspice — differential CANH/CANL pair, 120 Ω termination at both ends, switch-based drivers, differential comparator with hysteresis
- The **protocol controller** is VHDL — bit timing with resynchronisation, framing, bit stuffing, CRC-15, arbitration, acknowledgement, error management
- The two are joined through **NGHDL**, which compiles VHDL into an XSPICE code model that ngspice can instantiate

CAN was chosen deliberately over UART/SPI/I²C. Its central mechanism — **non-destructive bitwise arbitration** — is a direct consequence of the bus being an electrical *wired-AND*: recessive (logic 1) is passive, dominant (logic 0) is actively driven and physically overrides it. Arbitration cannot be demonstrated without a correct analog bus model, which makes this inherently a mixed-signal project rather than a digital one with decorative analog attached.

## Status

| Phase | Days | State |
|---|---|---|
| 0 — Environment & de-risking | 1–5 | in progress |
| 1 — VHDL competency | 6–12 | not started |
| 2 — Analog physical layer | 13–22 | not started |
| 3 — Bit timing & synchronisation | 23–28 | not started |
| 4 — Transmit path | 29–38 | not started |
| 5 — Receive path | 39–45 | not started |
| 6 — Error management | 46–56 | not started |
| 7 — Node integration | 57–63 | not started |
| 8 — Multi-node & arbitration | 64–70 | not started |
| 9 — Advanced studies | 71–76 | not started |
| 10 — Verification campaign | 77–81 | not started |
| 11 — Documentation & submission | 82–86 | not started |

See `LOG.md` for the day-by-day record.

## Key design parameters

| Parameter | Value |
|---|---|
| Bit rate | 125 kbit/s |
| Nominal bit time | 8.000 us |
| Time quanta per bit | 16 (500 ns each) |
| Segments SYNC / PROP / PS1 / PS2 | 1 / 5 / 6 / 4 tq |
| Sample point | 75.00% (tq 12) |
| SJW | 4 tq |
| Oscillator tolerance (derived) | 0.98% |
| Max bus length (derived) | 220 m |
| Dominant levels | CANH 3.5 V, CANL 1.5 V, Vdiff 2.0 V |
| Recessive levels | both 2.5 V, Vdiff 0 V |
| Driver on-resistance | 45.0 ohm |
| Termination | 120 ohm x2 -> 60 ohm differential |
| CRC-15 polynomial | 0x4599 |

Every parameter is derived from first principles in `docs/roadmap.md` Part 3.

## Repository layout

```
docs/       roadmap, handoff prompt, measurements, waveforms, schematics, report
vhdl/src    design modules
vhdl/tb     testbenches (self-checking)
vhdl/scripts  run.sh, regress.sh
spice/      standalone ngspice netlists for PHY development
python/ref  independent reference models (CRC, frame encoder)
python/vectors  golden test vectors
esim/       eSim schematic sources
```

## Toolchain

| Tool | Version |
|---|---|
| eSim | 2.5 |
| ngspice | 35 (NGHDL-patched) |
| GHDL | 4.1.0 LLVM |
| GTKWave | 3.3.104 |
| KiCad | 6.0 |
| Ubuntu | 22.04.5 LTS |

## Reproducing results

**VHDL modules** — fast loop, no eSim required:

```bash
cd vhdl
./scripts/run.sh <module_name> <stop_time>     # e.g. ./scripts/run.sh can_crc15 200us
./scripts/regress.sh                            # full regression suite
```

**Analog PHY** — standalone ngspice:

```bash
cd spice
ngspice -b phy_dc.cir
```

**Mixed-signal** — eSim: open the project in `esim/`, then
KiCad-to-Ngspice -> Convert -> Simulate.

## Verification approach

Three levels, each catching a different class of defect:

| Level | Method | Catches |
|---|---|---|
| Unit | Self-checking GHDL testbench per module | Logic errors, boundary conditions |
| Integration | Multi-module GHDL testbenches | Interface and handshake errors |
| System | Mixed-signal eSim simulations | Analog/digital interaction, real bus behaviour |

Every test has a **predicted** value derived analytically and a **measured** value from
simulation. Results are recorded in `docs/measurements.md`.

## Documentation

- `docs/roadmap.md` — complete 86-day plan: protocol reference, architecture, all derivations, failure catalogue, 71-test verification matrix, VHDL module specs, SPICE netlists
- `docs/handoff.md` — context prompt for resuming work in a new session
- `docs/measurements.md` — predicted vs measured for every test
- `LOG.md` — daily development record

## License

Educational project submitted to FOSSEE, IIT Bombay.
