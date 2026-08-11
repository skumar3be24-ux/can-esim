# CAN Protocol — Complete Circuit-Level Modelling & Verification in eSim
## Master Roadmap (Unconstrained Edition)

**Project:** FOSSEE eSim Semester Long Internship, Autumn 2026 — Task 2
**Author:** Vlsi Integration · vlsiintegration@gmail.com
**Platform:** Ubuntu 22.04.5 LTS (VirtualBox), eSim 2.5, ngspice-35 (NGHDL), GHDL 4.1.0, GTKWave 3.3.104
**Plan length:** 86 working days, phase-structured, ~3 h/day (~260 hours)
**Assumed starting point:** beginner VHDL, sound digital electronics fundamentals
**Document version:** 2.0 — supersedes v1.0 (`CAN_eSim_Roadmap.md`)

---

## WHAT CHANGED FROM VERSION 1.0

Version 1.0 was written under a 28-day / 70-hour budget. Several decisions in it were compromises forced by that budget, not engineering judgements. With the constraint removed:

| Item | v1.0 (time-limited) | v2.0 (this document) | Why |
|---|---|---|---|
| Time quanta per bit | 8 tq | **16 tq** | 8 tq gives 12.5%-of-bit resynchronisation granularity — too coarse for a credible sync demonstration. 16 tq gives 6.25% and allows SJW = 4. |
| Resynchronisation | **Omitted** (bug — SJW was specified but never used) | Fully implemented + measured | The task explicitly names *synchronisation* as an evaluation criterion |
| Oscillator tolerance | Not analysed | Derived (0.98%) and demonstrated pass/fail | Turns "timing is correct" into a measured result |
| Bus model | Lumped capacitance only | Lumped **and** transmission-line (220 m) | Lets you demonstrate *why* PROP_SEG exists |
| Frame types | Standard 2.0A only | Standard + **Extended 2.0B** + **Remote** | Completeness; also enables the standard-beats-extended arbitration demo |
| Error handling | Detection only | Detection + **error frames + TEC/REC + bus-off + recovery** | This is half of what a real CAN controller does |
| Retransmission | Out of scope | Implemented | Makes the arbitration demo complete — the loser actually retries |
| Overload frames | Out of scope | Implemented | Small addition once error frames exist |
| Acceptance filtering | Out of scope | Implemented (ID + mask) | Makes the node a realistic controller, not just a decoder |
| Testbenches | Manual waveform inspection | **Self-checking with `assert`** + regression script | Manual inspection does not scale to 40+ tests |
| Backup / VCS | **Omitted** (bug) | Day 1, mandatory | Single-VM projects die |
| Bit rate | 125 kbit/s only | 125 k / 250 k / 500 k / 1 M analysed | Produces the bus-length vs bit-rate trade-off study |

Three of those — resynchronisation, backup, and the stuff/stall handshake — were genuine oversights in v1.0, not trade-offs. They are corrected here.

---

# TABLE OF CONTENTS

**PART 0** — Orientation: what this project is and how it is built
**PART 1** — CAN protocol reference (complete, for this project)
**PART 2** — System architecture and design decisions
**PART 3** — Complete parameter set with every calculation
**PART 4** — Toolchain reference
**PART 5** — Failure catalogue (every expected problem and its fix)
**PART 6** — Day-by-day plan, Days 1–86
**PART 7** — Verification campaign and evidence matrix
**PART 8** — Documentation and submission
**APPENDIX A** — VHDL crash course
**APPENDIX B** — SPICE netlists
**APPENDIX C** — VHDL module specifications
**APPENDIX D** — Command cheat sheet
**APPENDIX E** — Reference tables (CRC vectors, timing tables, frame maps)
**APPENDIX F** — Glossary

---

# PART 0 — ORIENTATION

## 0.1 What you are actually building

A **complete, working CAN 2.0A/B controller and physical layer, simulated at circuit level in eSim**, together with the evidence that it behaves correctly.

Concretely, at the end you will have:

- An **analog physical layer** in ngspice: differential CANH/CANL bus, correct dominant/recessive levels, proper termination, realistic edge rates, and — for the long-bus studies — a genuine transmission-line model with propagation delay
- A **digital protocol controller** in VHDL: bit timing with resynchronisation, framing, bit stuffing, CRC-15, arbitration, acknowledgement, acceptance filtering, and full error management including error frames, error counters and bus-off recovery
- The two joined through **NGHDL** into a single mixed-signal simulation
- **Three or four nodes** on one bus, demonstrating non-destructive bitwise arbitration, acknowledgement, error signalling and retransmission
- A **verification campaign**: ~45 directed tests, each with a captured waveform and a measured number compared against a predicted number

Not a PCB, not firmware, not silicon. A simulation — and the proof that the simulation is right.

## 0.2 Why CAN, and why this is the right project for eSim

The task permits any communication protocol. UART, SPI and I²C are the common choices, and all three share a weakness for this brief: **they can be demonstrated entirely in the digital domain.** The analog layer is decorative — you could replace the wires with ideal logic nets and nothing would change.

CAN cannot. Its central mechanism, **non-destructive bitwise arbitration**, is a direct consequence of the *electrical* behaviour of the bus:

- Recessive (logic 1) is **passive** — nobody drives it; resistors hold the line
- Dominant (logic 0) is **actively driven** and physically overrides recessive
- Therefore the bus performs a **wired-AND** across every transmitter simultaneously

You cannot demonstrate CAN arbitration without modelling the analog bus correctly. That makes this an *inherently* mixed-signal project, which maps exactly onto what eSim is for and onto the task's stated criteria:

> *"Can include analog, digital or mixed signal together as per the user analysis"*
> *"Proper verification of timing, synchronization, and errors (if applicable)"*

CAN lets you satisfy all of that structurally rather than by addition.

## 0.3 How it is built — the three domains

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                      ANALOG DOMAIN — solved by ngspice                       ║
║                                                                              ║
║   CANH ●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━● CANH   ║
║        │        │              │              │              │              ║
║      120Ω   [Node A drv]  [Node B drv]  [Node C drv]   bias 10k×2   120Ω     ║
║        │        │              │              │           to 2.5V   │       ║
║   CANL ●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━● CANL   ║
║                                                                              ║
║   Each driver: two 45 Ω switches (VCC→CANH, CANL→GND)                        ║
║   Each receiver: differential comparator, 0.7 V threshold, ±0.2 V hysteresis ║
║                                                                              ║
║   >>>>> THE WIRED-AND IS PRODUCED HERE BY PHYSICS, NOT BY LOGIC <<<<<        ║
╚══════════════════════════════════════════════════════════════════════════════╝
              ▲ dac_bridge (digital→analog)   │ adc_bridge (analog→digital)
              │                               ▼
╔══════════════════════════════════════════════════════════════════════════════╗
║                 EVENT DOMAIN — XSPICE code models (built in)                 ║
║      adc_bridge · dac_bridge · digital clock · reset · d_source              ║
╚══════════════════════════════════════════════════════════════════════════════╝
              ▲                               │
              │                               ▼
╔══════════════════════════════════════════════════════════════════════════════╗
║              VHDL DOMAIN — your code, compiled by GHDL, wrapped by NGHDL     ║
║                                                                              ║
║   can_node                                                                   ║
║     ├── can_bit_timing      16 tq/bit, hard sync + resynchronisation (SJW)   ║
║     ├── can_crc15           CRC-15, polynomial 0x4599                        ║
║     ├── can_stuffer         insert stuff bit after 5 identical               ║
║     ├── can_destuffer       remove stuff bits, detect stuff error            ║
║     ├── can_tx_fsm          frame serialiser + arbitration monitor           ║
║     ├── can_rx_fsm          frame deserialiser + CRC check + ACK             ║
║     ├── can_filter          acceptance filter (ID + mask)                    ║
║     └── can_error_mgmt      error frames, TEC/REC, error states, bus-off     ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

**The central design insight:** you never write arbitration *logic*. The analog domain produces the wired-AND for free. The VHDL merely has to *notice* — one comparison, once per bit, at the sample point:

```vhdl
if (tx_bit = '1') and (rx_bit = '0') then   -- I sent recessive, bus is dominant
    arb_lost <= '1';                        -- someone with higher priority is talking
end if;
```

That is the whole of arbitration. Everything else in this project exists to make that one comparison meaningful.

## 0.4 The five rules that keep this project out of trouble

**Rule 1 — Never debug VHDL inside eSim.**
The eSim round trip (regenerate NGHDL model → regenerate KiCad symbol → restart eSim → re-place symbol → KiCad-to-Ngspice → simulate) is 5–15 minutes and fails in opaque ways. The GHDL round trip is 10 seconds with a full waveform. Develop and verify every module in GHDL + GTKWave; bring it into eSim only when it is *finished*. Phases 3–6 of this plan barely open eSim at all.

**Rule 2 — Freeze the port list before generating any NGHDL model.**
Every port change costs a full regeneration cycle. Day 58 exists solely to freeze `can_node`'s interface before Day 59 generates the model.

**Rule 3 — Every test is self-checking.**
A testbench that requires you to squint at a waveform does not scale to 45 tests and will not catch a regression on day 70. Use `assert ... report ... severity error;`. Waveforms are for *debugging* and for *evidence*, not for *verification*.

**Rule 4 — Commit every day.**
`git commit` at the end of every session, and push somewhere off the VM. This project lives in one VirtualBox image that has already filled its disk once.

**Rule 5 — Measure, don't assert.**
"The bit time is 8 µs" is worthless. "Measured bit time 8.00 µs ±0.01 µs against a predicted 8.00 µs, GTKWave markers at 104.00 µs and 112.00 µs" is evidence. Every claim in Part 7 has a number behind it.

## 0.5 How to read this document

Parts 1–5 are **reference** — read Part 0 and Part 2 now, skim the rest, and return to them as needed. Part 3 is the numerical contract for the whole project; Part 5 is what you consult the moment anything breaks.

Part 6 is the **plan** — work through it day by day. Each day has a Goal, Tasks, an **Exit criterion** (an objective test of doneness), and an **If stuck** escape hatch with a hard time limit.

The appendices are **lookups**.

---

# PART 1 — CAN PROTOCOL REFERENCE

*Complete for the scope of this project. Where the ISO standard has provisions we deliberately simplify, that is flagged explicitly.*

## 1.1 Physical layer

CAN transmits on two wires, **CANH** and **CANL**, and encodes each bit in the *difference* between them.

| State | CANH | CANL | V_diff | Logic | Driven? |
|---|---|---|---|---|---|
| **Recessive** | 2.5 V | 2.5 V | 0 V | **1** | No — held by bias resistors |
| **Dominant** | 3.5 V | 1.5 V | 2.0 V | **0** | Yes — actively driven |

Three consequences follow, and all of CAN's cleverness comes from them:

**(a) The bus is a wired-AND.**
```
Bus_state = TX₁ AND TX₂ AND TX₃ AND … AND TXₙ
```
One node driving dominant beats any number of nodes driving recessive.

**(b) Collisions are non-destructive.** Two nodes transmitting the same bit value do not corrupt each other. Two nodes transmitting *different* values produce dominant on the bus — which is exactly one of the two transmitted values, not a corrupted third state.

**(c) Every transmitter can hear itself.** A node reads the bus at the sample point of every bit it transmits. If what it reads differs from what it sent, it has learned something — either it lost arbitration, or an error occurred.

**Differential signalling** also gives strong common-mode noise rejection: interference couples equally onto both wires and cancels in the difference. You will demonstrate this on Day 19.

## 1.2 Arbitration — the mechanism this project exists to demonstrate

When multiple nodes begin transmitting simultaneously, all of them send their identifier MSB-first. At every bit, each transmitting node:

1. Drives its bit onto the bus
2. Samples the actual bus level at the sample point
3. Compares:

| Sent | Read | Meaning | Action |
|---|---|---|---|
| 0 (dominant) | 0 | I am driving; still winning | continue |
| 1 (recessive) | 1 | Nobody is driving dominant; still winning | continue |
| 1 (recessive) | 0 | **Someone else is driving dominant** | **lost arbitration → become receiver** |
| 0 (dominant) | 1 | Physically impossible unless faulty | **bit error** |

Because dominant = 0 and comparison proceeds MSB-first, **the numerically lowest identifier wins**.

The winner never learns there was a contest. Its frame is not delayed, corrupted or retransmitted. Losers switch to receiver mode mid-frame, receive the winner's message correctly, and retry once the bus is idle.

**Arbitration field boundaries:**
- Standard frame (2.0A): SOF + 11 ID bits + RTR — **13 bits**
- Extended frame (2.0B): SOF + 11 ID_A bits + SRR + IDE + 18 ID_B bits + RTR — **33 bits**

**Priority rules that emerge from the bit pattern:**
1. Lower identifier wins
2. Data frame beats remote frame with the same ID (RTR: 0 vs 1)
3. **Standard frame beats extended frame with the same 11-bit base ID** — because at the position after the base ID, the standard frame sends RTR (dominant for a data frame) while the extended frame must send SRR (always recessive)

You will demonstrate rules 1 and 3 explicitly (Days 66–67).

## 1.3 Frame formats

### 1.3.1 Standard data frame (CAN 2.0A, 11-bit identifier)

```
 ┌───┬─────────────┬───┬───┬───┬──────┬──────────┬────────┬───┬───┬───┬───────┬─────┐
 │SOF│ Identifier  │RTR│IDE│r0 │ DLC  │   Data   │ CRC-15 │CRC│ACK│ACK│  EOF  │ IFS │
 │   │  11 bits    │   │   │   │4 bits│ 0-64 bit │        │del│slt│del│7 bits │3 bit│
 └───┴─────────────┴───┴───┴───┴──────┴──────────┴────────┴───┴───┴───┴───────┴─────┘
   1        11       1   1   1     4       16        15     1   1   1     7      3
  └────── ARBITRATION FIELD (13) ─────┘
  └──────────────── BIT STUFFING APPLIES (50 bits) ────────────────┘
  └──────────── CRC COVERAGE (35 bits) ──────────┘
```

### 1.3.2 Extended data frame (CAN 2.0B, 29-bit identifier)

```
 ┌───┬──────────┬───┬───┬──────────┬───┬──┬──┬─────┬────────┬──────┬───┬───┬───┬─────┬───┐
 │SOF│ ID_A(11) │SRR│IDE│ ID_B(18) │RTR│r1│r0│ DLC │  Data  │CRC-15│CRC│ACK│ACK│ EOF │IFS│
 └───┴──────────┴───┴───┴──────────┴───┴──┴──┴─────┴────────┴──────┴───┴───┴───┴─────┴───┘
   1       11     1   1      18      1  1  1    4      16      15    1   1   1    7    3
  └───────────── ARBITRATION FIELD (33) ────────────┘
  └────────────────────── BIT STUFFING (70 bits) ────────────────────┘
  └───────────────── CRC COVERAGE (55 bits) ───────────┘
```

- **SRR** (Substitute Remote Request) — always recessive; occupies the RTR position of a standard frame, which is why standard frames win against extended frames with the same base ID
- **IDE** — 0 = standard, 1 = extended
- **r1, r0** — reserved, transmitted dominant

### 1.3.3 Remote frame

Identical to a data frame except:
- **RTR = 1** (recessive)
- **No data field**, regardless of DLC
- DLC indicates how many bytes are *requested*

### 1.3.4 Error frame

```
 ┌────────────────────────────┬──────────────────────┐
 │      ERROR FLAG            │   ERROR DELIMITER    │
 │ 6 dominant  (error-active) │   8 recessive bits   │
 │ 6 recessive (error-passive)│                      │
 └────────────────────────────┴──────────────────────┘
    6 to 12 bits (superposition)          8 bits
```

An error-active node that detects an error transmits **6 dominant bits**. This deliberately violates the bit-stuffing rule, so every other node also detects an error and transmits its own flag — the flags superpose, producing 6–12 dominant bits total. Then 8 recessive delimiter bits. Total: **14 to 20 bit times**.

An error-**passive** node transmits 6 *recessive* bits, which do not disturb other traffic — this is how a faulty node is progressively silenced without taking the bus down.

### 1.3.5 Overload frame

Structurally identical to an error frame (6 dominant + 8 recessive delimiter) but transmitted during the intermission, to request a delay before the next frame.

### 1.3.6 Field value reference

| Field | Bits | Value / meaning |
|---|---|---|
| SOF | 1 | Always `0` (dominant). Falling edge synchronises all receivers. |
| Identifier | 11 or 11+18 | Message priority and content label |
| SRR | 1 | Extended only. Always `1`. |
| IDE | 1 | `0` = standard, `1` = extended |
| RTR | 1 | `0` = data frame, `1` = remote frame |
| r0, r1 | 1 each | Reserved. Transmit `0`. |
| DLC | 4 | Data byte count, 0–8. Values 9–15 treated as 8. |
| Data | 0–64 | Payload, MSB first, byte 0 first |
| CRC-15 | 15 | See §1.5 |
| CRC delimiter | 1 | Always `1` |
| ACK slot | 1 | Transmitter sends `1`; any receiver with valid CRC overwrites with `0` |
| ACK delimiter | 1 | Always `1` |
| EOF | 7 | `1111111` |
| IFS / Intermission | 3 | `111` — minimum gap before next frame |

**The ACK mechanism deserves attention** — it is the second place the wired-AND does real work. The transmitter sends recessive; *any* receiver that validated the CRC drives that same bit slot dominant; the transmitter reads dominant and knows at least one node heard it. No addressing, no reply frame, no handshake. If it reads recessive, that is an **ACK error**.

## 1.4 Bit stuffing

CAN has no clock wire. Receivers recover timing from bus edges. Long runs of identical bits produce no edges and receivers drift.

**Rule:** after **5 consecutive bits of identical value**, the transmitter inserts one bit of **opposite** polarity. The receiver removes it. Stuff bits are not part of the message and are **not included in the CRC calculation**.

**Applies to:** SOF, identifier, control field, data field, CRC sequence.
**Does not apply to:** CRC delimiter, ACK slot, ACK delimiter, EOF, IFS, error frames, overload frames. These are *fixed-form* fields.

**Worst-case stuff-bit count** over an n-bit stuffed region:

```
max_stuff = floor((n − 1) / 4)
```

Derivation: the worst case alternates 5 identical bits then a forced stuff bit; each group of 5 original bits generates 1 stuff bit, but the first stuff bit can only occur after bit 5, and the inserted bit resets the counter — giving one stuff bit per 4 subsequent original bits.

| Frame type | Stuffed region | Max stuff bits |
|---|---|---|
| Standard, DLC=2 | 50 bits | `floor(49/4)` = **12** |
| Standard, DLC=8 | 98 bits | `floor(97/4)` = **24** |
| Extended, DLC=2 | 70 bits | `floor(69/4)` = **17** |
| Extended, DLC=8 | 118 bits | `floor(117/4)` = **29** |

**Stuff error:** a receiver that observes **6 consecutive identical bits** inside a stuffed field has detected an error. This is also precisely how an error flag (6 dominant bits) forces every node to notice.

## 1.5 CRC-15

**Generator polynomial:**
```
G(x) = x¹⁵ + x¹⁴ + x¹⁰ + x⁸ + x⁷ + x⁴ + x³ + 1
```

**Coefficient vector** (x¹⁴ … x⁰, the x¹⁵ term is implicit):
```
bit:    14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
value:   1  0  0  0  1  0  1  1  0  0  1  1  0  0  1
hex:                          0x4599
```

Verify: `100 0101 1001 1001₂` = `0x4599`. Reading nibbles from the MSB with a leading 0 pad: `0100 0101 1001 1001` = `0x4599` ✓

**Properties:** Hamming distance 6 — detects up to 5 randomly distributed bit errors, all burst errors up to 15 bits, and all odd numbers of errors.

**Algorithm** (register initialised to 0, MSB-first):
```
for each bit d in covered_bits:
    crc_next = d XOR crc[14]
    crc = (crc << 1) AND 0x7FFF
    if crc_next == 1:
        crc = crc XOR 0x4599
```

**Coverage:** SOF through the end of the data field, **excluding stuff bits**.

| Frame type | CRC coverage |
|---|---|
| Standard, DLC=2 | 1+11+1+1+1+4+16 = **35 bits** |
| Standard, DLC=8 | 1+11+1+1+1+4+64 = **83 bits** |
| Extended, DLC=2 | 1+11+1+1+18+1+1+1+4+16 = **55 bits** |
| Extended, DLC=8 | 1+11+1+1+18+1+1+1+4+64 = **103 bits** |

## 1.6 Bit timing and synchronisation

### 1.6.1 Segment structure

Each bit is divided into **time quanta (tq)** — equal, indivisible time slices — grouped into four segments:

```
│←─────────────────── NOMINAL BIT TIME (16 tq) ───────────────────→│
│         │                     │                    │             │
│ SYNC_SEG│      PROP_SEG       │    PHASE_SEG1      │ PHASE_SEG2  │
│  (1 tq) │       (5 tq)        │      (6 tq)        │   (4 tq)    │
│         │                     │                    ▲             │
│    ▲    │                     │              SAMPLE POINT        │
│  edges  │                     │                  (75%)           │
│ expected│                     │                                  │
│  here   │←── may be LENGTHENED by up to SJW ──→│←─ may be SHORTENED
                                                     by up to SJW ─→│
```

| Segment | Fixed? | Purpose |
|---|---|---|
| **SYNC_SEG** | Always 1 tq | The window in which bit edges are expected. Synchronisation aligns edges to here. |
| **PROP_SEG** | Programmable | Compensates the *round-trip* physical delay: signal must reach the furthest node and its response must return within the same bit. **This is what limits bus length.** |
| **PHASE_SEG1** | Programmable | Lengthened on resynchronisation when an edge arrives *late*. |
| **PHASE_SEG2** | Programmable | Shortened on resynchronisation when an edge arrives *early*. Also provides the information-processing time. |

The **sample point** is the boundary between PHASE_SEG1 and PHASE_SEG2. It is the *only* instant at which the bus value is read.

### 1.6.2 Hard synchronisation

