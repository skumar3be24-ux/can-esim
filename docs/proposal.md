# Project Overview

---

## Title

CAN (Controller Area Network) Bus — Mixed-Signal Modelling and Verification of a
Multi-Node Communication Protocol in eSim

---

## Short description / abstract (for the proposal form)

This project models a complete CAN (Controller Area Network) communication bus in
eSim as a mixed-signal system, combining an analog physical layer simulated in
Ngspice with digital protocol controllers written in VHDL and integrated through
eSim's NGHDL interface.

CAN is the standard automotive and industrial fieldbus defined by ISO 11898. It
is chosen here because, unlike simpler protocols such as UART or SPI, it exercises
the full range of eSim's mixed-signal capability: it requires a differential
analog physical layer with defined electrical thresholds, a bit-synchronised
digital controller with no shared clock line, non-destructive bus arbitration
that depends on a node reading back the analog level it is driving, and a
fault-confinement mechanism that progressively removes a faulty node from the bus.

The analog physical layer models the differential pair with 45 Ω driver
on-resistance, dual 120 Ω termination, bus capacitance, a bias network and a
differential receiver, together with a transmission-line model of a 220 m twisted
pair. The digital controller implements bit timing with resynchronisation, bit
stuffing, CRC-15, frame assembly and decoding, arbitration, acknowledgement,
error signalling and fault confinement.

Four controller instances share a single differential pair. When several nodes
transmit simultaneously, arbitration is resolved bit by bit on the physical bus:
a node transmitting a recessive level that reads back dominant has lost, and
withdraws without corrupting the winner's frame.

The system operates at 125 kbit/s with a 8.000 µs bit time divided into 16 time
quanta and a sample point at 75%. These parameters are not assumed — the
propagation segment is derived from a measured round-trip delay over the modelled
220 m bus.

---

## Reference source

ISO 11898-1:2015, *Road vehicles — Controller area network (CAN) — Part 1: Data
link layer and physical signalling*, and ISO 11898-2:2016, *Part 2: High-speed
medium access unit*.

Bosch CAN Specification Version 2.0 (1991) for the frame format and
fault-confinement rules.

---

## Why this is not a trivial simulation

A minimal one- or two-component simulation would not exercise the interesting
part of the protocol. This design comprises:

- Analog: differential driver stages, dual termination, bias network, bus
  capacitance, differential receiver, transmission-line model
- Digital: 10 VHDL modules — bit timing, bit stuffing, CRC-15, frame generator,
  frame decoder, transmit datapath, error frame generator, fault-confinement
  counters, node wrapper, top-level model
- Mixed-signal: four NGHDL controller instances on one analog bus, with ADC and
  DAC bridges at every boundary

---

## What will be demonstrated

1. **Data transfer** — a transmitting node's identifier, DLC and payload
   recovered correctly by receiving nodes across the analog bus.
2. **Timing and synchronisation** — 16 time quanta per bit, sample point at 75%,
   hard synchronisation and resynchronisation bounded by the synchronisation
   jump width.
3. **Arbitration** — four nodes transmitting simultaneously; the lowest
   identifier wins and the losers withdraw one bit apart in the order their
   identifiers predict, without corrupting the winner's frame.
4. **Error handling** — CRC, form, stuff and bit errors detected; error frames
   transmitted; transmit and receive error counters; error-active,
   error-passive and bus-off states.
5. **Fault confinement** — a physical bus fault drives the affected node to
   bus-off while healthy nodes continue unaffected.

---

## Deliverables

- eSim project with schematic and simulation
- VHDL source for the CAN controller, integrated via NGHDL
- Ngspice netlists for the analog physical layer
- Abstract documenting theory, method and results
- Verification matrix listing every test and its measured result

---

## Note on toolchain defects found along the way

During development, six defects were found in eSim 2.5 and NGHDL, each diagnosed
and patched. The most significant is that NGHDL's generated build script analyses
only the single uploaded VHDL file, so no model split across multiple files can be
built. A CAN controller is naturally ten files. The fix uses GHDL make mode
(`ghdl -i` followed by `ghdl -m`) so dependencies are resolved automatically, and
it also removes a locale-dependent file-ordering bug in the same script.

These patches are documented and can be contributed back to the eSim project if
useful.