Occurs **once per frame**, on the falling (recessive→dominant) edge of SOF. The bit-time counter is restarted so that the edge falls inside SYNC_SEG. No SJW limit — this is an unconditional restart.

### 1.6.3 Resynchronisation

Occurs on **every** recessive→dominant edge *within* a frame (except when the node is itself transmitting a dominant bit). Corrects for accumulated clock drift between transmitter and receiver.

Define the **phase error** `e`, in tq, as the position of the edge relative to SYNC_SEG:

| Condition | e | Meaning | Correction |
|---|---|---|---|
| Edge inside SYNC_SEG | `e = 0` | Perfectly aligned | none |
| Edge after SYNC_SEG, before sample point | `e > 0` | Edge arrived **late** — we are running fast | **lengthen PHASE_SEG1** by `min(e, SJW)` |
| Edge after the sample point | `e < 0` | Edge arrived **early** — we are running slow | **shorten PHASE_SEG2** by `min(|e|, SJW)` |

**SJW (Synchronisation Jump Width)** bounds the correction per edge:
```
SJW ≤ min(PHASE_SEG1, 4, PHASE_SEG2)
```
The absolute cap of 4 tq is fixed by the standard.

**This is where v1.0 was wrong** — it defined SJW and never implemented the mechanism. Days 25–27 of this plan build and measure it.

### 1.6.4 Oscillator tolerance

The maximum permitted clock frequency deviation `df` for a node is bounded by two conditions (ISO 11898-1):

```
Condition 1 (resynchronisation capability):
    df ≤ SJW / (2 × 10 × NBT)

Condition 2 (phase-segment margin):
    df ≤ min(PHASE_SEG1, PHASE_SEG2) / (2 × (13 × NBT − PHASE_SEG2))
```
where NBT = nominal bit time in tq. Both are evaluated in §3.3 for our design.

## 1.7 Error detection — the five mechanisms

| # | Error | Detected by | How |
|---|---|---|---|
| 1 | **Bit error** | Transmitter | Reads back a level different from what it sent (excluding arbitration field and ACK slot) |
| 2 | **Stuff error** | Any node | 6 consecutive identical bits in a stuffed field |
| 3 | **CRC error** | Receiver | Computed CRC ≠ received CRC |
| 4 | **Form error** | Any node | A fixed-form field contains the wrong value (CRC delim, ACK delim, EOF) |
| 5 | **ACK error** | Transmitter | ACK slot read recessive — nobody acknowledged |

All five are implemented and demonstrated in this plan (Days 46–48).

## 1.8 Fault confinement — TEC, REC, and bus-off

Every node maintains two counters:
- **TEC** — Transmit Error Counter
- **REC** — Receive Error Counter

**Simplified increment/decrement rules** (the ISO rules have ~12 clauses; this is a faithful, documented subset):

| Event | TEC | REC |
|---|---|---|
| Transmit error detected | +8 | — |
| Receive error detected | — | +1 |
| Receiver detects error and is first to signal it | — | +8 |
| Successful transmission | −1 (floor 0) | — |
| Successful reception | — | −1 (floor 0) |

**Node states:**

| State | Condition | Behaviour |
|---|---|---|
| **Error-active** | TEC ≤ 127 **and** REC ≤ 127 | Normal. Transmits **dominant** error flags. |
| **Error-passive** | TEC > 127 **or** REC > 127 | Transmits **recessive** error flags (does not disturb the bus). Must wait an extra 8-bit suspend transmission after each frame. |
| **Bus-off** | TEC > 255 | Takes no part in bus activity. Drivers disabled. |

**Recovery from bus-off:** the node may rejoin after observing **128 occurrences of 11 consecutive recessive bits**.

```
128 × 11 = 1408 bit times = 1408 × 8 µs = 11.264 ms
```

11.264 ms is a long transient simulation. **Simulation accommodation:** the recovery threshold is made a VHDL constant, `BUSOFF_RECOVERY_COUNT`, set to **8** for simulation (8 × 11 = 88 bit times = 704 µs) and documented as a deliberate scaling. The mechanism is identical; only the count changes. State this explicitly in the report — a scaled constant with a stated reason is good engineering; an undocumented one is a defect.

## 1.9 Acceptance filtering

A real controller does not pass every frame to its host. It compares the received identifier against a configured filter:

```
accept  ⟺  (received_id XOR filter_id) AND filter_mask == 0
```

A `1` bit in the mask means "this bit must match"; a `0` means "don't care".

| Filter ID | Mask | Effect |
|---|---|---|
| `0x0A5` | `0x7FF` | Accept only exactly `0x0A5` |
| `0x0A0` | `0x7F0` | Accept `0x0A0`–`0x0AF` |
| `0x000` | `0x000` | Accept everything (promiscuous) |

Implemented on Day 44.

---

# PART 2 — ARCHITECTURE AND DESIGN DECISIONS

## 2.1 Partitioning: what goes where, and why

| Function | Domain | Rationale |
|---|---|---|
| CANH/CANL bus, termination, bias | **Analog** | Physical reality; produces the wired-AND |
| Output drivers (switches + R_on) | **Analog** | Determines dominant levels and edge rates |
| Differential receiver / comparator | **Analog** | Thresholds and hysteresis are analog properties |
| Bus capacitance / transmission line | **Analog** | Sets edge rate and propagation delay |
| Level shifting logic ↔ analog | **Event (XSPICE bridges)** | Purpose-built primitives already exist |
| Bit timing, sync, resync | **VHDL** | Sequential logic |
| Framing, stuffing, CRC | **VHDL** | Sequential logic |
| Arbitration *detection* | **VHDL** | One comparison — the *mechanism* is analog |
| Error management, TEC/REC | **VHDL** | Sequential logic |

**Anti-pattern to avoid:** modelling the wired-AND in VHDL with an `and` gate. It works, it is much easier — and it destroys the entire point of the project. The bus must be a real electrical node with real drivers, or you have built a digital simulation with decorative analog around it.

## 2.2 Node instantiation strategy

Three or four nodes are needed. Two implementation options:

| | **Approach A** — separate entities | **Approach B** — one entity, `node_sel` input |
|---|---|---|
| Structure | `can_node_a/b/c/d`, each with hardcoded ID and payload | One `can_node` with a 2-bit `node_sel` selecting from an internal constant table |
| Ports | Scalar `std_logic` only | Requires `std_logic_vector` port support |
| Models to regenerate per change | 3–4 | 1 |
| Iteration cost | High | Low |
| Risk | None | Depends on NGHDL vector support |

**Decision: Approach B, with Approach A as a pre-authorised fallback.**

Days 3–4 are dedicated to probing NGHDL's actual capabilities *before* any protocol VHDL is written. If vectors or multiple instances turn out to be unsupported, you switch to Approach A having lost one afternoon instead of three weeks. **This is the single highest-value de-risking step in the plan.**

## 2.3 Bus configurations

Two analog configurations are built and used for different purposes:

| Config | Bus model | Used for | Days |
|---|---|---|---|
| **SHORT** | Lumped 1 nF per line, negligible propagation | All protocol development and the main demonstrations | 13–16, 57–70 |
| **LONG** | Transmission line, 220 m, TD = 1.1 µs | Propagation-delay studies, PROP_SEG justification, arbitration timing margin | 17–18, 71 |

Keep both netlists. The SHORT config is the default because it simulates faster and isolates protocol behaviour from transmission-line artefacts.

## 2.4 Complete scope

### IN SCOPE

**Physical layer**
- ✅ Differential CANH/CANL, correct ISO 11898-2 levels
- ✅ 120 Ω termination at both ends, recessive bias network
- ✅ Switch-based drivers with derived on-resistance
- ✅ Differential comparator with hysteresis
- ✅ Realistic bus capacitance and edge rates
- ✅ Transmission-line model with propagation delay (220 m)
- ✅ Reflection study with mismatched termination
- ✅ Common-mode rejection demonstration
- ✅ Multi-bit-rate analysis (125 k / 250 k / 500 k / 1 M)

**Protocol — framing**
- ✅ Standard data frames (CAN 2.0A, 11-bit ID)
- ✅ Extended data frames (CAN 2.0B, 29-bit ID)
- ✅ Remote frames (RTR = 1)
- ✅ Bit stuffing and destuffing with correct stall handshake
- ✅ CRC-15 generation and verification
- ✅ ACK generation and detection

**Protocol — timing**
- ✅ 16 tq bit timing with programmable segments
- ✅ Hard synchronisation on SOF
- ✅ Resynchronisation with SJW
- ✅ Oscillator tolerance analysis and demonstration

**Protocol — arbitration**
- ✅ Non-destructive bitwise arbitration, 3+ nodes
- ✅ Standard-vs-extended priority demonstration
- ✅ Automatic retransmission after arbitration loss

**Protocol — error management**
- ✅ All five error detection mechanisms
- ✅ Error frame transmission (active and passive)
- ✅ Error flag superposition
- ✅ Overload frames
- ✅ TEC / REC counters
- ✅ Error-active / error-passive / bus-off states
- ✅ Bus-off recovery (scaled count, documented)

**Controller features**
- ✅ Acceptance filtering with ID + mask

**Verification**
- ✅ Self-checking testbenches for every module
- ✅ Regression script
- ✅ ~45-test directed verification matrix
- ✅ Every claim backed by a measured number

### OUT OF SCOPE (deliberate, documented)

- ❌ **CAN FD** — different frame format, bit-rate switching, CRC-17/21. A separate project.
- ❌ **Time-Triggered CAN (TTCAN)** — a scheduling layer above this
- ❌ **Transistor-level transceiver design** — switch-level behavioural models are the correct abstraction here; transistor-level adds convergence pain and no protocol insight
- ❌ **Physical PCB, footprints, layout**
- ❌ **Higher-layer protocols** (CANopen, J1939, OBD-II)
- ❌ **Full ISO 11898-1 fault-confinement clause set** — a documented subset is implemented (§1.8)

Each exclusion goes in the report's Limitations section with its reason. Stating boundaries clearly reads as competence.

---

# PART 3 — COMPLETE PARAMETER SET AND CALCULATIONS

> **Everything in Part 3 is the numerical contract for the project.** Every number is derived, not assumed. If you change one, re-derive the others and record why in `LOG.md`.

## 3.1 Bit rate selection

**Primary bit rate: 125 kbit/s**

| Criterion | Assessment |
|---|---|
| Standards conformance | Standard CAN rate (CiA-recommended set: 10 k, 20 k, 50 k, 125 k, 250 k, 500 k, 800 k, 1 M) |
| Industrial realism | Widely used for automotive body electronics and industrial sensor buses |
| Simulation cost | One frame ≈ 0.5 ms → a full multi-frame scenario fits in a few ms of transient |
| Bus length supported | ~220 m with our segment allocation (derived in §3.4) — realistic |
| Timing resolution | 8 µs bit time ÷ 16 tq = 500 ns tq — comfortably resolved with a 100 ns max timestep |

```
Nominal bit time:   T_bit = 1 / 125 000 = 8.000 µs
```

Secondary rates (250 k, 500 k, 1 M) are analysed in §3.5 for the bit-rate scaling study but the deliverable design is 125 kbit/s.

## 3.2 Time quanta and segment allocation

**Time quanta per bit: 16**

Why 16 rather than 8:

| | 8 tq | 16 tq |
|---|---|---|
| tq duration | 1000 ns | **500 ns** |
| Max SJW | 2 tq = 25% of bit | **4 tq = 25% of bit** |
| Resync granularity | 12.5% of bit | **6.25% of bit** |
| Oscillator tolerance (§3.3) | ~0.49% | **~0.98%** |
| VHDL clock | 1 MHz | 2 MHz |
| Simulation event rate | 1× | 2× |

16 tq **doubles** the tolerable oscillator error and **halves** the resynchronisation granularity, for 2× the digital event count — which is a trivial cost at 125 kbit/s. v1.0 chose 8 tq purely to save simulation time under a deadline. That trade is not worth making here.

```
Time quantum:      T_tq = T_bit / 16 = 8.000 µs / 16 = 500.0 ns
tq clock frequency: f_tq = 1 / 500 ns = 2.000 MHz
```

**Segment allocation** — constraint: `SYNC + PROP + PS1 + PS2 = 16 tq`

| Segment | tq | Time | Justification |
|---|---|---|---|
| SYNC_SEG | **1** | 500 ns | Fixed at 1 tq by the standard |
| PROP_SEG | **5** | 2500 ns | Supports 220 m bus — see §3.4 |
| PHASE_SEG1 | **6** | 3000 ns | Sized to place the sample point at 75% |
| PHASE_SEG2 | **4** | 2000 ns | Remainder; must be ≥ SJW and ≥ 2 tq (information processing time). Both satisfied. |
| **Total** | **16** | 8000 ns | ✓ |

**Sample point:**
```
Sample point = (SYNC_SEG + PROP_SEG + PHASE_SEG1) / 16
             = (1 + 5 + 6) / 16
             = 12 / 16
             = 0.7500  →  75.00 %

Absolute position = 12 tq × 500 ns = 6.000 µs after bit start
```

**Why 75% and not the CiA-recommended 87.5%?**

This is a real trade-off and you should be able to defend it:

| Sample point | Segment split | Bus length | Oscillator tolerance |
|---|---|---|---|
| 87.5% | SYNC 1, PROP 11, PS1 2, PS2 2 | ~1100 m | 0.485% |
| **75.0%** | **SYNC 1, PROP 5, PS1 6, PS2 4** | **~220 m** | **0.980%** |

87.5% buys bus length; 75% buys **twice the oscillator tolerance**. For this project the deliverable is a *demonstration of resynchronisation*, and a larger tolerance band gives a much cleaner pass/fail experiment (0.5% offset works, 1.5% fails). 220 m is still a realistic bus. **Chosen: 75%.** Document the alternative in the report — showing you considered both is worth more than either choice alone.

**SJW:**
```
SJW ≤ min(PHASE_SEG1, 4, PHASE_SEG2)
    = min(6, 4, 4)
    = 4 tq
```
> **SJW = 4 tq = 2.000 µs = 25% of nominal bit time**

## 3.3 Oscillator tolerance

Applying the ISO 11898-1 conditions with NBT = 16 tq, SJW = 4, PS1 = 6, PS2 = 4:

**Condition 1 — resynchronisation capability:**
```
df ≤ SJW / (2 × 10 × NBT)
   = 4 / (2 × 10 × 16)
   = 4 / 320
   = 0.01250
   = 1.250 %
```

**Condition 2 — phase-segment margin:**
```
df ≤ min(PS1, PS2) / (2 × (13 × NBT − PS2))
   = min(6, 4) / (2 × (13 × 16 − 4))
   = 4 / (2 × (208 − 4))
   = 4 / (2 × 204)
   = 4 / 408
   = 0.009804
   = 0.9804 %
```

**Binding constraint = Condition 2:**
> **df_max = 0.98 % per node**

Interpretation, and the basis of the Day 26 experiment:

| Scenario | Relative error | Predicted result |
|---|---|---|
| Both nodes at nominal 2.000 MHz | 0% | Works |
| One node at 1.990 MHz (−0.5%) | 0.5% < 0.98% | **Works** |
| One node at 1.970 MHz (−1.5%) | 1.5% > 0.98% | **Fails** — receiver drifts, frame corrupted |
| Resynchronisation disabled, one node at −0.5% | — | **Fails** — proves resync is doing the work |

That three-way experiment is strong evidence: it demonstrates the mechanism, quantifies the boundary, and shows the boundary matches the theory.

**Hardware context (worth a sentence in the report):** a crystal oscillator gives ~0.005%, a ceramic resonator ~0.5%, an on-chip RC oscillator ~1–2%. Our 0.98% budget means CAN at these settings works with a ceramic resonator but **not** with an untrimmed internal RC — which is exactly why real CAN microcontrollers require an external crystal or resonator. This is a genuine engineering insight that falls directly out of the calculation.

## 3.4 Propagation delay and maximum bus length

PROP_SEG must cover the **round trip**: a bit must reach the most distant node *and* that node's response (a dominant bit during arbitration or the ACK) must return, all within the same bit time.

```
PROP_SEG ≥ 2 × (t_bus + t_trx)
```
where `t_bus` = one-way cable propagation delay, `t_trx` = transceiver loop delay (TX driver delay + RX comparator delay).

**Given:**
```
PROP_SEG = 5 tq = 2500 ns
t_trx    = 150 ns          (typical for a real CAN transceiver; our simulated
                            driver + comparator + bridges are faster, so this
                            is a conservative allowance)
v_prop   = 200 m/µs = 5 ns/m   (typical twisted-pair, 0.66c)
```

**Solve for maximum cable length:**
```
2500 ns ≥ 2 × (t_bus + 150 ns)
1250 ns ≥ t_bus + 150 ns
t_bus   ≤ 1100 ns
L_max   = 1100 ns / 5 ns/m = 220 m
```

> **Maximum bus length = 220 m at 125 kbit/s with this segment allocation**

**Transmission-line model parameters** for the LONG configuration:
```
Characteristic impedance:  Z₀ = 120 Ω  (matched to termination)
Propagation velocity:      v  = 2 × 10⁸ m/s

Inductance per metre:      L' = Z₀ / v = 120 / (2 × 10⁸) = 600 nH/m
Capacitance per metre:     C' = 1 / (Z₀ × v) = 1 / (120 × 2 × 10⁸) = 41.67 pF/m

Check: √(L'/C') = √(600 n / 41.67 p) = √14400 = 120 Ω  ✓
Check: 1/√(L'C') = 1/√(600 n × 41.67 p) = 1/√(2.5 × 10⁻¹⁷) = 2 × 10⁸ m/s  ✓

For 220 m:
    Total inductance:  L = 132 µH
    Total capacitance: C = 9.167 nF
    Delay:             TD = 220 m / (2 × 10⁸ m/s) = 1.100 µs
```

Note that TD = 1.100 µs = **2.2 tq** — a substantial fraction of a bit time, and precisely why PROP_SEG is 5 tq. Day 71 demonstrates arbitration failing when the bus is lengthened beyond this.

## 3.5 Bit-rate scaling study

Holding the segment ratios constant (16 tq; SYNC 1, PROP 5, PS1 6, PS2 4) and `t_trx = 150 ns`:

| Bit rate | T_bit | T_tq | f_clk | PROP_SEG | t_bus max | **L_max** |
|---|---|---|---|---|---|---|
| 125 kbit/s | 8.000 µs | 500 ns | 2 MHz | 2500 ns | 1100 ns | **220 m** |
| 250 kbit/s | 4.000 µs | 250 ns | 4 MHz | 1250 ns | 475 ns | **95 m** |
| 500 kbit/s | 2.000 µs | 125 ns | 8 MHz | 625 ns | 162.5 ns | **32 m** |
| 1 Mbit/s | 1.000 µs | 62.5 ns | 16 MHz | 312.5 ns | 6.25 ns | **1.3 m** |

Worked example for 500 kbit/s:
```
T_bit = 1/500 000 = 2.000 µs
T_tq  = 2.000 µs / 16 = 125 ns
PROP_SEG = 5 × 125 ns = 625 ns
625 ≥ 2 × (t_bus + 150)  →  312.5 ≥ t_bus + 150  →  t_bus ≤ 162.5 ns
L_max = 162.5 / 5 = 32.5 m
```

**The 1 Mbit/s row is the interesting one.** With a 150 ns transceiver loop delay, PROP_SEG has almost nothing left for cable — 1.3 m. Real 1 Mbit/s CAN reaches ~40 m only because high-speed transceivers achieve loop delays around 50 ns *and* the segment split is re-optimised toward PROP_SEG. This is a concrete, defensible conclusion from your own numbers, and it belongs in the report: **at high bit rates, transceiver delay — not cable length — dominates the timing budget.**

## 3.6 Frame lengths and simulation windows

**Nominal (unstuffed) frame lengths:**

| Frame type | Field sum | +IFS | Bit times | Duration @125k |
|---|---|---|---|---|
| Standard, DLC=2 | 60 | 3 | **63** | **504 µs** |
| Standard, DLC=8 | 108 | 3 | 111 | 888 µs |
| Extended, DLC=2 | 80 | 3 | 83 | 664 µs |
| Extended, DLC=8 | 128 | 3 | 131 | 1048 µs |
| Remote, standard, DLC=2 | 44 | 3 | 47 | 376 µs |

Verification of the standard DLC=2 sum:
```
SOF 1 + ID 11 + RTR 1 + IDE 1 + r0 1 + DLC 4 + Data 16
    + CRC 15 + CRCdel 1 + ACK 1 + ACKdel 1 + EOF 7  =  60  ✓
```

Verification of the extended DLC=2 sum:
```
SOF 1 + ID_A 11 + SRR 1 + IDE 1 + ID_B 18 + RTR 1 + r1 1 + r0 1
    + DLC 4 + Data 16 + CRC 15 + CRCdel 1 + ACK 1 + ACKdel 1 + EOF 7  =  80  ✓
```

**Worst case with bit stuffing:**

| Frame type | Stuffed region | Max stuff | Total bits | Duration |
|---|---|---|---|---|
| Standard, DLC=2 | 50 | 12 | 75 | 600 µs |
| Standard, DLC=8 | 98 | 24 | 135 | 1080 µs |
| Extended, DLC=2 | 70 | 17 | 100 | 800 µs |
| Extended, DLC=8 | 118 | 29 | 160 | 1280 µs |

**Other timed sequences:**
```
Error frame:            14 to 20 bit times  =  112 to 160 µs
Overload frame:         14 to 20 bit times  =  112 to 160 µs
Suspend transmission:   8 bit times         =  64 µs   (error-passive nodes)
Bus-off recovery (real):   128 × 11 = 1408 bit times = 11.264 ms
Bus-off recovery (scaled):   8 × 11 =   88 bit times =  704 µs
```

**Simulation windows per scenario:**

| Scenario | `.tran` | Rationale |
|---|---|---|
| Single standard frame | `100n 1.5m` | 504 µs frame + reset + margin |
| Single extended frame | `100n 2m` | 800 µs worst case + margin |
| 3-node arbitration | `100n 2.5m` | one frame + winner's frame + margin |
| Arbitration + retransmission | `100n 4m` | winner + two retries |
| Error frame + recovery | `100n 3m` | frame + error frame + retry |
| Bus-off (scaled) | `200n 20m` | 704 µs recovery × several cycles; larger max step to keep runtime sane |

**Max timestep justification:** 100 ns = 1/5 of a 500 ns time quantum → at least 5 solver points per tq, and ~80 per bit. Sufficient to resolve the 40 ns bus edges without exploding the dataset. For the 20 ms bus-off run, 200 ns is acceptable because that scenario is about counting bit times, not resolving edges.

## 3.7 Node configuration

Four nodes. IDs chosen so that arbitration losses occur at **distinct, predictable, easily-annotated bit positions**.

| Node | Type | Identifier | Binary (bit10→bit0) | Payload | Outcome |
|---|---|---|---|---|---|
| **A** | Standard | `0x0A5` | `0 0 0 1 0 1 0 0 1 0 1` | `0xA5 0x3C` | **WINS** |
| **B** | Standard | `0x123` | `0 0 1 0 0 1 0 0 0 1 1` | `0x12 0x34` | loses at ID bit 8 |
| **C** | Standard | `0x2AA` | `0 1 0 1 0 1 0 1 0 1 0` | `0x55 0xAA` | loses at ID bit 9 |
| **D** | Extended | `0x297ABCD` | base `0x0A5`, ext `0x3ABCD` | `0xDE 0xAD` | loses at SRR |

Hex → binary verification:
```
0x0A5 = 0000 1010 0101  →  low 11 bits: 000 1010 0101   ✓
0x123 = 0001 0010 0011  →  low 11 bits: 001 0010 0011   ✓
0x2AA = 0010 1010 1010  →  low 11 bits: 010 1010 1010   ✓
```

Node D's 29-bit identifier construction:
```
ID_A (11 bits, base) = 0x0A5 = 165
ID_B (18 bits, ext)  = 0x3ABCD = 240 589

Full 29-bit ID = (ID_A << 18) | ID_B
               = 165 × 262 144 + 240 589
               = 43 253 760 + 240 589
               = 43 494 349
               = 0x297ABCD                              ✓
```

### 3.7.1 Arbitration trace — Scenario 1 (A, B, C simultaneous)

| Bit | A | B | C | Bus | Event |
|---|---|---|---|---|---|
| SOF | 0 | 0 | 0 | **0** | all synchronised |
| ID bit10 | 0 | 0 | 0 | **0** | all match |
| ID bit9 | 0 | 0 | **1** | **0** | C sent 1, read 0 → **C LOSES** |
| ID bit8 | 0 | **1** | – | **0** | B sent 1, read 0 → **B LOSES** |
| ID bit7 | 1 | – | – | **1** | A uncontested |
| ID bit6..0 | A's bits | – | – | A's bits | A completes |

**Two-stage dropout, one bit apart.** Far more legible in a waveform than a simultaneous loss.

### 3.7.2 Arbitration trace — Scenario 2 (A standard vs D extended, same base ID)

| Bit | A (standard) | D (extended) | Bus | Event |
|---|---|---|---|---|
| SOF | 0 | 0 | **0** | — |
| ID bit10..0 | `00010100101` | `00010100101` | same | **identical base IDs — no resolution yet** |
| next bit | **RTR = 0** (dominant) | **SRR = 1** (recessive) | **0** | D sent 1, read 0 → **D LOSES** |

This demonstrates the standard-beats-extended priority rule at exactly the bit where the protocol intends it. Verifying this is worth more than any number of repeated simple-arbitration runs.

### 3.7.3 Acceptance filter configuration

| Node | Filter ID | Mask | Accepts |
|---|---|---|---|
| A | `0x000` | `0x000` | everything (monitor mode) |
| B | `0x0A5` | `0x7FF` | only A's frames |
| C | `0x0A0` | `0x7F0` | `0x0A0`–`0x0AF` (range demo) |
| D | `0x123` | `0x7FF` | only B's frames |

## 3.8 Analog physical layer — full derivation

### 3.8.1 Target levels

```
VCC              = 5.000 V
V_recessive      = 2.500 V  (both lines)      →  V_diff = 0.000 V
V_dominant_CANH  = 3.500 V
V_dominant_CANL  = 1.500 V                     →  V_diff = 2.000 V
```
ISO 11898-2 nominal values for a 5 V high-speed CAN transceiver.

### 3.8.2 Termination

```
R_term = 120 Ω at each end of the bus (two resistors total)

Differential load:
R_diff = (120 × 120) / (120 + 120) = 14 400 / 240 = 60.00 Ω
```

120 Ω matches the characteristic impedance of standard CAN twisted pair, suppressing reflections. Day 18 demonstrates what happens when this is wrong.

### 3.8.3 Driver on-resistance — the key calculation

The dominant driver is a pair of switches:
```
VCC ──[S_high, R_on]── CANH ──[R_diff = 60 Ω]── CANL ──[S_low, R_on]── GND
```

Required load current:
```
I = V_diff / R_diff = 2.000 V / 60.00 Ω = 33.333 mA
```

High-side switch drop and resistance:
```
V_drop_H = VCC − V_CANH = 5.000 − 3.500 = 1.500 V
R_on_H   = 1.500 V / 33.333 mA = 45.00 Ω
```

Low-side switch drop and resistance:
```
V_drop_L = V_CANL − 0 = 1.500 V
R_on_L   = 1.500 V / 33.333 mA = 45.00 Ω
```

> ## **R_on = 45.0 Ω** (both high-side and low-side)

**Independent verification — reproduce this in the report:**
```
R_total = R_on_H + R_diff + R_on_L = 45 + 60 + 45   = 150.00 Ω
I       = VCC / R_total = 5.000 / 150.00            = 33.333 mA   ✓
V_CANH  = VCC − I·R_on_H = 5.000 − 0.033333 × 45    = 3.500 V     ✓
V_CANL  = I·R_on_L       = 0.033333 × 45            = 1.500 V     ✓
V_diff  = 3.500 − 1.500                             = 2.000 V     ✓
P_drv   = VCC × I = 5.000 × 0.033333                = 166.7 mW    ✓
```

**Multiple simultaneous dominant drivers** — this *will* appear in your arbitration waveforms and you must be ready to explain it. With *n* drivers dominant in parallel:
```
R_on_effective = 45 / n
```

| n | R_on_eff | R_total | I | V_CANH | V_CANL | V_diff |
|---|---|---|---|---|---|---|
| 1 | 45.0 Ω | 150.0 Ω | 33.3 mA | 3.500 V | 1.500 V | 2.000 V |
| 2 | 22.5 Ω | 105.0 Ω | 47.6 mA | 3.929 V | 1.071 V | 2.857 V |
| 3 | 15.0 Ω | 90.0 Ω | 55.6 mA | 4.167 V | 0.833 V | 3.333 V |

Worked check for n = 3:
```
R_total = 15 + 60 + 15 = 90 Ω
I = 5.000 / 90 = 55.56 mA
V_CANH = 5.000 − 0.05556 × 15 = 5.000 − 0.833 = 4.167 V
V_CANL = 0.05556 × 15 = 0.833 V
V_diff = 3.333 V
```

The differential voltage rises above the nominal 2.0 V when several nodes drive dominant together. **This is physically correct and completely benign** — the receiver threshold is 0.9 V, so the bus still reads dominant. Explaining this in the report demonstrates that you understand your own circuit rather than having copied values.

### 3.8.4 Recessive bias network

```
R_bias = 10 kΩ from CANH to a 2.5 V reference
R_bias = 10 kΩ from CANL to the same 2.5 V reference
```

**Sizing justification:**

*Upper bound (must not disturb the dominant levels).* In the dominant state, CANH sits 1.0 V above the 2.5 V reference:
```
I_bias = (3.500 − 2.500) / 10 000 = 100 µA
Error relative to load current = 100 µA / 33.333 mA = 0.30 %
Resulting level error ≈ 0.30 % × 2.0 V = 6 mV     — negligible ✓
```

*Lower bound (must restore recessive quickly).* In the recessive state the termination resistors already tie CANH and CANL together (60 Ω differential), so the differential voltage collapses through the termination, not the bias network. The bias network only has to set the *common-mode* level, for which 10 kΩ into 2 nF of total bus capacitance gives:
```
τ_cm = 10 kΩ × 2 nF = 20 µs
```
That is slow, but it only affects the initial power-up settling, not bit-to-bit behaviour. Give the simulation 100 µs of settling before the first frame — which the plan already does (transmission starts at t = 100 µs).

### 3.8.5 Bus capacitance and edge rate (SHORT configuration)

```
C_CANH = 1 nF (CANH to GND)
C_CANL = 1 nF (CANL to GND)
```

Differential capacitance seen by the driver (series combination):
```
C_diff = (1 nF × 1 nF) / (1 nF + 1 nF) = 500 pF
```

Effective source resistance during a dominant transition — the driver's series resistance in parallel with the termination:
```
R_src = (R_on_H + R_on_L) ∥ R_diff = 90 ∥ 60 = (90 × 60)/150 = 36.00 Ω
```

Time constant and edge:
```
τ       = 36.00 Ω × 500 pF = 18.0 ns
t_rise  ≈ 2.2 τ = 2.2 × 18.0 = 39.6 ns  ≈ 40 ns  (10–90 %)
```

**Sanity check against the bit time:**
```
40 ns / 8000 ns  = 0.50 % of a bit time
40 ns /  500 ns  = 8.0 %  of a time quantum
```
Fast enough to be irrelevant to protocol timing; slow enough to keep ngspice's solver stable. Real CAN transceivers at 125 kbit/s produce 50–150 ns edges, so this is realistic — arguably slightly optimistic, which is fine.

**Why capacitance is not optional:** an ideal zero-capacitance switching node makes the derivative of voltage infinite at the switching instant, which is the classic cause of ngspice `timestep too small` failures. The capacitance is simultaneously physically correct and numerically necessary.

### 3.8.6 Differential receiver

ISO 11898-2 receiver thresholds:
```
V_diff > 0.900 V  →  DOMINANT
V_diff < 0.500 V  →  RECESSIVE
```

Centre and hysteresis:
```
V_threshold  = (0.900 + 0.500) / 2 = 0.700 V
V_hysteresis = (0.900 − 0.500) / 2 = 0.200 V
```

Implemented as a **smooth behavioural source** rather than an ideal comparator, because discontinuous transfer functions are the second-largest cause of convergence failure:

```spice
Bcomp rx_ana 0 V = 2.5 * (1 - tanh(10 * (V(canh) - V(canl) - 0.7)))
```

Transfer characteristic:

| V_diff | 10·(V_diff−0.7) | tanh | Output | Interpretation |
|---|---|---|---|---|
| 0.000 V | −7.00 | −0.999998 | 5.000 V | recessive → logic 1 ✓ |
| 0.500 V | −2.00 | −0.96403 | 4.910 V | still recessive ✓ |
| 0.700 V | 0.00 | 0.00000 | 2.500 V | threshold |
| 0.900 V | +2.00 | +0.96403 | 0.090 V | dominant ✓ |
| 2.000 V | +13.00 | +1.000000 | 0.000 V | dominant → logic 0 ✓ |
| 3.333 V | +26.33 | +1.000000 | 0.000 V | 3 drivers, still dominant ✓ |

**Gain factor selection.** The transition width (10%→90% of output swing) is:
```
Δ(V_diff) = 2 × atanh(0.8) / k = 2 × 1.0986 / 10 = 0.220 V
```
centred on 0.700 V, i.e. spanning 0.590–0.810 V. That sits neatly inside the 0.5–0.9 V specification band. **k = 10** is therefore the right choice; k = 100 would approach an ideal comparator and reintroduce convergence risk, while k = 2 would produce a 1.1 V transition that violates the spec band.

**Note the inversion:** high V_diff (dominant) produces a **low** output. This is correct — dominant is logic 0. Polarity errors here are the single most common PHY bug (§5.4 N7).

### 3.8.7 Analog↔digital bridge parameters

**`dac_bridge`** — digital TX (from VHDL) → analog switch control:
```
out_low   = 0.0 V
out_high  = 5.0 V
out_undef = 2.5 V
t_rise    = 20 ns
t_fall    = 20 ns
```
20 ns is half the 40 ns bus edge, so the bridge does not become the dominant pole.

**`adc_bridge`** — analog comparator output → digital RX (into VHDL):
```
in_low    = 1.5 V     (30 % of 5 V)
in_high   = 3.5 V     (70 % of 5 V)
```
The 2.0 V gap gives a wide dead band, well clear of the comparator's 0.22 V transition region referred to the output, preventing chatter.

**Clock bridge** — the 2 MHz VHDL clock is generated in the analog domain and bridged:
```spice
Vclk clk_ana 0 PULSE(0 5 0 5n 5n 250n 500n)
Aclk [clk_ana] [clk_dig] adc_clk
.model adc_clk adc_bridge(in_low=1.5 in_high=3.5)
```
Period 500 ns = 2 MHz, 50% duty (250 ns high), 5 ns edges.

### 3.8.8 Frozen analog parameter table

| Parameter | Symbol | Value | Source |
|---|---|---|---|
| Supply | VCC | 5.000 V | ISO 11898-2 |
| Recessive level | — | 2.500 V both lines | ISO 11898-2 |
| Dominant CANH | — | 3.500 V | ISO 11898-2 |
| Dominant CANL | — | 1.500 V | ISO 11898-2 |
| Dominant differential | V_diff | 2.000 V | derived |
| Termination (each end) | R_term | 120 Ω | matched to Z₀ |
| Differential load | R_diff | 60.00 Ω | 120 ∥ 120 |
| Dominant load current | I | 33.333 mA | 2.0 V / 60 Ω |
| **Driver on-resistance** | **R_on** | **45.00 Ω** | **1.5 V / 33.333 mA** |
| Driver power (1 node) | P | 166.7 mW | VCC × I |
| Bias resistors | R_bias | 10 kΩ × 2 | 0.30% load error |
| Bias reference | V_ref | 2.500 V | VCC / 2 |
| Bus capacitance (SHORT) | C_H, C_L | 1 nF each | 40 ns edge |
| Differential capacitance | C_diff | 500 pF | series |
| Effective source R | R_src | 36.00 Ω | 90 ∥ 60 |
| Edge time constant | τ | 18.0 ns | R_src × C_diff |
| Rise time 10–90% | t_r | 39.6 ns | 2.2 τ |
| Line impedance (LONG) | Z₀ | 120 Ω | matched |
| Line inductance (LONG) | L' | 600 nH/m | Z₀ / v |
| Line capacitance (LONG) | C' | 41.67 pF/m | 1/(Z₀·v) |
| Line delay (220 m) | TD | 1.100 µs | L / v |
| Comparator threshold | V_th | 0.700 V | (0.9+0.5)/2 |
| Comparator hysteresis | V_hyst | ±0.200 V | (0.9−0.5)/2 |
| Comparator gain | k | 10 | 0.22 V transition |
| DAC rails | — | 0 / 5 V | logic levels |
| DAC edges | — | 20 ns | < bus edge |
| ADC thresholds | — | 1.5 / 3.5 V | 30% / 70% |

## 3.9 Complete frozen digital parameter table

| Parameter | Value |
|---|---|
| Bit rate | 125 000 bit/s |
| Nominal bit time | 8.000 µs |
| Time quanta per bit | 16 |
| Time quantum | 500 ns |
| VHDL clock | 2.000 MHz |
| SYNC_SEG | 1 tq (500 ns) |
| PROP_SEG | 5 tq (2500 ns) |
| PHASE_SEG1 | 6 tq (3000 ns) |
| PHASE_SEG2 | 4 tq (2000 ns) |
| Sample point | 12 tq (6.000 µs, 75.00%) |
| SJW | 4 tq (2.000 µs) |
| Oscillator tolerance | 0.98% |
| Max bus length | 220 m |
| CRC polynomial | 0x4599 |
| CRC width | 15 bits |
| CRC init | 0x0000 |
| Stuff threshold | 5 identical bits |
| Stuff error threshold | 6 identical bits |
| Error flag length | 6 bits |
| Error delimiter | 8 bits |
| IFS / intermission | 3 bits |
| Suspend transmission | 8 bits (error-passive) |
| Error-passive threshold | TEC or REC > 127 |
| Bus-off threshold | TEC > 255 |
| Bus-off recovery (real) | 128 × 11 recessive bits |
| Bus-off recovery (simulated) | 8 × 11 recessive bits |
| TEC increment (TX error) | +8 |
| REC increment (RX error) | +1 |
| REC increment (first detector) | +8 |
| TEC/REC decrement (success) | −1 |

## 3.10 Simulator control

```spice
* --- Default transient settings ---
.tran 100n 1.5m

* --- Solver options: start here ---
.options reltol=1e-3        $ relative tolerance
.options abstol=1e-9        $ absolute current tolerance (1 nA)
.options vntol=1e-6         $ absolute voltage tolerance (1 µV)
.options chgtol=1e-14       $ charge tolerance
.options trtol=7            $ truncation error over-estimate factor
.options gmin=1e-12         $ minimum conductance
.options method=trap        $ trapezoidal integration
.options maxord=2           $ maximum integration order
.options itl1=200           $ DC iteration limit
.options itl4=50            $ transient iteration limit

* --- DC operating point hint ---
.nodeset v(canh)=2.5 v(canl)=2.5
```

If convergence fails, apply the escalation ladder in §5.5 **in order**. Do not skip steps — jumping straight to loose tolerances hides real circuit errors.

---
# PART 4 — TOOLCHAIN REFERENCE

## 4.1 What each tool does and where it sits

| Tool | Version | Role | You use it… |
|---|---|---|---|
| **GHDL** | 4.1.0 LLVM | VHDL analyser/elaborator/simulator | …constantly. This is your primary development tool. |
| **GTKWave** | 3.3.104 | VCD waveform viewer | …constantly, alongside GHDL |
| **ngspice** | 35 (NGHDL-patched) | Analog + event-driven simulator | …directly for PHY development; indirectly via eSim later |
| **XSPICE** | built into ngspice | Event-driven extension: `adc_bridge`, `dac_bridge`, digital primitives | …as library parts; already installed as `.cm` files |
| **NGHDL** | bundled with eSim | Wraps a GHDL-compiled entity as an XSPICE code model + generates a KiCad symbol | …only at integration milestones |
| **KiCad / Eeschema** | system | Schematic capture | …in Phases 7–9 |
| **eSim** | 2.5 | Project manager; orchestrates KiCad → netlist → ngspice | …in Phases 7–9 |
| **Python 3** | 3.10 | Independent reference models (CRC, frame encoder) | …for cross-checking VHDL |
| **git** | system | Version control | …every single day |
| Verilator | 4.210 | Verilog path (NgVeri) | …not used in this plan |

**Verified installation paths on your machine:**
```
/usr/bin/esim
/usr/bin/kicad
/usr/bin/ngspice                    → NGHDL-patched build
/usr/local/bin/ghdl
/usr/local/bin/verilator
/usr/bin/gtkwave
~/nghdl-simulator/install_dir/lib/ngspice/
    analog.cm  digital.cm  ghdl.cm  Ngveri.cm  spice2poly.cm  table.cm  xtradev.cm  xtraevt.cm
```

`ghdl.cm` is the shim that lets ngspice instantiate your compiled VHDL. `digital.cm` provides the bridges. Both confirmed present.

## 4.2 How the pieces connect

```
   your .vhdl ──► GHDL ──► compiled object
                            │
                            ▼
                       NGHDL wrapper
                    ┌───────┴────────┐
                    ▼                ▼
          XSPICE code model    KiCad symbol (.lib/.dcm)
          (loaded by ngspice)   (placed in Eeschema)
                    │                │
                    └────────┬───────┘
                             ▼
              Eeschema schematic  ──►  KiCad-to-Ngspice  ──►  .cir netlist
                                                                  │
                                                                  ▼
                                                      ngspice (analog + event)
                                                                  │
                                                                  ▼
                                                        plots / raw data
```

## 4.3 The GHDL development loop (your 90% workflow)

```bash
cd ~/Documents/CAN_project/vhdl

ghdl -a  module.vhdl tb_module.vhdl          # analyse (compile) — dependency order matters
ghdl -e  tb_module                            # elaborate (link)
ghdl -r  tb_module --stop-time=1ms --vcd=out.vcd --assert-level=error
gtkwave  out.vcd &
```

Useful flags:

| Flag | Effect |
|---|---|
| `--stop-time=1ms` | Hard stop. **Always use it** — a testbench without a stop condition runs forever. |
| `--vcd=file.vcd` | Dump waveform |
| `--wave=file.ghw` | GHDL native format — smaller and faster than VCD for large runs |
| `--assert-level=error` | Halt on a failing `assert` — essential for self-checking tests |
| `--ieee-asserts=disable` | Suppress noisy IEEE library warnings about `U`/`X` metavalues |
| `-fsynopsys` | Allow non-standard libraries — **avoid**; fix your code instead |

**Automation — build this on Day 6 and use it every day after:**

```bash
cat > ~/Documents/CAN_project/vhdl/run.sh <<'EOF'
#!/bin/bash
# usage: ./run.sh <module> [stop_time]     e.g.  ./run.sh can_crc15 200us
set -e
M=$1; T=${2:-1ms}
rm -f work-obj93.cf
ghdl -a ${M}.vhdl tb_${M}.vhdl
ghdl -e tb_${M}
ghdl -r tb_${M} --stop-time=${T} --vcd=${M}.vcd --assert-level=error
echo "PASS: ${M}  ->  ${M}.vcd"
EOF
chmod +x ~/Documents/CAN_project/vhdl/run.sh
```

**Regression script — build this on Day 77:**

```bash
cat > ~/Documents/CAN_project/vhdl/regress.sh <<'EOF'
#!/bin/bash
# Run every testbench; report pass/fail summary.
MODULES="can_bit_timing can_crc15 can_stuffer can_destuffer \
         can_tx_fsm can_rx_fsm can_filter can_error_mgmt can_node"
PASS=0; FAIL=0; FAILED=""
for m in $MODULES; do
  if ./run.sh $m 5ms > /tmp/${m}.log 2>&1; then
    echo "  PASS  $m"; PASS=$((PASS+1))
  else
    echo "  FAIL  $m   (see /tmp/${m}.log)"; FAIL=$((FAIL+1)); FAILED="$FAILED $m"
  fi
done
echo "─────────────────────────────"
echo "  $PASS passed, $FAIL failed"
[ -n "$FAILED" ] && echo "  failing:$FAILED"
exit $FAIL
EOF
chmod +x ~/Documents/CAN_project/vhdl/regress.sh
```

## 4.4 Self-checking testbench pattern

**This is Rule 3, and it is what makes 45 tests manageable.** A testbench should *tell you* it passed, not require you to look.

```vhdl
-- inside the stimulus process
check_id : assert rx_id = "00010100101"
    report "FAIL: expected ID 0x0A5, got something else"
    severity error;

check_crc : assert crc_out = x"1234"
    report "FAIL: CRC mismatch"
    severity error;

-- final summary
report "===== ALL CHECKS PASSED =====" severity note;
```

Severity levels:

| Level | GHDL behaviour |
|---|---|
| `note` | prints, continues |
| `warning` | prints, continues |
| `error` | prints; **halts if `--assert-level=error`** |
| `failure` | always halts |

Run with `--assert-level=error` and a failing test returns a non-zero exit code — which is what makes `regress.sh` work.

## 4.5 The NGHDL integration loop (use sparingly)

**Preconditions — check all three before starting:**
1. The VHDL filename matches the entity name exactly (`can_node.vhdl` ↔ `entity can_node`)
2. All ports are `in` or `out` — **never `inout`**
3. The design compiles cleanly under GHDL with zero warnings

**Procedure:**
1. eSim → **NGHDL** button (left rail)
2. Upload the `.vhdl` file
3. NGHDL invokes GHDL, builds the code model, and runs `createkicad` to generate the symbol
4. **Restart eSim** — the KiCad symbol library is cached at startup and will not otherwise refresh
5. In Eeschema, place the symbol from the NGHDL library
6. eSim → **KiCad-to-Ngspice** → click through **every** tab, including ones that look empty → **Convert**
7. eSim → **Simulate**

Steps 4 and 6 are the ones people skip; together they account for most "it doesn't work" reports.

## 4.6 NGHDL constraints

**Confirmed:**
- Entity name must equal the filename
- Port directions: `in` / `out` only
- Port types: `std_logic`, `std_logic_vector`

**To be determined empirically on Days 3–4** — do not assume either way:

| Question | Expected | Consequence if false |
|---|---|---|
| Are `generic`s passed through? | **No** | Use `constant` in the architecture. *(Design assumes this already.)* |
| Do `std_logic_vector` ports produce correct multi-pin symbols? | Yes | Fall back to Approach A (scalar ports, separate entities) |
| Can multiple instances of one model coexist? | Yes | Fall back to separate entities per node |
| Are `integer`/`unsigned` ports supported? | No | Convert at the boundary; keep internals typed |

**Design rule adopted:** the top-level `can_node` entity uses **only** `std_logic` and `std_logic_vector` ports, and **no generics**. All configuration is via `constant` declarations. This is already reflected in Appendix C.

## 4.7 ngspice standalone usage

```bash
ngspice -b netlist.cir              # batch mode: run and exit
ngspice -b netlist.cir -r out.raw   # batch + write raw data
ngspice netlist.cir                 # interactive
```

Interactive commands worth knowing:

| Command | Effect |
|---|---|
| `run` | run the analysis |
| `plot v(canh) v(canl)` | plot signals |
| `plot v(canh)-v(canl)` | plot an expression |
| `print v(canh)` | print values |
| `let vd = v(canh)-v(canl)` | define a derived vector |
| `meas tran trise TRIG v(canh) VAL=2.6 RISE=1 TARG v(canh) VAL=3.4 RISE=1` | measure rise time |
| `alter Vctrl 0` | change a source value between runs |
| `write out.raw v(canh) v(canl)` | export data |
| `quit` | exit |

An in-netlist `.control` block automates all of this — see Appendix B.

## 4.8 Project layout

```
~/Documents/CAN_project/                      ← git repository root
├── .git/
├── .gitignore                      ← *.vcd *.o work-obj93.cf *.raw
├── LOG.md                          ← daily log — MANDATORY
├── README.md                       ← how to reproduce every result
├── vhdl/
│   ├── can_bit_timing.vhdl
│   ├── can_crc15.vhdl
│   ├── can_stuffer.vhdl
│   ├── can_destuffer.vhdl
│   ├── can_tx_fsm.vhdl
│   ├── can_rx_fsm.vhdl
│   ├── can_filter.vhdl
│   ├── can_error_mgmt.vhdl
│   ├── can_node.vhdl               ← top level; NGHDL consumes this
│   ├── tb_*.vhdl                   ← one self-checking testbench per module
│   ├── run.sh
│   └── regress.sh
├── python/
│   ├── crc15_ref.py                ← independent CRC reference
│   ├── frame_gen.py                ← independent frame encoder, generates test vectors
│   └── vectors/                    ← generated golden vectors
├── spice/
│   ├── phy_dc.cir                  ← Day 13
│   ├── phy_loopback.cir            ← Day 14
│   ├── phy_wired_and.cir           ← Day 16
│   ├── phy_tline.cir               ← Day 17
│   ├── phy_reflection.cir          ← Day 18
│   └── phy_commonmode.cir          ← Day 19
├── esim/                           ← symlink to ~/eSim-Workspace/CAN2.0
└── docs/
    ├── measurements.md             ← every measured vs predicted number
    ├── waveforms/                  ← every screenshot, named by day
    ├── schematics/                 ← Eeschema exports
    └── report/
```

## 4.9 Version control — non-negotiable

```bash
cd ~/Documents/CAN_project
git init
cat > .gitignore <<'EOF'
*.vcd
*.ghw
*.o
*.raw
work-obj93.cf
tb_*
!tb_*.vhdl
EOF
git add -A
git commit -m "Day 1: project skeleton"

# private remote (do this on Day 1, not Day 40)
git remote add origin git@github.com:<you>/can-esim.git
git push -u origin main
```

End every working session with:
```bash
git add -A && git commit -m "Day N: <one line>" && git push
```

This project lives inside a single VirtualBox image that has already exhausted its disk once. Losing it in week 8 would be avoidable and devastating.

---

# PART 5 — FAILURE CATALOGUE

*Read once now. Return whenever anything breaks. **Hard rule: never spend more than 30 minutes stuck on something listed here** — find it, apply the fix, move on.*

## 5.1 Environment and infrastructure

| # | Symptom | Cause | Fix |
|---|---|---|---|
| E1 | `Not enough disk space`; eSim Python crash mid-conversion | Root filesystem full | Grow VDI **and** partition — §5.2. This is a two-step operation. |
| E2 | Disk fills again weeks later | NGHDL rebuilds ngspice code models on every model creation | Keep ≥ 15 GB free. Monitor with `du -sh ~/nghdl-simulator/*`. **Never delete `~/nghdl-simulator/`** — both `release/` and `install_dir/` are live. |
| E3 | `esim` blocks the terminal | Foreground process | `esim &`. Keep the launching terminal visible — Python tracebacks appear there, not in the GUI. |
| E4 | Eeschema blank / slow / crashes | VirtualBox graphics | Enable 3D acceleration, video memory 128 MB, install Guest Additions |
| E5 | Everything lost after a VM problem | No backup | Rule 4. Commit and push daily. |
| E6 | Simulations inexplicably slow | VM under-resourced | Give the VM ≥ 4 vCPU and ≥ 8 GB RAM |

## 5.2 The VDI resize trap (E1 in detail)

Growing the disk requires **two** operations. Doing only the first is the classic error.

**Step 1 — grow the virtual disk (VM powered off, on the host):**
```
VirtualBox Manager → File → Tools → Virtual Media Manager
  → select the .vdi → drag Size to 80 GB → Apply
```
or:
```
VBoxManage modifymedium disk "/path/to/ubuntu-22.vdi" --resize 81920
```

**Step 2 — grow the partition and filesystem (inside Ubuntu):**
The guest still reports the old size until you do this.
```bash
sudo apt install cloud-guest-utils
lsblk                          # confirm layout; note the partition number
sudo growpart /dev/sda 3       # grow partition 3 into the free space
sudo resize2fs /dev/sda3       # grow the ext4 filesystem
df -h /                        # verify
```

If `growpart` refuses — LVM, or the partition is not last on the disk — boot the Ubuntu live ISO and use GParted to extend `/dev/sda3`, then reboot.

**Target: ≥ 40 GB free.** This project builds ngspice code models repeatedly; 5 GB is not enough.

## 5.3 GHDL and VHDL problems

| # | Symptom | Cause | Fix |
|---|---|---|---|
| V1 | `entity "x" not found` | Wrong analysis order | Analyse dependencies first: `ghdl -a sub.vhdl top.vhdl tb_top.vhdl` |
| V2 | `unit "x" has changed and must be reanalysed` | Stale library file | `rm -f work-obj93.cf *.o` then re-analyse everything (already in `run.sh`) |
| V3 | VCD exists but GTKWave shows nothing | No signals added, or zoomed to femtoseconds | Click entity in SST → select signals → **Append** → **Time → Zoom → Zoom Full** |
| V4 | Simulation never ends | No stop condition | Always pass `--stop-time=`. Never rely on the testbench to terminate. |
| V5 | `bound check failure` | Vector index out of range — usually an off-by-one counter | Add `report` around the index; check `to` vs `downto` |
| V6 | Signal is `U` | Never assigned, or read before reset released | Initialise at declaration: `signal s : std_logic := '0';` and hold reset ≥ 4 clocks |
| V7 | Signal is `X` | Two processes driving one signal | One signal, one driver. Never assign the same signal from two processes. |
| V8 | Assignment appears one clock late | Signals update at process end | Correct behaviour — that is a flip-flop. Use a `variable` for immediate update within a process. |
| V9 | Type conversion errors | `std_logic_vector` ≠ `unsigned` ≠ `integer` | `use ieee.numeric_std.all;` → `to_integer(unsigned(x))`, `std_logic_vector(to_unsigned(n,w))`. **Never** `std_logic_arith`. |
| V10 | Inferred latch warnings | Incomplete `if`/`case` in combinational logic | Cover every branch; always include `when others` |
| V11 | Assertion never fires even when wrong | Missing `--assert-level=error`, or assertion placed where it is never reached | Check the report text actually prints; put a deliberate failure in temporarily to confirm the check runs |
| V12 | Works in GHDL, misbehaves in NGHDL | Timing/initialisation assumptions that only hold in a testbench | Ensure reset is driven from ngspice and held long enough; never rely on VHDL initial values alone |

## 5.4 ngspice / analog problems

| # | Symptom | Fix ladder — apply in order |
|---|---|---|
| N1 | `Timestep too small` | 1. Confirm `C_CANH`/`C_CANL` = 1 nF present<br>2. Confirm comparator uses smooth `tanh`, not a ternary `?:`<br>3. Add `.options trtol=7`<br>4. Add `.nodeset v(canh)=2.5 v(canl)=2.5`<br>5. Relax: `reltol=1e-2 abstol=1e-8`<br>6. `.options method=gear maxord=2`<br>7. Increase switch transition width / use `aswitch` with `log=TRUE`<br>8. Add 1 MΩ from every node to ground |
| N2 | `singular matrix` | A node has no DC path to ground. Add 1 MΩ to ground. Most often on the digital side of a bridge or a floating switch terminal. |
| N3 | `no convergence in DC analysis` | Add `.nodeset`; if it persists, add `.options itl1=500` |
| N4 | Runtime > 10 min | Max timestep too small, or excessive digital events. Check `.tran 100n 1.5m` — the **first** number is the max step. For long runs use 200 n. |
| N5 | Bus stuck at 2.5 V | Drivers never enabled. Probe the `dac_bridge` output — it must swing 0→5 V, and the switch threshold must lie between. |
| N6 | Dominant levels wrong | `R_on` ≠ 45 Ω, or a termination resistor missing/mis-valued. **Re-derive with §3.8.3 — do not tune the resistor until the plot looks right.** |
| N7 | RX never goes low | Comparator polarity inverted, or `adc_bridge` thresholds wrong. Plot `v(canh)-v(canl)` and the comparator output on one axis. |
| N8 | Reflections / ringing on edges | Termination mismatch. Expected in the Day 18 study; a bug anywhere else. |
| N9 | Results change when unrelated things change | Floating node or marginal tolerance. Fix N1/N2 properly rather than working around it. |
| N10 | Transmission line gives odd results | `T` element ports are (p1+, p1−, p2+, p2−). Check `Z0` and `TD` units (`1.1u` not `1.1µ`). |
| N11 | `.measure` returns nothing | Trigger condition never met, or the signal name is wrong | Plot first, measure second. |

## 5.5 eSim / NGHDL / KiCad problems

| # | Symptom | Cause | Fix |
|---|---|---|---|
| S1 | `The project doesn't contain .proj file` | Selected a parent directory | Navigate **into** the project folder, or paste the full path into the **Directory:** field |
| S2 | `Please select the project first` | Tool clicked before opening a project | Open Project — **2nd icon, top toolbar** — first |
| S3 | Projects pane empty after opening | Tree does not always populate for projects outside the workspace | Cosmetic. Copy the project into `~/eSim-Workspace/` if it bothers you. |
| S4 | New NGHDL symbol absent from KiCad | Symbol library cached at startup | **Restart eSim after every model generation.** Every time. |
| S5 | Netlist incomplete after Convert | A tab was skipped | Click through **every** tab, including empty-looking ones |
| S6 | "unknown device" at simulation | `.cm` not loaded | Check `~/nghdl-simulator/install_dir/lib/ngspice/` contains your model; check `spinit` |
| S7 | eSim Python crash | Disk full (usual); path with spaces (occasional) | Fix disk. Never use spaces in paths. Read the traceback in the launching terminal. |
| S8 | Second instance behaves like the first | Reference designator collision | Unique refdes per instance: U1, U2, U3, U4 |
| S9 | Multi-bit port appears as one pin | Vector handling | Exactly what Days 3–4 test. Fall back to scalar ports (Approach A). |
| S10 | Model builds but ports are misordered | NGHDL orders pins by declaration order | Keep the entity port order stable once frozen; re-check the symbol after any change |
| S11 | Simulation runs but VHDL output never changes | Clock not reaching the model | Probe the `adc_bridge` output feeding `clk`. A missing clock is the most common integration bug. |
| S12 | Reset never releases | Reset polarity or level mismatch across the bridge | Confirm the digital reset is `1` then `0`, with the bridge thresholds correct |

## 5.6 Protocol-level bugs

| # | Symptom | Likely cause | Where to look |
|---|---|---|---|
| P1 | Received ID shifted one bit | Sampling on the wrong edge, or SOF detection off by one bit | `can_rx_fsm` SOF state |
| P2 | CRC never matches | Stuff bits included in CRC (they must not be), or bit order reversed | `can_crc15` enable logic |
| P3 | Stuff bits in fixed-form fields | Stuffing not disabled after the CRC field | `can_stuffer` enable |
| P4 | Spurious stuff error on a valid frame | Destuffer's run counter not reset on a polarity change | `can_destuffer` |
| P5 | All nodes think they won | Comparison not at the sample point, or comparing the pre-stuff bit instead of the actual bus bit | `can_tx_fsm` arbitration check |
| P6 | Winner also drops out | **Treating `tx=0, rx=0` as a loss.** Only `tx=1, rx=0` is a loss. | `can_tx_fsm` — this is the #1 arbitration bug |
| P7 | ACK never detected | Receiver not driving dominant in the ACK slot, or transmitter checking the wrong bit | `can_rx_fsm` ack_drive timing |
| P8 | Frames run together | IFS not enforced | `can_tx_fsm` IFS state |
| P9 | Stuff bit corrupts the frame | FSM advanced its bit index during a stuff bit | **The stall handshake — see §5.7** |
| P10 | Error frame never ends | Delimiter counter wrong, or waiting for a condition that never occurs | `can_error_mgmt` |
| P11 | Error flags don't superpose correctly | Node stops driving too early | Error flag is 6 bits *minimum*; must continue while the bus stays dominant |
| P12 | TEC/REC drift wrongly | Increment applied more than once per event | Gate increments on a single-cycle pulse, not a level |
| P13 | Bus-off never recovers | Recovery counter counting bits instead of *occurrences of 11 recessive bits* | `can_error_mgmt` recovery FSM |
| P14 | Resynchronisation makes things worse | Sign of the phase error inverted | §1.6.3 — late edge → **lengthen PS1**; early edge → **shorten PS2** |
| P15 | Extended frame decoded as standard | IDE bit sampled at the wrong position | `can_rx_fsm` — IDE is bit 2 after the base ID in extended frames |

## 5.7 The stuff-bit stall handshake (P9 — expanded)

**v1.0 listed a `stall` port and never explained it. This is that explanation.**

The transmit path is a chain:
```
can_tx_fsm ──tx_bit──► can_stuffer ──tx_stuffed──► dac_bridge ──► bus
```

When the stuffer decides to insert a stuff bit, it must transmit the *stuff* bit for one bit time and **hold the FSM's original bit**, so that the FSM does not advance and lose a real frame bit.

**Protocol:**

| Signal | Direction | Meaning |
|---|---|---|
| `tx_bit` | FSM → stuffer | the next real frame bit |
| `bit_start` | timing → both | one-tq pulse at each bit boundary |
| `stuff_active` | stuffer → FSM | **high for the whole bit time in which a stuff bit is on the bus** |
| `tx_stuffed` | stuffer → PHY | what actually goes on the wire |

**FSM rule:**
```vhdl
if bit_start = '1' and stuff_active = '0' then
    -- advance to the next frame bit
    bit_index <= bit_index + 1;
    -- ... state transitions ...
end if;
-- when stuff_active = '1', the FSM does NOTHING: same bit_index, same state
```

**Stuffer rule:**
```vhdl
if bit_start = '1' then
    if stuff_active = '1' then
        stuff_active <= '0';          -- stuff bit is done; resume
        run_count    <= 1;            -- the stuff bit itself starts a new run
        last_bit     <= not last_bit;
    elsif run_count = 5 then
        stuff_active <= '1';          -- insert now
        tx_stuffed   <= not last_bit;
    else
        tx_stuffed   <= tx_bit;
        if tx_bit = last_bit then run_count <= run_count + 1;
        else run_count <= 1; last_bit <= tx_bit; end if;
    end if;
end if;
```

**The mirror problem on receive:** the destuffer must *discard* a received stuff bit and **not** present it to `can_rx_fsm`, using a `rx_valid` strobe:

```vhdl
-- destuffer output
rx_valid <= '0' when this_bit_was_a_stuff_bit else '1';

-- rx_fsm only advances when rx_valid = '1'
```

**And the CRC must be gated on the same strobe** — stuff bits are not part of the CRC (§1.5). A single missing gate here produces bug P2, which then looks like a CRC implementation error and wastes a day. Day 31 is dedicated entirely to this handshake for exactly that reason.

## 5.8 When you are genuinely stuck — the bisection procedure

If something fails and it is not in this catalogue:

1. **Isolate the domain.** Does it fail in GHDL alone? Then it is VHDL. Only in eSim? Then it is integration.
2. **Replace with a stub.** Swap the failing block for a trivial one that produces a known output. If the system then works, the block is at fault; if not, the surroundings are.
3. **Bisect in time.** Find the last moment the waveform is correct. The bug is at that instant, not where you noticed it.
4. **Bisect in git.** `git stash` your changes and confirm the last commit still works. If it does, the bug is in today's work — a much smaller search space.
5. **Print, don't stare.** Add `report` statements in VHDL and `print`/`.measure` in SPICE. Numbers beat eyeballs.
6. **Reduce the stimulus.** One bit instead of a frame. One node instead of three. Shrink until it is trivially understandable, then grow back.
7. **Sleep on it.** Genuinely — after 90 minutes of no progress your effective debugging rate is near zero. The buffer days exist for this.

---

# PART 6 — DAY-BY-DAY PLAN (86 DAYS)

**Structure:** 12 phases. Each day has a **Goal**, **Tasks**, an **Exit criterion** (an objective test), and an **If stuck** hatch with a time limit.

**Rules of engagement:**
- If a day's exit criterion is unmet, **do not start the next day's new material.** Roll into the next buffer.
- Buffer days (5, 12, 22, 28, 38, 45, 56, 63, 70, 76, 81) are scheduled slip absorption, not padding. You will use several.
- `git commit` and update `LOG.md` at the end of **every** day. Two lines minimum: what worked, what broke.
- Update `docs/measurements.md` whenever you measure anything.

---

## PHASE 0 — ENVIRONMENT AND DE-RISKING (Days 1–5)

### DAY 1 — Infrastructure

**Goal:** a machine that will not run out of disk, and a project that cannot be lost.

**Tasks:**
1. Power off the VM. Grow the VDI to **80 GB** (§5.2 Step 1).
2. Boot; grow partition and filesystem (§5.2 Step 2). Verify `df -h /` shows ≥ 40 GB free.
3. Increase VM allocation to ≥ 4 vCPU and ≥ 8 GB RAM if the host allows.
4. Create the full directory tree from §4.8.
5. `git init`, `.gitignore`, first commit, **push to a private remote**.
6. Create `LOG.md` and `docs/measurements.md` with headers.
7. Install anything missing: `sudo apt install git python3 pandoc cloud-guest-utils`

**Exit criterion:** `df -h /` ≥ 40 GB free; `git log` shows one commit; `git push` succeeded to an off-machine remote.

**If stuck (2 h):** if `growpart` fails, use GParted from a live ISO. If the host has no space, delete `~/Downloads/eSim-2.5` except `Examples/` — eSim is already installed system-wide.

---

### DAY 2 — Toolchain gate

**Goal:** prove the VHDL → GHDL → NGHDL → ngspice path works **on your machine**. Nothing else in this plan matters until this passes.

**Tasks:**
1. `esim &`
2. Open Project → `/home/vboxuser/Downloads/eSim-2.5/Examples/Mixed_Signal/custom_mixed_signal`
3. **KiCad-to-Ngspice** → every tab → **Convert**
4. **Simulate**
5. Capture the plot → `docs/waveforms/day02_toolchain_proof.png`
6. Separately confirm GHDL + GTKWave still work (re-run the `tq_gen` test you already built)

**Exit criterion:** the example produces a plot, and GTKWave displays a GHDL-generated VCD.

**If stuck (3 h):** read the traceback in the launching terminal. Consult §5.5. If it still fails with adequate disk, try the eSim Docker image as an alternative environment before spending another day on the native install.

---

### DAY 3 — NGHDL capability probe, part 1

**Goal:** establish what NGHDL can actually do with scalar ports and multiple instances.

**Tasks:**
1. Write `probe_and.vhdl` — a 2-input AND with three `std_logic` ports.
2. Verify in GHDL first (10 lines of testbench).
3. Push through NGHDL. Restart eSim. Confirm the symbol appears with 3 pins.
4. Build a schematic: two digital sources → `probe_and` → output. Simulate. Confirm correct AND behaviour.
5. **Probe: multiple instances.** Place **two** `probe_and` symbols with different inputs. Simulate. Do they behave independently?
6. Record both answers in `LOG.md`.

**Exit criterion:** you can state with evidence whether one model supports multiple independent instances.

**If stuck (3 h):** if multi-instance fails, plan for separate entities per node (Approach A). Record the decision and move on — do not try to fix NGHDL.

---

### DAY 4 — NGHDL capability probe, part 2, and the architecture decision

**Goal:** settle vectors and generics; lock the node instantiation strategy.

**Tasks:**
1. **Probe: vector ports.** `probe_vec.vhdl` with `din : in std_logic_vector(3 downto 0)` and `dout : out std_logic`. Push through NGHDL. Does the symbol show **4 separate pins**?
2. **Probe: generics.** Push a module using a `generic`. Does it build? *(Expected: no.)*
3. **Probe: wide vectors.** Repeat with `std_logic_vector(15 downto 0)` — do 16 pins appear and remain usable in a schematic?
4. Record everything in `LOG.md` and `docs/measurements.md`.
5. **Make the decision:**

| Probe results | Decision |
|---|---|
| Vectors ✅, instances ✅ | **Approach B** — one `can_node`, `node_sel(1:0)` input |
| Vectors ❌ | **Approach A** — `can_node_a/b/c/d`, scalar ports, hardcoded IDs |
| Instances ❌ | **Approach A**, mandatory |
| Both ❌ | Approach A with 2 nodes minimum; still fully satisfies the task |

6. Write the decision and its rationale into `LOG.md`. **This decision is now frozen.**

**Exit criterion:** architecture decision made and recorded, backed by four probe results.

**If stuck (3 h):** Approach A with scalar ports is guaranteed to work. Take it. Do not spend a second day here — this day is *insurance*, and insurance you spend two days on is a bad deal.

---

### DAY 5 — BUFFER + ngspice fundamentals

**Tasks:**
1. Absorb any slip from Days 1–4. **Do this first.**
2. Learn raw ngspice: write a trivial RC circuit netlist, run `.tran`, plot, use `.measure` to extract the time constant.
3. Confirm your measured τ matches `R × C` analytically.
4. Read §4.7 and try each interactive command once.

**Exit criterion:** Days 1–4 exit criteria all met; you can write, run and measure a SPICE netlist without the GUI.

---

## PHASE 1 — VHDL COMPETENCY (Days 6–12)

*This phase produces no deliverables. It is pure investment. Do not skip it — every later day gets slower if you do.*

### DAY 6 — VHDL I: structure and clocked logic

**Tasks:**
1. Read Appendix A §A.1–A.4.
2. Write `run.sh` (§4.3).
3. Exercise: an 8-bit up-counter with synchronous enable and asynchronous reset.
4. Testbench it. View in GTKWave. Verify the count sequence and reset behaviour.
5. Deliberately introduce the signal-vs-variable bug from §A.2 and observe it in the waveform. Then fix it. **Understanding this now saves days later.**

**Exit criterion:** counter works; you can explain *why* `a <= b; c <= a;` gives `c` the old value of `a`.

---

### DAY 7 — VHDL II: finite state machines

**Tasks:**
1. Read Appendix A §A.5.
2. Exercise: a 4-state FSM (IDLE → START → RUN → DONE) with a `start` input and a `busy` output.
3. Extend it to output a fixed 8-bit pattern serially, MSB first.
4. Testbench; verify the output stream bit by bit.

**Exit criterion:** you can write a clocked FSM from scratch, without reference. `can_tx_fsm` is this pattern at larger scale.

**If stuck:** take two days. This is the highest-leverage skill in the project.

---

### DAY 8 — VHDL III: vectors, arithmetic, shift registers

**Tasks:**
1. Read Appendix A §A.6–A.8.
2. Exercise: an 11-bit shift register with parallel load and MSB-first serial output.
3. Exercise: convert between `std_logic_vector`, `unsigned` and `integer` in all directions.
4. Exercise: index and slice a vector; deliberately trigger a `bound check failure` and read the error message.

**Exit criterion:** shift register verified; you can convert between the three types without consulting notes.

---

### DAY 9 — VHDL IV: self-checking testbenches

**Tasks:**
1. Read Appendix A §A.9 and §4.4.
2. Rewrite **all** of Days 6–8's testbenches to be self-checking with `assert`.
3. Run with `--assert-level=error`. Confirm a deliberately broken design **fails** and returns a non-zero exit code.
4. Confirm `echo $?` returns non-zero on failure and zero on success — this is what makes `regress.sh` work.

**Exit criterion:** a broken design causes a non-zero exit; a correct one exits zero. **Rule 3 is now operational.**

---

### DAY 10 — VHDL V: hierarchy and structural composition

**Tasks:**
1. Read Appendix A §A.10.
2. Exercise: instantiate the Day 8 shift register **inside** the Day 7 FSM using `port map`.
3. Verify the composed design.
4. Practise both instantiation styles (direct entity instantiation and component declaration); adopt direct instantiation as the project standard — it is less error-prone.

**Exit criterion:** a two-level hierarchical design that works. `can_node` is this pattern with eight submodules.

---

### DAY 11 — Integration exercise: a small UART transmitter

**Goal:** build one complete, real serial transmitter before attempting CAN.

**Tasks:**
1. Write a UART TX: 8N1, configurable baud via a `constant` divisor.
2. Structure it exactly as CAN will be: a baud-rate generator, a shift register, an FSM.
3. Self-checking testbench: transmit `0x55` and `0xA5`, assert on each expected bit.
4. Verify start bit, 8 data bits LSB-first, stop bit, and correct bit period.

**Exit criterion:** UART TX passes its self-checking testbench.

**Why this is worth a day:** UART is CAN's structure without the difficulty. Everything you learn here transfers directly, and any confusion surfaces on a design where the correct answer is obvious.

---

### DAY 12 — BUFFER + consolidation

**Tasks:**
1. Absorb slip.
2. Delete the throwaway exercises (keep the UART — it is good report material as a methodology note).
3. Re-read Parts 1 and 3 now that VHDL makes sense. **They will read very differently.**
4. Write a one-page summary of the CAN frame format from memory; check it against §1.3.

**Exit criterion:** you can sketch the standard CAN frame from memory and explain each field.

---

## PHASE 2 — ANALOG PHYSICAL LAYER (Days 13–22)

*Raw ngspice throughout. eSim stays closed.*

### DAY 13 — DC levels and driver verification

**Tasks:**
1. Write `spice/phy_dc.cir` (Appendix B.1): one driver, both terminations, bias network.
2. Run an operating point in both driver states.
3. **Measure and record:** `V(canh)`, `V(canl)`, `V_diff`, driver current — in both states.
4. Compare against §3.8: recessive 2.5/2.5/0.000 V; dominant 3.500/1.500/2.000 V; I = 33.333 mA.
5. If levels are wrong, **re-derive** rather than tune. Understand the error.

**Exit criterion:** measured levels within **±50 mV** of predicted; current within **±1 mA** of 33.333 mA. All logged in `docs/measurements.md` alongside predictions.

---

### DAY 14 — Comparator, bridges, digital loopback

**Tasks:**
1. Extend to `spice/phy_loopback.cir` (Appendix B.2): `tanh` comparator, `dac_bridge`, `adc_bridge`.
2. Drive TX with a 125 kHz `PULSE`.
3. `.tran 100n 200u`.
4. Plot: `TX_digital`, `V(canh)`, `V(canl)`, `V_diff`, `comparator_out`, `RX_digital`.
5. **Measure:** total TX→RX loop delay.
6. Verify polarity end-to-end: TX = 0 → dominant → RX = 0.

**Exit criterion:** RX reproduces TX faithfully; loop delay < 1 tq (500 ns), measured and logged.

---

### DAY 15 — Edge rates and capacitance study

**Tasks:**
1. Measure the dominant and recessive edges with `.measure`:
   ```
   .measure tran tr_dom TRIG v(canh) VAL=2.6 RISE=1 TARG v(canh) VAL=3.4 RISE=1
   ```
2. Compare against the predicted 39.6 ns.
3. Sweep `C_CANH`/`C_CANL` over 100 pF, 500 pF, 1 nF, 5 nF, 10 nF. Record rise time for each.
4. Plot rise time vs capacitance; confirm the linear relationship `t_r = 2.2 × R_src × C_diff`.
5. Identify the capacitance at which the edge becomes a significant fraction of a tq (500 ns) — this is the practical bus-loading limit.

**Exit criterion:** measured rise time within **±10%** of 39.6 ns; a rise-time-vs-capacitance table with the theoretical fit.

**Report value:** this is a genuine parametric study, not just a working circuit.

---

### DAY 16 — Wired-AND demonstration ⭐

**Goal:** the electrical proof underpinning the entire arbitration claim.

**Tasks:**
1. `spice/phy_wired_and.cir` (Appendix B.3): **three** drivers, one bus, three independent digital inputs.
2. Drive with three PULSE sources at different rates so all 8 combinations occur.
3. Plot the three TX inputs and `V_diff`.
4. **Build a truth table from the measured waveform.**
5. **Measure `V_diff` for n = 1, 2, 3 simultaneous dominant drivers.** Compare against §3.8.3: 2.000 V / 2.857 V / 3.333 V.

**Exit criterion:** a measured 3-input truth table proving `bus = TX₁ AND TX₂ AND TX₃`, **and** measured multi-driver differential voltages matching the predicted table within ±100 mV.

**Screenshot → `docs/waveforms/day16_wired_and.png`. This goes in the report.**

---

### DAY 17 — Transmission line model

**Tasks:**
1. `spice/phy_tline.cir`: replace the ideal wire between two nodes with a transmission line, `Z0 = 120`, `TD = 1.1u` (§3.4).
2. Place one driver at each end, terminations at both ends.
3. **Measure the actual propagation delay** from a driver edge at one end to the arrival at the other.
4. Compare against the predicted 1.100 µs.
5. Express the delay in tq: `1.100 µs / 500 ns = 2.2 tq`.
6. Confirm this is comfortably inside PROP_SEG = 5 tq, and note the round-trip figure: `2 × (1.1 + 0.15) = 2.5 µs = 5 tq` — exactly the design limit.

**Exit criterion:** measured delay within ±5% of 1.100 µs; the round-trip budget shown to match PROP_SEG exactly.

**This is the day PROP_SEG stops being an arbitrary number and becomes a derived one.**

---

### DAY 18 — Reflection and termination study

**Tasks:**
1. Run `phy_tline.cir` with correct 120 Ω terminations. Record clean edges.
2. Remove one termination (open circuit). Observe and **measure** the reflection amplitude and ringing period.
3. Set one termination to 60 Ω (over-terminated). Observe.
4. Set one to 1 kΩ (under-terminated). Observe.
5. Compute the reflection coefficient for each case and compare with measurement:
   ```
   Γ = (R_L − Z₀) / (R_L + Z₀)
   open:    Γ = +1.00
   1 kΩ:    Γ = (1000−120)/(1000+120) = +0.786
   120 Ω:   Γ = 0.000
   60 Ω:    Γ = (60−120)/(60+120) = −0.333
   ```
6. Determine whether the reflections would cause a false read at the sample point.

**Exit criterion:** measured reflection amplitudes within ±15% of the computed Γ for all four cases; a stated conclusion about sample-point robustness.

---

### DAY 19 — Common-mode rejection

**Tasks:**
1. Inject a common-mode disturbance: a voltage source in series with the ground reference of the bus, or equal-amplitude noise onto both CANH and CANL.
2. Apply 1 V p-p at 1 MHz common-mode.
3. Measure the resulting differential disturbance.
4. Compute CMRR:
   ```
   CMRR = 20 log₁₀(V_common / V_differential_error)  dB
   ```
5. Confirm RX remains correct throughout.
6. Increase the disturbance until RX fails; record the threshold.

**Exit criterion:** measured CMRR figure and a stated common-mode immunity limit. RX unaffected at 1 V p-p.

**Report value:** this directly demonstrates *why* CAN uses differential signalling — a strong section that most submissions will not have.

---

### DAY 20 — Multi-bit-rate PHY validation

**Tasks:**
1. Re-run the loopback at 125 k, 250 k, 500 k and 1 Mbit/s.
2. For each, measure the eye opening at the sample point (the margin between the signal and the 0.9 V / 0.5 V thresholds).
3. Confirm the §3.5 table: max bus length 220 / 95 / 32 / 1.3 m.
4. For the LONG configuration, demonstrate that at 1 Mbit/s over 220 m the round-trip delay **exceeds** PROP_SEG and arbitration would fail.

**Exit criterion:** a completed bit-rate table with measured eye openings, and a demonstrated failure case at high rate / long bus.

---

### DAY 21 — PHY documentation freeze

**Tasks:**
1. Consolidate every PHY measurement into `docs/measurements.md` with predicted vs measured vs % error.
2. Finalise the §3.8.8 parameter table with **measured** values beside the derived ones.
3. Write the PHY section of the report (~1500 words) while it is fresh.
4. Clean up and comment all SPICE netlists.
5. Commit and tag: `git tag phase2-complete`

**Exit criterion:** PHY report section drafted; all netlists commented; tag pushed.

---

### DAY 22 — BUFFER

Absorb slip. If on schedule, extend the reflection study to a stub-length analysis (what happens with long drop cables from the main trunk) — a genuinely interesting CAN topology issue.

---

## PHASE 3 — BIT TIMING AND SYNCHRONISATION (Days 23–28)

### DAY 23 — Bit timing core

**Tasks:**
1. Write `can_bit_timing.vhdl` (Appendix C.1) — **16 tq, constants not generics**.
2. Outputs: `bit_start`, `sample_pt`, `tq_index`, `seg_state`.
3. Self-checking testbench: assert `bit_start` period = 16 clocks, `sample_pt` at tq 12.
4. Verify in GTKWave and by assertion.

**Exit criterion:** testbench passes; measured `bit_start` period = 8.000 µs, `sample_pt` at 6.000 µs.

---

### DAY 24 — Hard synchronisation

**Tasks:**
1. Add a `hard_sync` input that restarts the tq counter unconditionally.
2. Testbench: assert `hard_sync` at various points within a bit; confirm the counter restarts and the next sample point lands exactly 12 tq later.
3. Assert this for at least 5 different sync positions.

**Exit criterion:** hard sync verified from 5 different in-bit positions, all self-checked.

---

### DAY 25 — Resynchronisation ⭐

**Goal:** implement the mechanism v1.0 omitted.

**Tasks:**
1. Add a `resync_edge` input (recessive→dominant edge detected during a frame).
2. Compute the phase error `e` = current tq index − SYNC_SEG position.
3. Apply the §1.6.3 rules:
   - `e > 0` and before the sample point → lengthen PHASE_SEG1 by `min(e, SJW)`
   - after the sample point → shorten PHASE_SEG2 by `min(16 − tq_index, SJW)`
4. Implement by adjusting the terminal count for the current bit only.
5. Self-checking testbench: apply edges at tq = 3, 7, 11, 14 and assert the resulting bit length is 16 + correction or 16 − correction, clamped to SJW = 4.

**Exit criterion:** all four resynchronisation cases verified by assertion, with the SJW clamp confirmed at `e > 4`.

**Watch for bug P14** — an inverted sign here makes drift worse, not better, and the symptom looks like a completely different problem.

---

### DAY 26 — Oscillator tolerance demonstration ⭐

**Goal:** prove resynchronisation works, and that the theory predicts the boundary.

**Tasks:**
1. Testbench with **two** `can_bit_timing` instances on slightly different clocks.
2. Run four experiments:

| # | Node B clock | Relative error | Resync | Predicted |
|---|---|---|---|---|
| 1 | 2.000 MHz | 0% | on | pass |
| 2 | 1.990 MHz | −0.5% | on | **pass** (0.5% < 0.98%) |
| 3 | 1.970 MHz | −1.5% | on | **fail** (1.5% > 0.98%) |
| 4 | 1.990 MHz | −0.5% | **off** | **fail** — proves resync is doing the work |

3. Measure the accumulated phase error over a 63-bit frame in each case.
4. Compare the observed failure boundary against the derived 0.98%.

**Exit criterion:** all four outcomes match prediction; the measured tolerance boundary is within ±0.2% of the derived 0.98%.

**This is one of your three strongest results.** It demonstrates the mechanism, quantifies it, and validates the theory in a single experiment.

---

### DAY 27 — Sample-point sweep study

**Tasks:**
1. Parameterise the segment split via constants; build variants at 62.5%, 68.75%, 75%, 81.25%, 87.5%.
2. For each, compute SJW, oscillator tolerance (both conditions), and maximum bus length.
3. Tabulate; identify the trade-off curve.
4. Confirm the §3.2 choice of 75% is defensible, and state under what conditions 87.5% would be better.

**Exit criterion:** a completed 5-row trade-off table with derived numbers. This becomes a report figure.

---

### DAY 28 — BUFFER

Absorb slip. Commit; `git tag phase3-complete`.

---

## PHASE 4 — TRANSMIT PATH (Days 29–38)

### DAY 29 — CRC-15 with an independent reference

**Tasks:**
1. Write `python/crc15_ref.py`:
   ```python
   def can_crc15(bits):
       crc = 0
       for b in bits:
           nxt = b ^ ((crc >> 14) & 1)
           crc = (crc << 1) & 0x7FFF
           if nxt:
               crc ^= 0x4599
       return crc
   ```
2. Generate golden vectors for: all zeros (35 bits), all ones (35 bits), Node A's actual frame prefix, and two random patterns. Save to `python/vectors/`.
3. Write `can_crc15.vhdl` (Appendix C.2).
4. Self-checking testbench asserting against **all five** golden vectors.

**Exit criterion:** VHDL CRC matches the Python reference on 5/5 vectors, verified by assertion.

**Why an independent reference matters:** checking VHDL against VHDL proves only self-consistency. Python is written from the specification, independently, and catches specification misreadings.

---

### DAY 30 — Bit stuffer

**Tasks:**
1. Write `can_stuffer.vhdl` per §5.7.
2. Self-checking testbench: input 20 identical bits → assert exactly 4 stuff bits at the correct positions.
3. Additional cases: alternating bits (0 stuff bits), 5 identical then a change (0 stuff bits), 6 identical (1 stuff bit).

**Exit criterion:** four stuffing scenarios verified by assertion.

---

### DAY 31 — The stall handshake ⭐

**Goal:** a dedicated day for the interface that v1.0 under-specified and that causes bug P9.

**Tasks:**
1. Implement `stuff_active` exactly as specified in §5.7.
2. Build a mock FSM that emits a known 20-bit pattern and **honours the stall**.
3. Assert that the stuffer output, with stuff bits removed, is bit-identical to the FSM's intended pattern.
4. Test the boundary case: a stuff bit required on the *last* bit of the stuffed region.
5. Test back-to-back stuff bits (possible when the inserted bit itself starts a new run of 5).

**Exit criterion:** the stall handshake verified across normal, boundary and back-to-back cases, all self-checked.

**Do not skip or shorten this day.** Getting this wrong later looks like a CRC bug, a framing bug, or a receiver bug — three days of misdirected debugging.

---

### DAY 32 — TX FSM: IDLE, SOF, arbitration field

**Tasks:**
1. Write `can_tx_fsm.vhdl`. States: `IDLE → SOF → ID_A → RTR_SRR → IDE → …`
2. Load ID from the constant table selected by `node_sel`.
3. Self-checking testbench asserting the first 14 bits against the expected pattern for each of nodes A, B, C.

**Exit criterion:** bits 0–13 correct for all three standard nodes, asserted.

---

### DAY 33 — TX FSM: control and data fields

**Tasks:**
1. Add `IDE → R0 → DLC → DATA`.
2. Wire in `can_crc15`, enabled over SOF..DATA and gated to **exclude stuff bits**.
3. Self-checking testbench through the end of the data field.

**Exit criterion:** bits 0–35 correct and asserted; CRC register value at end of data matches the Python reference.

---

### DAY 34 — TX FSM: CRC, ACK, EOF, IFS

**Tasks:**
1. Add `CRC → CRC_DELIM → ACK → ACK_DELIM → EOF → IFS → IDLE`.
2. Disable stuffing from CRC_DELIM onward.
3. Full-frame self-checking testbench: assert all 60 bits.
4. Measure the total frame duration.

**Exit criterion:** complete 60-bit frame asserted bit by bit; measured duration = 504 µs (+8 µs per stuff bit), matching §3.6.

---

### DAY 35 — Extended frame support

**Tasks:**
1. Add extended-frame states: `ID_A → SRR → IDE → ID_B → RTR → R1 → R0 → …`
2. Select frame format via a `frame_format` constant per node (Node D = extended).
3. Self-checking testbench for the full 80-bit extended frame.
4. Verify the CRC now covers 55 bits.

**Exit criterion:** extended frame asserted bit by bit; duration = 664 µs; CRC coverage confirmed at 55 bits.

---

### DAY 36 — Remote frames

**Tasks:**
1. Add RTR = 1 handling: DLC transmitted, data field **skipped**.
2. Self-checking testbench for a standard remote frame: 44 bits + 3 IFS.
3. Confirm the CRC covers 19 bits (1+11+1+1+1+4) with no data.

**Exit criterion:** remote frame asserted; duration = 376 µs.

---

### DAY 37 — Transmit path integration

**Tasks:**
1. Compose `can_bit_timing` + `can_tx_fsm` + `can_crc15` + `can_stuffer` into `can_tx_top`.
2. Self-checking testbench covering all four frame types (standard, extended, remote, and a stuff-heavy payload).
3. Produce one clean, **annotated** full-frame waveform.

**Exit criterion:** all four frame types pass; annotated waveform saved to `docs/waveforms/day37_tx_frames.png`.

---

### DAY 38 — BUFFER

Absorb slip. `git tag phase4-complete`.

---

## PHASE 5 — RECEIVE PATH (Days 39–45)

### DAY 39 — Destuffer

**Tasks:**
1. Write `can_destuffer.vhdl` with an `rx_valid` strobe (§5.7).
2. Raise `stuff_error` on 6 consecutive identical bits.
3. **Round-trip test:** feed Day 30's stuffer output in; assert the recovered stream is bit-identical to the original.
4. Separately inject 6 identical bits; assert `stuff_error`.

**Exit criterion:** round trip bit-exact; stuff error detected. **This round-trip test catches almost every stuffing bug — treat a failure here as important.**

---

### DAY 40 — RX FSM: SOF detection and field decode

**Tasks:**
1. Write `can_rx_fsm.vhdl`: detect the recessive→dominant SOF edge while idle, issue `hard_sync`, then shift in fields.
2. Outputs: `rx_id`, `rx_rtr`, `rx_ide`, `rx_dlc`, `rx_data`.
3. Self-checking testbench fed from Day 37's transmitter output. Assert ID = `0x0A5`, DLC = 2, data = `0xA53C`.

**Exit criterion:** all decoded fields asserted correct.

---

### DAY 41 — RX FSM: extended frame decode

**Tasks:**
1. Branch on the IDE bit to select standard vs extended decoding.
2. Assemble the 29-bit ID from ID_A and ID_B.
3. Self-checking testbench: assert full ID = `0x297ABCD` for Node D's frame.

**Exit criterion:** extended ID reassembled and asserted correct.

**Watch for bug P15** — the IDE bit position differs between formats; sampling it at the wrong index causes silent misdecoding.

---

### DAY 42 — RX FSM: CRC checking

**Tasks:**
1. Instantiate a second `can_crc15` in the receiver, enabled over the same coverage and gated on `rx_valid` (stuff bits excluded).
2. Compare against the received CRC; output `crc_ok`.
3. Self-checking testbench: valid frame → `crc_ok` = 1. Corrupt one data bit → `crc_ok` = 0.
4. Test corruption at 5 different bit positions.

**Exit criterion:** CRC passes on valid frames and fails on all 5 corrupted variants.

---

### DAY 43 — RX FSM: ACK generation

**Tasks:**
1. Assert `ack_drive` during the ACK slot **only if** `crc_ok`.
2. Testbench: valid frame → ACK driven; invalid CRC → ACK withheld.
3. Verify the ACK is exactly one bit long and correctly positioned.

**Exit criterion:** ACK behaviour verified for both cases, position asserted.

---

### DAY 44 — Acceptance filtering

**Tasks:**
1. Write `can_filter.vhdl` implementing `(rx_id XOR filter_id) AND filter_mask == 0`.
2. Configure per §3.7.3.
3. Self-checking testbench with 6 cases: exact match, exact mismatch, range match, range boundary (both edges), promiscuous.

**Exit criterion:** all 6 filter cases asserted correct.

**Note:** filtering affects `rx_valid` to the *host*, not ACK generation — a node acknowledges every correctly-received frame regardless of its filter. Getting this wrong breaks the bus. Assert it explicitly.

---

### DAY 45 — Receive path integration + BUFFER

**Tasks:**
1. Compose the full receive chain.
2. End-to-end testbench: `can_tx_top` → `can_rx_top`, all four frame types.
3. Absorb any slip. `git tag phase5-complete`.

**Exit criterion:** all four frame types transmitted and received correctly, end to end, self-checked.

---

## PHASE 6 — ERROR MANAGEMENT (Days 46–56)

### DAY 46 — Bit error detection

**Tasks:**
1. In `can_tx_fsm`, compare transmitted vs sampled bit at every sample point **outside** the arbitration field and ACK slot.
2. Mismatch → `bit_error`.
3. Self-checking testbench: force a mismatch during the data field; assert `bit_error`. Confirm **no** error during arbitration or ACK.

**Exit criterion:** bit error detected in the data field; correctly suppressed in arbitration and ACK slot.

---

### DAY 47 — Stuff and form errors

**Tasks:**
1. Stuff error already exists (Day 39) — wire it into the error manager.
2. Add form error: check CRC delimiter = 1, ACK delimiter = 1, EOF = all 1s.
3. Self-checking testbench: corrupt each fixed-form field in turn; assert `form_error` for each.

**Exit criterion:** stuff error and all three form-error positions detected and asserted.

---

### DAY 48 — CRC and ACK errors

**Tasks:**
1. CRC error already exists (Day 42) — wire it in.
2. Add ACK error: transmitter samples the ACK slot; recessive → `ack_error`.
3. Self-checking testbench: run with no receiver present; assert `ack_error`.

**Exit criterion:** all **five** error types now detected, each with a passing assertion. Record the five in `docs/measurements.md`.

---

### DAY 49 — Error frame transmission (error-active)

**Tasks:**
1. Write `can_error_mgmt.vhdl`.
2. On any error, transmit **6 dominant bits** followed by **8 recessive** delimiter bits.
3. Abort the current frame immediately on error.
4. Self-checking testbench: assert the error frame is 14 bits minimum with the correct pattern.

**Exit criterion:** error frame transmitted with correct structure and length, asserted.

---

### DAY 50 — Error flag superposition

**Tasks:**
1. Model two nodes both detecting the same error; both transmit flags starting at slightly different bit times.
2. Confirm the superposed dominant sequence is 6–12 bits.
3. Confirm the delimiter begins only after the bus returns recessive.
4. Self-checking testbench for both the aligned and the offset case.

**Exit criterion:** superposition produces 6–12 dominant bits; delimiter correctly delayed. Both cases asserted.

**Watch for bug P11** — a node that stops driving after exactly 6 bits regardless of bus state breaks superposition.

---

### DAY 51 — TEC and REC counters

**Tasks:**
1. Implement the §1.8 increment/decrement rules.
2. **Gate every increment on a single-cycle pulse**, not a level (bug P12).
3. Self-checking testbench: drive a sequence of errors and successes; assert the counter values after each.
4. Test the floor at 0 and saturation behaviour.

**Exit criterion:** counter values match a hand-computed sequence of at least 10 events, asserted at each step.

---

### DAY 52 — Error-active / error-passive states

**Tasks:**
1. Implement state transitions at TEC/REC > 127.
2. In error-passive, transmit **recessive** error flags.
3. Implement the 8-bit suspend transmission after each frame in error-passive.
4. Self-checking testbench: drive TEC past 127; assert the state change and the recessive flag.

**Exit criterion:** state transition at exactly TEC = 128; recessive flags confirmed; suspend transmission = 8 bits, asserted.

---

### DAY 53 — Bus-off and recovery

**Tasks:**
1. Bus-off at TEC > 255: disable drivers entirely.
2. Recovery: count occurrences of **11 consecutive recessive bits**; after `BUSOFF_RECOVERY_COUNT` (= 8 for simulation), reset TEC/REC to 0 and return to error-active.
3. Self-checking testbench: drive TEC to 256; assert bus-off; supply the recessive sequences; assert recovery.
4. Confirm the node takes no part in bus activity while bus-off.

**Exit criterion:** bus-off entered at TEC = 256; recovery after exactly 8 × 11 recessive bits; asserted.

**Document the scaling.** `BUSOFF_RECOVERY_COUNT = 8` instead of 128 is a deliberate simulation accommodation (§1.8) — state it in the report with the reason and the real value.

---

### DAY 54 — Overload frames

**Tasks:**
1. Generate an overload frame (6 dominant + 8 recessive) when a dominant bit is detected during intermission.
2. Self-checking testbench asserting structure and trigger condition.

**Exit criterion:** overload frame generated on the correct trigger, structure asserted.

---

### DAY 55 — Automatic retransmission

**Tasks:**
1. After arbitration loss or error, the node re-arms and retransmits once the bus is idle (3 recessive bits of intermission, plus 8 more if error-passive).
2. Add a retransmission attempt counter for observability.
3. Self-checking testbench: force an arbitration loss; assert the frame is retransmitted and completes.

**Exit criterion:** frame lost to arbitration is successfully retransmitted, asserted.

**This completes the arbitration story** — the loser does not merely detect the loss, it recovers from it.

---

### DAY 56 — BUFFER

Absorb slip. Run the full regression. `git tag phase6-complete`.

---
## PHASE 7 — NODE INTEGRATION AND FIRST MIXED-SIGNAL RUN (Days 57–63)

### DAY 57 — `can_node` top-level assembly

**Tasks:**
1. Write `can_node.vhdl` instantiating all eight submodules.
2. Internal wiring per the §2.3 dataflow.
3. Compile clean under GHDL with **zero warnings**.

**Exit criterion:** `can_node` elaborates with no warnings.

---

### DAY 58 — Port freeze and two-node GHDL loopback ⭐

**Goal:** lock the interface before it becomes expensive to change (Rule 2).

**Tasks:**
1. Finalise the port list:

```vhdl
entity can_node is
  port (
    clk          : in  std_logic;                     -- 2 MHz tq clock
    rst          : in  std_logic;                     -- active high
    node_sel     : in  std_logic_vector(1 downto 0);  -- 00=A 01=B 10=C 11=D
    tx_req       : in  std_logic;                     -- request transmission
    can_rx       : in  std_logic;                     -- from bus comparator
    can_tx       : out std_logic;                     -- to bus driver
    tx_done      : out std_logic;
    arb_lost     : out std_logic;
    rx_valid     : out std_logic;
    bit_error    : out std_logic;
    stuff_error  : out std_logic;
    crc_error    : out std_logic;
    form_error   : out std_logic;
    ack_error    : out std_logic;
    err_passive  : out std_logic;
    bus_off      : out std_logic
  );
end entity;
```

2. **Write this port list into `LOG.md` and mark it FROZEN.**
3. Two-node testbench with the wired-AND modelled digitally: `bus <= tx_a and tx_b;`
4. Assert: A transmits, B receives, B acknowledges, A sees the ACK.

**Exit criterion:** two nodes communicate in pure VHDL, self-checked. Port list frozen and documented.

**16 ports.** If Day 4 showed vectors are unsupported, replace `node_sel(1:0)` with two scalars `node_sel0`, `node_sel1` — still 17 scalar ports, entirely workable.

---

### DAY 59 — NGHDL model generation

**Tasks:**
1. eSim → NGHDL → upload `can_node.vhdl`
2. **Restart eSim**
3. Confirm the symbol appears with the correct pin count and pin names
4. Verify pin order matches the entity declaration order (§5.5 S10)

**Exit criterion:** `can_node` symbol available in KiCad with all 16 pins correct.

**If stuck (4 h):** §5.5 S4/S6/S9/S10. If vector ports fail here, apply the Day 4 fallback — it should be a mechanical change since the decision was pre-made.

---

### DAY 60 — Single-node schematic

**Tasks:**
1. In Eeschema, draw the complete single-node circuit:
   - `can_node` symbol
   - `can_tx` → `dac_bridge` → driver switch pair
   - CANH/CANL with two 120 Ω terminations, bias network, 1 nF each
   - comparator → `adc_bridge` → `can_rx`
   - 2 MHz clock source → `adc_bridge` → `clk`
   - reset source → `adc_bridge` → `rst`
2. Label every net clearly — you will read these plots dozens of times.
3. Add a title block.
4. **Do not simulate yet.** Check the schematic against §2.3 and §3.8 first.

**Exit criterion:** complete, labelled schematic; a manual review against the block diagram finds no discrepancies.

---

### DAY 61 — First mixed-signal simulation ⭐

**Tasks:**
1. KiCad-to-Ngspice → every tab → Convert
2. Simulate with `.tran 100n 1.5m`
3. Plot: `V(canh)`, `V(canl)`, `V_diff`, `can_tx`, `can_rx`, `tx_done`
4. Verify: a complete CAN frame appears as real analog waveforms; the node's own receiver decodes it (self-reception)

**Exit criterion:** a full CAN frame visible on analog CANH/CANL; frame duration measured at 504 µs (+ stuff bits).

**Expect this to fail first time.** Day 62 exists for that.

---

### DAY 62 — Integration debugging

Work §5.4 and §5.5 systematically. Most likely, in order of probability:

1. **Clock not reaching the VHDL block** (S11) — probe the `adc_bridge` output driving `clk` first, always
2. **Convergence failure** (N1) — apply the ladder in order
3. **Polarity inversion** somewhere in TX→bus→RX — plot every intermediate node
4. **Incomplete netlist** — a Kicad-to-Ngspice tab was skipped
5. **Reset never released** (S12)

**Exit criterion:** Day 61's exit criterion met.

**If still stuck at end of day:** replace `can_node` with a trivial VHDL block that just toggles `can_tx` at 125 kHz. If *that* drives the bus correctly, the analog side is proven and the problem is in your VHDL or the netlist — bisect from there (§5.8).

---

### DAY 63 — BUFFER

Absorb slip. `git tag phase7-complete`. Capture a clean single-node mixed-signal waveform for the report.

---

## PHASE 8 — MULTI-NODE AND ARBITRATION (Days 64–70)

### DAY 64 — Arbitration logic (GHDL first)

**Tasks:**
1. In `can_tx_fsm`, during the arbitration field, at each sample point:
   ```vhdl
   if arb_field = '1' and tx_bit = '1' and rx_bit = '0' then
       arb_lost <= '1';
       state    <= BECOME_RECEIVER;
   end if;
   ```
2. **Only `tx=1, rx=0` is a loss** (bug P6). `tx=0, rx=0` is winning.
3. On loss: stop driving (go recessive), switch to receiving the winner's frame, re-arm for retransmission.
4. GHDL testbench with a digital wired-AND: two nodes, assert the correct one loses at the correct bit.

**Exit criterion:** in GHDL, the lower-ID node completes; the higher-ID node asserts `arb_lost` at the predicted bit index and stops driving. Asserted, not eyeballed.

---

### DAY 65 — Two-node arbitration in eSim

**Tasks:**
1. Duplicate node + driver + comparator in the schematic. **Each node needs its own driver and its own comparator** — they share only CANH/CANL.
2. `node_sel` = A (`0x0A5`) and B (`0x123`).
3. Assert both `tx_req` simultaneously.
4. Plot: both `can_tx`, both `arb_lost`, `V_diff`.

**Exit criterion:** Node B asserts `arb_lost` at **ID bit 8**, exactly as §3.7.1 predicts. Node A's frame completes unaffected. Bit position measured from the waveform, not assumed.

---

### DAY 66 — Three-node arbitration ⭐⭐ THE HEADLINE RESULT

**Tasks:**
1. Add Node C (`0x2AA`).
2. All three `tx_req` simultaneously.
3. Simulate `.tran 100n 2.5m`.
4. Verify against §3.7.1: **C loses at ID bit 9, B loses at ID bit 8, A wins.**
5. Also confirm the multi-driver differential voltage steps: 3 drivers dominant → ~3.33 V, then 2 → ~2.86 V, then 1 → 2.00 V. **This is visible in the waveform and is direct evidence that the wired-AND is electrical, not logical.**
6. Produce a carefully annotated waveform: label bit positions, mark both dropout points, show `V_diff` alongside the three `can_tx` signals.

**Exit criterion:** staged dropout matches §3.7.1 exactly; multi-driver voltage steps match §3.8.3 within ±100 mV.

**Screenshot → `docs/waveforms/day66_arbitration_3node.png`.** This is the single most important image in your report. Spend real time making it legible.

---

### DAY 67 — Standard vs extended arbitration

**Tasks:**
1. Add Node D (extended, base ID `0x0A5` — identical to Node A's).
2. A and D transmit simultaneously.
3. Verify §3.7.2: identical through all 11 base ID bits, then D loses at the **SRR** bit because A sends RTR = 0 (dominant) while D must send SRR = 1 (recessive).
4. Capture and annotate.

**Exit criterion:** D loses at the SRR bit position, confirming the standard-beats-extended priority rule.

**Why this matters:** it demonstrates you implemented the *protocol*, not just a bit-comparison loop. Very few submissions will show this.

---

### DAY 68 — Retransmission after arbitration loss

**Tasks:**
1. With retransmission enabled (Day 55), run the 3-node scenario.
2. Verify: A's frame completes; after intermission, B and C contend again; B wins (lower ID); then C transmits.
3. Measure the total time for all three frames to complete.
4. Compare against the predicted sum of frame durations plus intermissions.

**Exit criterion:** all three frames eventually transmit, in ID priority order. Total time within 5% of prediction.

**This is the complete arbitration story:** contention → resolution → recovery → eventual delivery of every message.

---

### DAY 69 — Multi-receiver acknowledgement

**Tasks:**
1. With A transmitting and B, C, D all receiving, verify **all three** drive the ACK slot dominant simultaneously.
2. Measure `V_diff` during the ACK bit — with three drivers it should be ~3.33 V (§3.8.3).
3. Disable all receivers; confirm `ack_error` at the transmitter.
4. Enable exactly one receiver; confirm ACK succeeds with `V_diff` ≈ 2.0 V.

**Exit criterion:** ACK verified with 3, 1 and 0 receivers; the differential voltage in each case matches the multi-driver table.

**Nice detail:** the ACK slot voltage *tells you how many nodes acknowledged*. That is a genuinely elegant observation and worth a paragraph in the report.

---

### DAY 70 — BUFFER

Absorb slip. `git tag phase8-complete`. This is the project's high-water mark — make sure everything is committed and pushed.

---

## PHASE 9 — ADVANCED STUDIES (Days 71–76)

*This phase is what "no time constraint" buys you. Each study is a distinct report section and each produces a quantitative result.*

### DAY 71 — Propagation delay and arbitration

**Tasks:**
1. Switch to the LONG bus configuration (transmission line, §2.3).
2. Run 3-node arbitration at 220 m. Confirm it still works.
3. Increase to 300 m, 400 m, 500 m. Find the length at which arbitration **fails**.
4. Compare the measured failure length against the derived 220 m limit, allowing for the conservative `t_trx` assumption.
5. Explain the failure mechanism from the waveform: the losing node's dominant bit arrives after the winner's sample point.

**Exit criterion:** measured maximum working bus length, with the failure mechanism explained from waveform evidence.

**This is the day PROP_SEG earns its existence.** Without it, PROP_SEG is a number in a table; with it, it is a measured engineering constraint.

---

### DAY 72 — Bit-rate scaling

**Tasks:**
1. Re-derive the timing tables for 250 k, 500 k, 1 Mbit/s (§3.5).
2. Rebuild the VHDL constants for each (clock frequency changes; segment ratios stay).
3. Run a single frame at each rate; verify correct operation on the SHORT bus.
4. On the LONG bus, find the maximum working length at each rate.
5. Plot maximum bus length vs bit rate; compare against §3.5 and against the published CAN limits.

**Exit criterion:** a four-point measured curve of bus length vs bit rate, compared against theory.

---

### DAY 73 — Oscillator mismatch across nodes

**Tasks:**
1. Give each of the three nodes a slightly different clock frequency, within ±0.5%.
2. Run 3-node arbitration and full frame exchange. Confirm resynchronisation holds everything together.
3. Increase the spread until communication fails; record the threshold.
4. Compare against the Day 26 single-link result and the derived 0.98%.

**Exit criterion:** measured multi-node tolerance threshold, compared against theory and against the two-node result.

---

### DAY 74 — Bus fault injection

**Tasks — run each as a separate simulation, capture each:**
1. **Missing termination** (one end open) — does the frame survive?
2. **Both terminations missing**
3. **CANH shorted to VCC**
4. **CANL shorted to GND**
5. **CANH shorted to CANL**
6. **One node's driver stuck dominant** — the classic "babbling idiot" failure

For each: record what the receivers see, which error types fire, and whether the offending node eventually goes bus-off.

**Exit criterion:** six fault scenarios characterised, each with the observed error type and node state.

**Fault 6 is the most interesting.** A node stuck dominant destroys the bus for everyone — and CAN's fault confinement is precisely the mechanism that eventually removes it. Demonstrating that closes the loop on your error-management work.

---

### DAY 75 — Noise immunity

**Tasks:**
1. Inject differential-mode noise of increasing amplitude; find the level at which bit errors appear.
2. Inject common-mode noise; confirm much higher immunity (Day 19 established the baseline).
3. Compute the ratio; express as an immunity margin.
4. Inject a single narrow glitch at the sample point vs between sample points; show that timing matters as much as amplitude.

**Exit criterion:** quantified differential and common-mode noise thresholds, with the ratio stated.

---

### DAY 76 — BUFFER

Absorb slip. `git tag phase9-complete`.

---

## PHASE 10 — VERIFICATION CAMPAIGN (Days 77–81)

### DAY 77 — Regression suite

**Tasks:**
1. Write `regress.sh` (§4.3).
2. Ensure every module has a self-checking testbench that returns a correct exit code.
3. Run the full suite; fix anything that has silently regressed.
4. Record the runtime — you will run this many times.

**Exit criterion:** `./regress.sh` runs every module testbench and reports `N passed, 0 failed`.

**Expect regressions.** Modules written in Phase 4 have been modified by Phase 6 work. This is exactly why Rule 3 exists.

---

### DAY 78 — VHDL test matrix

**Tasks:**
1. Execute the full Part 7 VHDL test matrix.
2. Record pass/fail and the measured value for each.
3. Fix any failures.

**Exit criterion:** every VHDL-domain row in the Part 7 matrix passes with a recorded number.

---

### DAY 79 — Mixed-signal test matrix

**Tasks:**
1. Execute every eSim-domain test in the Part 7 matrix.
2. Capture a waveform for each.
3. Record measured vs predicted for each.

**Exit criterion:** every mixed-signal row passes with a captured waveform and a recorded measurement.

---

### DAY 80 — Measurement consolidation

**Tasks:**
1. Complete `docs/measurements.md`: predicted, measured, absolute error, % error, for every parameter.
2. Identify anything with > 5% error and either explain it or investigate it.
3. Export all schematics from Eeschema as PDF and SVG.
4. **Re-run every simulation from a clean checkout** and confirm reproducibility.

**Exit criterion:** complete measurement table; every result reproducible from a clean clone.

**The clean-checkout test matters.** If it only works because of an uncommitted file on your machine, you will discover that now rather than when an examiner tries it.

---

### DAY 81 — BUFFER

Absorb slip. `git tag phase10-complete`.

---

## PHASE 11 — DOCUMENTATION AND SUBMISSION (Days 82–86)

### DAY 82 — Report: theory and design

**Tasks:** write sections 1–6 of the Part 8 structure (introduction through digital implementation). Pull directly from Parts 1–3 of this document and from `LOG.md`.

**Exit criterion:** sections 1–6 drafted, ~5000 words, with all derivations shown.

---

### DAY 83 — Report: results

**Tasks:** write sections 7–9 (integration, results, verification). Every waveform gets a caption stating what it proves and the measured number.

**Exit criterion:** sections 7–9 drafted, every figure captioned and referenced in the text.

---

### DAY 84 — Report: completion and review

**Tasks:**
1. Write sections 10–12 (limitations, conclusion, references).
2. **Be explicit about limitations:** no CAN FD, documented subset of fault confinement, scaled bus-off recovery count, simulated rather than physical transceiver. Stating boundaries precisely reads as competence.
3. Full read-through for consistency of numbers — every figure quoted in the text must match `docs/measurements.md`.

**Exit criterion:** complete report; no numerical inconsistencies.

---

### DAY 85 — Reproducibility package

**Tasks:**
1. Write `README.md`: exact steps to reproduce every result, from a clean clone.
2. Test it by following your own instructions in a fresh directory.
3. Assemble the submission package (§8.2).
4. Verify every file opens and every simulation runs.

**Exit criterion:** a third party could reproduce your headline results from the README alone.

---

### DAY 86 — Final review and submission

**Tasks:**
1. Re-read the original task statement. Tick every requirement:
   - Choose a communication protocol ✓
   - Model the transmitter and receiver ✓
   - Connect and simulate the system ✓
   - Verify the data transfer ✓
   - Include analog / digital / mixed signal as appropriate ✓
   - Follow the circuit-proposal procedure ✓
2. **Read the "propose the circuits" procedure page linked in the task.** I cannot verify its current contents; it may specify a format or a separate proposal step. Do not skip this.
3. Email **contact-esim@fossee.in**, subject exactly:
   `eSim Semester Long Internship - Autumn 2026 Submission Task 2`
4. Final commit, tag `v1.0-submitted`, push.
5. Archive the whole project off-machine.

**Exit criterion:** submitted, tagged, archived.

---

# PART 7 — VERIFICATION CAMPAIGN

## 7.1 Verification philosophy

Three levels, each catching a different class of bug:

| Level | Method | Catches |
|---|---|---|
| **Unit** | Self-checking GHDL testbench per module | Logic errors, boundary conditions |
| **Integration** | Multi-module GHDL testbenches | Interface mismatches, handshake errors |
| **System** | Mixed-signal eSim simulations | Analog/digital interaction, timing, real bus behaviour |

Every test has a **predicted** value derived from Part 3 and a **measured** value from simulation. A test without a number is not a test.

## 7.2 Test matrix

### Analog / PHY (ngspice)

| # | Test | Predicted | Day | Evidence |
|---|---|---|---|---|
| A1 | Recessive levels | CANH=CANL=2.500 V, V_diff=0 | 13 | `day13_dc.png` |
| A2 | Dominant levels | 3.500 / 1.500 / 2.000 V | 13 | `day13_dc.png` |
| A3 | Driver current | 33.333 mA | 13 | measurements |
| A4 | Driver power | 166.7 mW | 13 | measurements |
| A5 | Loop delay TX→RX | < 500 ns | 14 | `day14_loop.png` |
| A6 | Rise time | 39.6 ns ±10% | 15 | `day15_edges.png` |
| A7 | Rise time vs C | linear, 2.2·R_src·C_diff | 15 | table |
| A8 | **Wired-AND truth table** | bus = AND of all TX | 16 | `day16_wired_and.png` |
| A9 | 2 drivers dominant | V_diff = 2.857 V | 16 | measurements |
| A10 | 3 drivers dominant | V_diff = 3.333 V | 16 | measurements |
| A11 | Line propagation delay | 1.100 µs (220 m) | 17 | `day17_tline.png` |
| A12 | Round-trip vs PROP_SEG | 2.5 µs = 5 tq exactly | 17 | analysis |
| A13 | Reflection, open end | Γ = +1.00 | 18 | `day18_refl.png` |
| A14 | Reflection, 60 Ω | Γ = −0.333 | 18 | `day18_refl.png` |
| A15 | Reflection, 1 kΩ | Γ = +0.786 | 18 | `day18_refl.png` |
| A16 | Reflection, 120 Ω | Γ = 0 (no reflection) | 18 | `day18_refl.png` |
| A17 | Common-mode rejection | RX unaffected at 1 V p-p | 19 | `day19_cmrr.png` |
| A18 | Bus length vs bit rate | 220 / 95 / 32 / 1.3 m | 20, 72 | table + curve |

### Digital / VHDL (GHDL)

| # | Test | Predicted | Day | Evidence |
|---|---|---|---|---|
| D1 | Bit period | 8.000 µs (16 clk) | 23 | assertion |
| D2 | Sample point | tq 12 = 6.000 µs = 75% | 23 | assertion |
| D3 | Hard sync, 5 positions | counter restarts, sample +12 tq | 24 | assertion |
| D4 | Resync, late edge | PS1 lengthened by min(e,4) | 25 | assertion |
| D5 | Resync, early edge | PS2 shortened by min(\|e\|,4) | 25 | assertion |
| D6 | SJW clamp | correction ≤ 4 tq | 25 | assertion |
| D7 | **Osc tolerance −0.5%** | **passes** | 26 | `day26_osc.png` |
| D8 | **Osc tolerance −1.5%** | **fails** | 26 | `day26_osc.png` |
| D9 | **Resync disabled, −0.5%** | **fails** | 26 | `day26_osc.png` |
| D10 | CRC vs Python, 5 vectors | exact match | 29 | assertion |
| D11 | Stuffing, 20 identical | exactly 4 stuff bits | 30 | assertion |
| D12 | Stuffing, alternating | 0 stuff bits | 30 | assertion |
| D13 | Stall handshake | output minus stuff = input | 31 | assertion |
| D14 | Back-to-back stuff bits | handled correctly | 31 | assertion |
| D15 | Standard frame | 60 bits, 504 µs | 34 | assertion |
| D16 | Extended frame | 80 bits, 664 µs | 35 | assertion |
| D17 | Remote frame | 44 bits, 376 µs | 36 | assertion |
| D18 | Destuff round trip | bit-exact | 39 | assertion |
| D19 | Stuff error, 6 bits | detected | 39 | assertion |
| D20 | RX decode standard | ID 0x0A5, DLC 2, 0xA53C | 40 | assertion |
| D21 | RX decode extended | ID 0x297ABCD | 41 | assertion |
| D22 | CRC check, valid | crc_ok = 1 | 42 | assertion |
| D23 | CRC check, 5 corruptions | crc_ok = 0 for all | 42 | assertion |
| D24 | ACK generation | driven iff crc_ok | 43 | assertion |
| D25 | Filter, 6 cases | per §3.7.3 | 44 | assertion |
| D26 | Bit error | detected outside arbitration | 46 | assertion |
| D27 | Bit error suppressed | none in arbitration/ACK | 46 | assertion |
| D28 | Form error, 3 fields | detected each | 47 | assertion |
| D29 | ACK error | detected with no receiver | 48 | assertion |
| D30 | Error frame structure | 6 dominant + 8 recessive | 49 | assertion |
| D31 | Flag superposition | 6–12 dominant bits | 50 | assertion |
| D32 | TEC/REC, 10 events | matches hand computation | 51 | assertion |
| D33 | Error-passive at 128 | state change, recessive flags | 52 | assertion |
| D34 | Suspend transmission | 8 bits | 52 | assertion |
| D35 | Bus-off at TEC 256 | drivers disabled | 53 | assertion |
| D36 | Bus-off recovery | after 8 × 11 recessive | 53 | assertion |
| D37 | Overload frame | correct trigger + structure | 54 | assertion |
| D38 | Retransmission | frame completes on retry | 55 | assertion |

### Mixed-signal (eSim)

| # | Test | Predicted | Day | Evidence |
|---|---|---|---|---|
| M1 | **Single frame on analog bus** | 504 µs, correct levels | 61 | `day61_mixed.png` |
| M2 | Self-reception | node decodes its own frame | 61 | `day61_mixed.png` |
| M3 | 2-node arbitration | B loses at ID bit 8 | 65 | `day65_arb2.png` |
| M4 | **3-node arbitration** | **C at bit 9, B at bit 8, A wins** | 66 | `day66_arb3.png` |
| M5 | Multi-driver V_diff steps | 3.33 → 2.86 → 2.00 V | 66 | `day66_arb3.png` |
| M6 | Standard beats extended | D loses at SRR | 67 | `day67_ext.png` |
| M7 | Retransmission | all 3 frames delivered in priority order | 68 | `day68_retx.png` |
| M8 | Multi-node ACK | 3 receivers → V_diff 3.33 V in ACK slot | 69 | `day69_ack.png` |
| M9 | ACK error | no receiver → ack_error | 69 | `day69_ack.png` |
| M10 | Long bus arbitration | works at 220 m, fails beyond | 71 | `day71_long.png` |
| M11 | Multi-node osc mismatch | works within ±0.5% | 73 | `day73_osc.png` |
| M12 | Fault: no termination | characterised | 74 | `day74_faults.png` |
| M13 | Fault: CANH–CANL short | characterised | 74 | `day74_faults.png` |
| M14 | Fault: stuck dominant node | bus destroyed; node → bus-off | 74 | `day74_faults.png` |
| M15 | Noise thresholds | differential vs common-mode ratio | 75 | `day75_noise.png` |

**Total: 18 + 38 + 15 = 71 tests.**

## 7.3 The results that matter most

If everything else were lost, these six would still constitute a strong submission:

| Rank | Result | Why |
|---|---|---|
| 1 | **M4** — 3-node staged arbitration | The headline. Unique to CAN, inherently mixed-signal. |
| 2 | **A8** — wired-AND truth table | The electrical proof that makes M4 meaningful |
| 3 | **D7/D8/D9** — oscillator tolerance | Demonstrates *and quantifies* synchronisation; matches theory |
| 4 | **M1** — frame on a real analog bus | Proves the mixed-signal integration works at all |
| 5 | **M6** — standard beats extended | Shows protocol depth, not just bit comparison |
| 6 | **A11/A12** — propagation delay vs PROP_SEG | Turns a table entry into a measured constraint |

---

# PART 8 — DOCUMENTATION AND SUBMISSION

## 8.1 Report structure

| § | Section | Content | Words |
|---|---|---|---|
| 1 | Abstract | What was built and proven | 200 |
| 2 | Introduction | CAN, motivation, why circuit-level modelling suits it | 600 |
| 3 | Protocol background | Frame formats, arbitration, bit timing, errors (condense Part 1) | 1800 |
| 4 | Design methodology | Analog/digital partitioning and its justification (Part 2) | 800 |
| 5 | Physical layer design | **Full derivations**: R_on = 45 Ω, edge rates, comparator, transmission line (§3.8) | 1800 |
| 6 | Digital implementation | Module by module; bit timing and oscillator tolerance derivations (§3.2–3.3) | 2200 |
| 7 | Mixed-signal integration | NGHDL bridging, schematic, netlist structure | 800 |
| 8 | Results | Every waveform, each captioned with what it proves and its measured number | 2500 |
| 9 | Verification | Test matrix, methodology, coverage | 1000 |
| 10 | Discussion | Trade-offs: sample point choice, bit rate vs length, scaled bus-off count | 800 |
| 11 | Limitations & future work | Honest boundaries (§2.4 out-of-scope) | 500 |
| 12 | Conclusion | | 300 |
| — | References | ISO 11898-1/-2, Bosch CAN 2.0, eSim/NGHDL docs, ngspice manual | — |

**~13,300 words.** Substantial, but you will have written much of it during Days 21, 82–84 rather than at the end.

**Show your derivations.** An examiner can tell the difference between "R_on = 45 Ω" and a derivation that starts from the load current and arrives at 45 Ω. The second is worth several times the first.

## 8.2 Submission package

```
CAN_eSim_Submission/
├── README.md                      ← reproduce every result from here
├── report.pdf
├── schematics/                    ← Eeschema PDF + SVG exports
├── vhdl/                          ← all sources + testbenches + run.sh + regress.sh
├── python/                        ← reference models + golden vectors
├── spice/                         ← standalone PHY netlists
├── esim_project/                  ← complete eSim project directory
├── waveforms/                     ← every captured result, named by test ID
├── measurements.md                ← predicted vs measured, all 71 tests
└── LOG.md                         ← the development record
```

**`README.md` is worth disproportionate effort.** An examiner who reproduces your headline result in ten minutes rates the work far higher than one who cannot get it to run.

## 8.3 Email

**To:** contact-esim@fossee.in
**Subject:** `eSim Semester Long Internship - Autumn 2026 Submission Task 2`

Contents: name and contact; protocol chosen and why; one paragraph on what was modelled and verified; headline results (3-node arbitration verified, 71 tests passing, oscillator tolerance measured at 0.98%); attachments or link.

**Before sending:** re-read the circuit-proposal procedure linked from the task statement. Its current requirements are unknown to me and it may mandate a specific format or a separate proposal step.

---

# APPENDIX A — VHDL CRASH COURSE

## A.1 File structure

```vhdl
library ieee;
use ieee.std_logic_1164.all;    -- std_logic, std_logic_vector
use ieee.numeric_std.all;       -- unsigned, signed, conversions

entity my_block is              -- the black box: name and pins
  port (
    clk  : in  std_logic;
    rst  : in  std_logic;
    din  : in  std_logic;
    dout : out std_logic
  );
end entity;

architecture rtl of my_block is -- what is inside
  signal internal : std_logic := '0';
  constant WIDTH  : integer := 8;
begin
  -- concurrent statements and processes
end architecture;
```

**Always** `numeric_std`. **Never** `std_logic_arith` or `std_logic_unsigned` — non-standard, and they cause type ambiguity errors that are miserable to debug.

## A.2 Signals versus variables

| | `signal` | `variable` |
|---|---|---|
| Represents | a wire / register | a local temporary |
| Assignment | `<=` | `:=` |
| Updates | at process end | immediately |
| Scope | architecture-wide | inside one process |

The classic beginner trap:
```vhdl
process(clk)
begin
  if rising_edge(clk) then
    a <= b;     -- a gets the OLD value of b
    c <= a;     -- c gets the OLD value of a, NOT the value just assigned
  end if;
end process;
```
This is **correct and intended** — it describes two flip-flops in series. Use variables only when you genuinely need intra-process immediacy (as in the CRC's `nxt`).

## A.3 The clocked process

```vhdl
process(clk, rst)
begin
  if rst = '1' then
    count <= 0;                    -- asynchronous reset
  elsif rising_edge(clk) then
    if enable = '1' then
      count <= count + 1;          -- synchronous logic
    end if;
  end if;
end process;
```
95% of this project is this pattern.

## A.4 Concurrent assignment

Outside a process, statements are continuous and parallel — order is irrelevant:
```vhdl
bit_start <= '1' when tq_count = 0  else '0';
sample_pt <= '1' when tq_count = 11 else '0';
```

## A.5 State machines

```vhdl
architecture rtl of fsm is
  type state_t is (IDLE, SOF, ID_FIELD, DATA, CRC_FIELD, DONE);
  signal state : state_t := IDLE;
begin
  process(clk, rst)
  begin
    if rst = '1' then
      state <= IDLE;
    elsif rising_edge(clk) then
      case state is
        when IDLE      => if start = '1' then state <= SOF; end if;
        when SOF       => state <= ID_FIELD;
        when ID_FIELD  => if bit_index = 10 then state <= DATA; end if;
        when DATA      => if bit_index = 15 then state <= CRC_FIELD; end if;
        when CRC_FIELD => if bit_index = 14 then state <= DONE; end if;
        when DONE      => state <= IDLE;
        when others    => state <= IDLE;
      end case;
    end if;
  end process;
end architecture;
```
Always include `when others` — it prevents inferred latches and unreachable states.

## A.6 Vectors

```vhdl
signal id : std_logic_vector(10 downto 0) := "00010100101";  -- 0x0A5

id(10)            -- MSB
id(0)             -- LSB
id(10 downto 8)   -- 3-bit slice
id'length         -- 11
id'high           -- 10
```
Use `downto` consistently. Mixing `to` and `downto` produces silent bit-reversal bugs.

## A.7 Shift registers

```vhdl
if rising_edge(clk) then
  if load = '1' then
    sr <= data_in;
  elsif shift = '1' then
    sr <= sr(9 downto 0) & '0';     -- shift left, zero fill
  end if;
end if;

tx_bit <= sr(10);                    -- MSB-first transmission
```
`&` is concatenation.

## A.8 Type conversion

```vhdl
-- std_logic_vector → integer
n <= to_integer(unsigned(slv));

-- integer → std_logic_vector
slv <= std_logic_vector(to_unsigned(n, 8));   -- 8 = target width

-- std_logic_vector → unsigned (for arithmetic)
result <= std_logic_vector(unsigned(a) + unsigned(b));
```

## A.9 Self-checking testbench template

```vhdl
library ieee;
use ieee.std_logic_1164.all;

entity tb_my_block is end entity;    -- testbenches have NO ports

architecture sim of tb_my_block is
  signal clk, rst, din, dout : std_logic := '0';
  signal errors : integer := 0;
begin
  uut : entity work.my_block
    port map (clk => clk, rst => rst, din => din, dout => dout);

  clk <= not clk after 250 ns;               -- 2 MHz
  rst <= '1', '0' after 2 us;

  stim : process
  begin
    wait until rst = '0';
    wait for 1 us;

    din <= '1';
    wait for 8 us;
    assert dout = '1'
      report "FAIL: dout should be 1 after din=1"
      severity error;

    din <= '0';
    wait for 8 us;
    assert dout = '0'
      report "FAIL: dout should be 0 after din=0"
      severity error;

    report "===== ALL CHECKS PASSED =====" severity note;
    wait;
  end process;
end architecture;
```

Run with `--assert-level=error` so a failure produces a non-zero exit code.

## A.10 Hierarchy

**Direct entity instantiation — use this style throughout:**
```vhdl
u_timing : entity work.can_bit_timing
  port map (
    clk       => clk,
    rst       => rst,
    hard_sync => sof_detected,
    bit_start => bit_start,
    sample_pt => sample_pt
  );
```
Named association (`formal => actual`) always. Positional association is a bug waiting to happen when a port list changes.

---

# APPENDIX B — SPICE NETLISTS

## B.1 DC level verification (Day 13)

```spice
* ============================================================
* CAN PHY - DC level verification
* Expect: dominant  CANH=3.500 CANL=1.500 Vdiff=2.000 I=33.33mA
*         recessive CANH=2.500 CANL=2.500 Vdiff=0.000
* ============================================================

Vcc    vcc  0  DC 5.0
Vref   vref 0  DC 2.5

* --- Termination, both bus ends ---
Rterm1 canh canl 120
Rterm2 canh canl 120

* --- Recessive bias ---
Rbias1 canh vref 10k
Rbias2 canl vref 10k

* --- Bus capacitance ---
Cbush  canh 0 1n
Cbusl  canl 0 1n

* --- DC path to ground for every node (convergence) ---
Rleak1 canh 0 1meg
Rleak2 canl 0 1meg

* --- Node A driver: ctrl HIGH = dominant ---
Vctrl  ctrl 0 DC 5.0
Sh     vcc  canh ctrl 0 swmod
Sl     canl 0    ctrl 0 swmod
.model swmod SW(Vt=2.5 Vh=0.2 Ron=45 Roff=1e9)

.control
  op
  echo "--- DOMINANT ---"
  print v(canh) v(canl)
  let vdiff_dom = v(canh) - v(canl)
  print vdiff_dom
  print i(vcc)

  alter Vctrl 0
  op
  echo "--- RECESSIVE ---"
  print v(canh) v(canl)
  let vdiff_rec = v(canh) - v(canl)
  print vdiff_rec
.endc
.end
```

## B.2 Loopback with comparator and bridges (Day 14)

Add to B.1:

```spice
* --- Digital TX stimulus, 125 kHz ---
Vtx tx_dig 0 PULSE(0 5 10u 20n 20n 4u 8u)

* --- Digital -> analog (drives the switch control) ---
Adac [tx_dig] [ctrl] dacmod
.model dacmod dac_bridge(out_low=0 out_high=5 out_undef=2.5
+                        t_rise=20n t_fall=20n)

* --- Differential receiver: smooth comparator ---
* dominant (Vdiff high) -> LOW output -> logic 0
Bcomp rx_ana 0 V = 2.5*(1 - tanh(10*(V(canh)-V(canl)-0.7)))

* --- Analog -> digital ---
Aadc [rx_ana] [rx_dig] adcmod
.model adcmod adc_bridge(in_low=1.5 in_high=3.5)

.tran 100n 200u

.control
  run
  plot v(tx_dig) v(canh) v(canl)
  let vdiff = v(canh)-v(canl)
  plot vdiff v(rx_ana)
  meas tran t_rise TRIG v(canh) VAL=2.6 RISE=1 TARG v(canh) VAL=3.4 RISE=1
  meas tran t_loop TRIG v(tx_dig) VAL=2.5 FALL=1 TARG v(rx_ana) VAL=2.5 FALL=1
.endc
```

Remove `Vctrl` from B.1 when adding the DAC — the bridge now drives `ctrl`.

## B.3 Three-driver wired-AND (Day 16)

```spice
* Node A driver
Sha vcc  canh ctrl_a 0 swmod
Sla canl 0    ctrl_a 0 swmod
* Node B driver
Shb vcc  canh ctrl_b 0 swmod
Slb canl 0    ctrl_b 0 swmod
* Node C driver
Shc vcc  canh ctrl_c 0 swmod
Slc canl 0    ctrl_c 0 swmod

* Three independent stimuli, different periods -> all 8 combinations
Vtxa txa 0 PULSE(0 5 0 20n 20n 20u  40u)
Vtxb txb 0 PULSE(0 5 0 20n 20n 40u  80u)
Vtxc txc 0 PULSE(0 5 0 20n 20n 80u 160u)

Adac3 [txa txb txc] [ctrl_a ctrl_b ctrl_c] dacmod

.tran 100n 200u

.control
  run
  plot v(txa) v(txb) v(txc)
  let vdiff = v(canh)-v(canl)
  plot vdiff
.endc
```

**Expected multi-driver voltages** (§3.8.3) — measure and confirm:
| Drivers dominant | V_diff |
|---|---|
| 0 | 0.000 V |
| 1 | 2.000 V |
| 2 | 2.857 V |
| 3 | 3.333 V |

## B.4 Transmission line, 220 m (Day 17)

```spice
* Two bus segments joined by a 220 m transmission line
* Z0 = 120 ohm, TD = 1.1 us

Ttl canh_a canl_a canh_b canl_b Z0=120 TD=1.1u

* Termination at each far end
Rterm_a canh_a canl_a 120
Rterm_b canh_b canl_b 120

* Bias at one end only
Rbias1 canh_a vref 10k
Rbias2 canl_a vref 10k

* Node A driver on segment A, Node B driver on segment B
Sha vcc    canh_a ctrl_a 0 swmod
Sla canl_a 0      ctrl_a 0 swmod
Shb vcc    canh_b ctrl_b 0 swmod
Slb canl_b 0      ctrl_b 0 swmod

.tran 20n 50u

.control
  run
  let vda = v(canh_a)-v(canl_a)
  let vdb = v(canh_b)-v(canl_b)
  plot vda vdb
  meas tran t_prop TRIG vda VAL=1.0 RISE=1 TARG vdb VAL=1.0 RISE=1
.endc
```
Expect `t_prop ≈ 1.100 µs`.

## B.5 Reflection study (Day 18)

Take B.4 and vary `Rterm_b`:

| Run | Rterm_b | Predicted Γ |
|---|---|---|
| 1 | 120 | 0.000 |
| 2 | 1e9 (open) | +1.000 |
| 3 | 1k | +0.786 |
| 4 | 60 | −0.333 |

```spice
.control
  foreach rt 120 1e9 1k 60
    alter Rterm_b $rt
    run
    let vdb = v(canh_b)-v(canl_b)
    plot vdb
  end
.endc
```

## B.6 Common-mode injection (Day 19)

```spice
* Inject common-mode disturbance by moving the whole bus reference
Vcm cm_node 0 SIN(0 1.0 1MEG)
Rcm1 canh cm_node 1meg
Rcm2 canl cm_node 1meg

* Alternatively inject equally onto both lines through small caps
Ccm1 canh cm_node 100p
Ccm2 canl cm_node 100p
```
Measure the resulting differential disturbance and compute CMRR.

---

# APPENDIX C — VHDL MODULE SPECIFICATIONS

## C.1 `can_bit_timing`

**Constants, not generics** (§4.6).

```vhdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity can_bit_timing is
  port (
    clk         : in  std_logic;                     -- 2 MHz tq clock
    rst         : in  std_logic;
    hard_sync   : in  std_logic;                     -- SOF detected
    resync_edge : in  std_logic;                     -- rec->dom edge in frame
    bit_start   : out std_logic;
    sample_pt   : out std_logic;
    tq_index    : out std_logic_vector(4 downto 0)
  );
end entity;

architecture rtl of can_bit_timing is
  constant TQ_PER_BIT : integer := 16;
  constant SYNC_SEG   : integer := 1;
  constant PROP_SEG   : integer := 5;
  constant PHASE_SEG1 : integer := 6;
  constant PHASE_SEG2 : integer := 4;
  constant SAMPLE_TQ  : integer := SYNC_SEG + PROP_SEG + PHASE_SEG1;  -- 12
  constant SJW        : integer := 4;

  signal cnt      : integer range 0 to 31 := 0;
  signal bit_len  : integer range 0 to 31 := TQ_PER_BIT;
begin
  process(clk, rst)
    variable e : integer;
  begin
    if rst = '1' then
      cnt     <= 0;
      bit_len <= TQ_PER_BIT;
    elsif rising_edge(clk) then
      if hard_sync = '1' then
        cnt     <= 0;
        bit_len <= TQ_PER_BIT;

      elsif resync_edge = '1' then
        e := cnt - SYNC_SEG;                       -- phase error in tq
        if e > 0 and cnt < SAMPLE_TQ then
          -- edge LATE: lengthen PHASE_SEG1
          if e > SJW then bit_len <= TQ_PER_BIT + SJW;
          else            bit_len <= TQ_PER_BIT + e;
          end if;
        elsif cnt >= SAMPLE_TQ then
          -- edge EARLY: shorten PHASE_SEG2
          e := TQ_PER_BIT - cnt;
          if e > SJW then bit_len <= TQ_PER_BIT - SJW;
          else            bit_len <= TQ_PER_BIT - e;
          end if;
        end if;
        cnt <= cnt + 1;

      elsif cnt >= bit_len - 1 then
        cnt     <= 0;
        bit_len <= TQ_PER_BIT;                     -- restore nominal
      else
        cnt <= cnt + 1;
      end if;
    end if;
  end process;

  bit_start <= '1' when cnt = 0            else '0';
  sample_pt <= '1' when cnt = SAMPLE_TQ-1  else '0';
  tq_index  <= std_logic_vector(to_unsigned(cnt, 5));
end architecture;
```

**Verify the resync sign convention against §1.6.3 on Day 25.** Getting it backwards (bug P14) makes drift worse and the symptom is misleading.

## C.2 `can_crc15`

```vhdl
entity can_crc15 is
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    enable   : in  std_logic;   -- one pulse per covered bit; EXCLUDES stuff bits
    data_bit : in  std_logic;
    crc_out  : out std_logic_vector(14 downto 0)
  );
end entity;
```

```vhdl
constant CRC_POLY : std_logic_vector(14 downto 0) := "100010110011001"; -- 0x4599

process(clk, rst)
  variable nxt : std_logic;
  variable tmp : std_logic_vector(14 downto 0);
begin
  if rst = '1' then
    crc_reg <= (others => '0');
  elsif rising_edge(clk) then
    if enable = '1' then
      nxt := data_bit xor crc_reg(14);
      tmp := crc_reg(13 downto 0) & '0';
      if nxt = '1' then
        crc_reg <= tmp xor CRC_POLY;
      else
        crc_reg <= tmp;
      end if;
    end if;
  end if;
end process;

crc_out <= crc_reg;
```

**Verify the constant:** `"100010110011001"` (15 bits). Padded to 16: `0100 0101 1001 1001` = `0x4599` ✓. Confirm against the Python reference on Day 29 rather than trusting this.

## C.3 Module interface summary

| Module | Key inputs | Key outputs |
|---|---|---|
| `can_bit_timing` | clk, rst, hard_sync, resync_edge | bit_start, sample_pt, tq_index |
| `can_crc15` | clk, rst, enable, data_bit | crc_out(14:0) |
| `can_stuffer` | clk, bit_start, tx_bit, stuff_en | tx_stuffed, stuff_active |
| `can_destuffer` | clk, sample_pt, rx_bit, destuff_en | rx_bit_out, rx_valid, stuff_error |
| `can_tx_fsm` | clk, rst, tx_req, node_sel, bit_start, sample_pt, rx_bit, stuff_active | tx_bit, stuff_en, arb_lost, tx_active, tx_done, bit_error |
| `can_rx_fsm` | clk, rst, sample_pt, rx_bit, rx_valid | rx_id, rx_ide, rx_rtr, rx_dlc, rx_data, rx_done, crc_error, form_error, ack_drive |
| `can_filter` | rx_id, rx_ide, node_sel | accept |
| `can_error_mgmt` | clk, rst, all error flags, tx_active | err_flag_drive, tec, rec, err_passive, bus_off |
| `can_node` | clk, rst, node_sel(1:0), tx_req, can_rx | can_tx, tx_done, arb_lost, rx_valid, 5 error flags, err_passive, bus_off |

## C.4 Node constant table

```vhdl
type id_array_t   is array (0 to 3) of std_logic_vector(10 downto 0);
type idb_array_t  is array (0 to 3) of std_logic_vector(17 downto 0);
type data_array_t is array (0 to 3) of std_logic_vector(15 downto 0);

constant NODE_ID_A   : id_array_t   := ("00010100101",   -- A: 0x0A5
                                        "00100100011",   -- B: 0x123
                                        "01010101010",   -- C: 0x2AA
                                        "00010100101");  -- D: base 0x0A5

constant NODE_ID_B   : idb_array_t  := ((others=>'0'), (others=>'0'), (others=>'0'),
                                        "111010101111001101");  -- D ext: 0x3ABCD

constant NODE_IDE    : std_logic_vector(3 downto 0) := "1000";  -- D is extended

constant NODE_DATA   : data_array_t := (x"A53C",   -- A
                                        x"1234",   -- B
                                        x"55AA",   -- C
                                        x"DEAD");  -- D
```

Verify `0x3ABCD` as 18 bits: `11 1010 1011 1100 1101` = `111010101111001101` ✓

---

# APPENDIX D — COMMAND CHEAT SHEET

```bash
# ---------- GHDL ----------
ghdl -a mod.vhdl tb_mod.vhdl                    # analyse (dependency order!)
ghdl -e tb_mod                                   # elaborate
ghdl -r tb_mod --stop-time=1ms --vcd=out.vcd --assert-level=error
rm -f work-obj93.cf *.o                          # clean a broken library

./run.sh can_crc15 200us                         # your wrapper
./regress.sh                                     # full regression

# ---------- GTKWave ----------
gtkwave out.vcd &

# ---------- ngspice ----------
ngspice -b netlist.cir                           # batch
ngspice netlist.cir                              # interactive
#   run / plot v(canh) / print v(canh) / meas tran ... / alter Vx 0 / quit

# ---------- eSim ----------
esim &                                           # ALWAYS background

# ---------- disk ----------
df -h /
du -sh ~/nghdl-simulator/* ~/Documents/CAN_project/*

# ---------- VM resize (guest side, after growing the VDI on the host) ----------
sudo apt install cloud-guest-utils
lsblk
sudo growpart /dev/sda 3
sudo resize2fs /dev/sda3
df -h /

# ---------- git (every single day) ----------
git add -A && git commit -m "Day N: ..." && git push

# ---------- independent CRC reference ----------
python3 -c "
def crc15(bits):
    c=0
    for b in bits:
        n=b^((c>>14)&1); c=(c<<1)&0x7FFF
        if n: c^=0x4599
    return hex(c)
print(crc15([0,0,0,1,0,1,0,0,1,0,1]))
"

# ---------- markdown -> PDF ----------
pandoc doc.md -o doc.html --standalone --toc      # then print to PDF from a browser
pandoc doc.md -o doc.pdf --toc -V geometry:margin=2cm   # needs texlive
```

**GTKWave essentials**

| Action | How |
|---|---|
| Add signals | Click entity in SST → select → **Append** |
| Fit to window | **Time → Zoom → Zoom Full** |
| Measure a delta | Click first point, Ctrl+click second — delta shows in the top bar |
| Reload after re-run | Circular-arrow toolbar button |
| Change radix | Right-click signal → Data Format → Hex |
| Save signal setup | **File → Write Save File** — then `gtkwave out.vcd out.gtkw` restores it |

That last one saves enormous time — set up your signal list once per module and reload it every run.

---

# APPENDIX E — REFERENCE TABLES

## E.1 Bit timing, all rates (16 tq; SYNC 1, PROP 5, PS1 6, PS2 4)

| Bit rate | T_bit | T_tq | f_clk | Sample pt | SJW | Max bus |
|---|---|---|---|---|---|---|
| 125 kbit/s | 8.000 µs | 500 ns | 2 MHz | 6.000 µs (75%) | 2.000 µs | 220 m |
| 250 kbit/s | 4.000 µs | 250 ns | 4 MHz | 3.000 µs (75%) | 1.000 µs | 95 m |
| 500 kbit/s | 2.000 µs | 125 ns | 8 MHz | 1.500 µs (75%) | 500 ns | 32 m |
| 1 Mbit/s | 1.000 µs | 62.5 ns | 16 MHz | 750 ns (75%) | 250 ns | 1.3 m |

## E.2 Frame lengths at 125 kbit/s

| Frame | Bits (nominal) | +IFS | Duration | Max stuff | Worst case |
|---|---|---|---|---|---|
| Standard DLC=0 | 44 | 47 | 376 µs | 10 | 456 µs |
| Standard DLC=2 | 60 | 63 | **504 µs** | 12 | 600 µs |
| Standard DLC=8 | 108 | 111 | 888 µs | 24 | 1080 µs |
| Extended DLC=2 | 80 | 83 | 664 µs | 17 | 800 µs |
| Extended DLC=8 | 128 | 131 | 1048 µs | 29 | 1280 µs |
| Remote std DLC=2 | 44 | 47 | 376 µs | 10 | 456 µs |
| Error frame | 14–20 | — | 112–160 µs | — | — |
| Overload frame | 14–20 | — | 112–160 µs | — | — |

## E.3 Multi-driver bus voltages

| Dominant drivers | R_on_eff | R_total | I | V_CANH | V_CANL | V_diff |
|---|---|---|---|---|---|---|
| 0 (recessive) | ∞ | — | 0 | 2.500 V | 2.500 V | 0.000 V |
| 1 | 45.0 Ω | 150.0 Ω | 33.33 mA | 3.500 V | 1.500 V | 2.000 V |
| 2 | 22.5 Ω | 105.0 Ω | 47.62 mA | 3.929 V | 1.071 V | 2.857 V |
| 3 | 15.0 Ω | 90.0 Ω | 55.56 mA | 4.167 V | 0.833 V | 3.333 V |
| 4 | 11.25 Ω | 82.5 Ω | 60.61 mA | 4.318 V | 0.682 V | 3.636 V |

## E.4 Node identifier map

| Node | Format | ID | Binary (base, bit10→0) | Payload | Filter ID / mask |
|---|---|---|---|---|---|
| A | Standard | 0x0A5 | `000 1010 0101` | 0xA53C | 0x000 / 0x000 |
| B | Standard | 0x123 | `001 0010 0011` | 0x1234 | 0x0A5 / 0x7FF |
| C | Standard | 0x2AA | `010 1010 1010` | 0x55AA | 0x0A0 / 0x7F0 |
| D | Extended | 0x297ABCD | base `000 1010 0101`, ext 0x3ABCD | 0xDEAD | 0x123 / 0x7FF |

## E.5 Arbitration outcome predictions

| Scenario | Contenders | Predicted |
|---|---|---|
| 1 | A, B, C | C loses at ID bit 9; B loses at ID bit 8; A wins |
| 2 | A, B | B loses at ID bit 8; A wins |
| 3 | B, C | C loses at ID bit 9; B wins |
| 4 | A, D | D loses at SRR bit (standard beats extended, same base ID) |
| 5 | A, B, C, D | D loses at SRR; C at bit 9; B at bit 8; A wins |

## E.6 CRC-15 golden vectors (generate on Day 29, record here)

| # | Input (35 bits) | Expected CRC | Source |
|---|---|---|---|
| 1 | all zeros | *(compute)* | Python reference |
| 2 | all ones | *(compute)* | Python reference |
| 3 | Node A frame prefix | *(compute)* | Python reference |
| 4 | random pattern 1 | *(compute)* | Python reference |
| 5 | random pattern 2 | *(compute)* | Python reference |

## E.7 Error counter thresholds

| Threshold | Value | Effect |
|---|---|---|
| Error-active → error-passive | TEC > 127 or REC > 127 | recessive error flags; +8-bit suspend |
| Error-passive → bus-off | TEC > 255 | drivers disabled |
| Bus-off → error-active (real) | 128 × 11 recessive bits | TEC, REC reset to 0 |
| Bus-off → error-active (sim) | **8 × 11 recessive bits** | documented scaling |

---

# APPENDIX F — GLOSSARY

| Term | Meaning |
|---|---|
| **Dominant** | Logic 0. Actively driven. Overrides recessive. CANH 3.5 V / CANL 1.5 V. |
| **Recessive** | Logic 1. Passive; held by bias resistors. Both lines 2.5 V. |
| **Wired-AND** | Bus behaviour where any dominant driver forces the entire bus dominant. |
| **Arbitration** | Bitwise, non-destructive priority resolution during the identifier field. |
| **tq** | Time quantum — the indivisible unit of CAN bit timing. 500 ns here. |
| **NBT** | Nominal Bit Time — 16 tq = 8 µs here. |
| **SYNC_SEG** | 1 tq segment in which bit edges are expected. |
| **PROP_SEG** | Segment covering round-trip physical propagation delay. Limits bus length. |
| **PHASE_SEG1/2** | Segments adjusted during resynchronisation. |
| **Sample point** | The single instant per bit at which the bus is read. 75% here. |
| **SJW** | Synchronisation Jump Width — maximum resynchronisation adjustment. 4 tq here. |
| **Hard synchronisation** | Unconditional bit-timer restart on SOF. |
| **Resynchronisation** | Bounded timing adjustment on edges within a frame. |
| **Bit stuffing** | Inserting an opposite-polarity bit after 5 identical bits, guaranteeing edges. |
| **SOF / EOF / IFS** | Start of Frame / End of Frame / Interframe Space. |
| **DLC** | Data Length Code — payload byte count. |
| **RTR** | Remote Transmission Request. 0 = data frame, 1 = remote frame. |
| **IDE** | Identifier Extension. 0 = standard 11-bit, 1 = extended 29-bit. |
| **SRR** | Substitute Remote Request — always recessive; makes standard frames beat extended. |
| **ACK slot** | Bit in which receivers acknowledge by driving dominant. |
| **Error frame** | 6 dominant (active) or recessive (passive) bits + 8 recessive delimiter. |
| **Overload frame** | Same structure as an error frame; requests a delay. |
| **TEC / REC** | Transmit / Receive Error Counter. |
| **Error-active** | Normal state. Transmits dominant error flags. |
| **Error-passive** | TEC or REC > 127. Transmits recessive error flags. |
| **Bus-off** | TEC > 255. Node disconnected from the bus. |
| **XSPICE** | ngspice's event-driven mixed-signal extension. |
| **Code model (.cm)** | Compiled shared library implementing an XSPICE device. |
| **NGHDL** | eSim component wrapping VHDL as an XSPICE code model. |
| **adc_bridge / dac_bridge** | XSPICE devices converting between analog and digital event domains. |
| **GHDL** | Open-source VHDL compiler and simulator. |
| **VCD / GHW** | Waveform file formats readable by GTKWave. |
| **Γ (Gamma)** | Reflection coefficient, `(R_L − Z₀)/(R_L + Z₀)`. |
| **CMRR** | Common-Mode Rejection Ratio, in dB. |

---

# CLOSING NOTES

## The five results that define this project

1. **A8** — measured wired-AND truth table from analog waveforms
2. **M4** — three-node staged arbitration, dropouts at the predicted bits
3. **D7/D8/D9** — oscillator tolerance measured and matching the derived 0.98%
4. **A11/A12** — propagation delay measured and shown to match PROP_SEG exactly
5. **M6** — standard frame beating extended frame at the SRR bit

Each is a *measured number compared against a number you derived first*. That is what distinguishes engineering from assembly.

## The three ways this project still fails

1. **Debugging VHDL inside eSim.** Rule 1. It is slow enough to consume the entire schedule.
2. **Skipping Days 3–4.** The NGHDL capability probes cost one afternoon and can save three weeks.
3. **Losing the work.** Rule 4. One VM, one disk, already filled once.

## Honest confidence assessment

With 86 days at ~3 h/day and no hard deadline, **90%** confidence the full in-scope list is delivered. The residual risk is concentrated in:

- **Phase 6 (error management, 11 days)** — the largest single block of new VHDL, and the least visually verifiable. If anything slips badly, it will slip here.
- **Phase 7 (mixed-signal integration)** — historically where eSim projects stall. Days 61–63 allow for that.
- **VHDL learning rate** — Phase 1 assumes seven days is enough to go from beginner to writing FSMs unaided. For some people it is ten. Take the extra days; every subsequent phase depends on it.

If the schedule ever has to compress, cut in this order and stop when you have enough: overload frames → remote frames → acceptance filtering → extended frames → bus-off recovery → TEC/REC. **Never cut arbitration, the wired-AND demonstration, or resynchronisation** — those three are the project.

---

*Document version 2.0. Update `LOG.md` daily. If a frozen parameter in Part 3 must genuinely change, re-derive everything downstream of it and record the reason here.*


