# eSim Schematic Build Sheet — CAN_Bus_MixedSignal

Two nodes on one differential pair. Enough to demonstrate data transfer,
arbitration, acknowledgement and error handling. Scale to four later if time
allows — the netlist versions already work at four.

Open: eSim → select `CAN_Bus_MixedSignal` → click the **eeschema** icon.

---

## Component list

Place these from **Place → Add Symbol** (or press `A`).

| Ref | Symbol | Library | Purpose |
|---|---|---|---|
| U1 | `can_node_top` | eSim_Nghdl | CAN node A |
| U2 | `can_node_top` | eSim_Nghdl | CAN node B |
| X1 | `can_phy` | eSim_Subckt | analog transceiver + bus |
| V1 | `pulse` | eSim_Sources | 2 MHz clock |
| V2 | `pulse` | eSim_Sources | reset |
| V3 | `pulse` | eSim_Sources | transmit request |
| V4 | `dc` | eSim_Sources | logic 0 for id_sel |
| V5 | `dc` | eSim_Sources | logic 1 for id_sel |
| V6 | `dc` | eSim_Sources | 5 V supply for the PHY |
| U3 | `adc_bridge_4` | eSim_Hybrid | clk, reset, req, rx → digital |
| U4 | `adc_bridge_2` | eSim_Hybrid | id_sel levels → digital |
| U5 | `dac_bridge_2` | eSim_Hybrid | both can_tx → analog |
| — | `eSim_GND` | eSim_Power | ground (place several) |
| — | `plot_v1` | eSim_Plot | on nodes you want to see |

---

## Pin map for `can_node_top`

The symbol has generic pin names. They map positionally:

| Pin | Signal | | Pin | Signal |
|---|---|---|---|---|
| in1 | clk | | out1 | can_tx |
| in2 | reset_n | | out2 | tx_busy |
| in3 | can_rx | | out3 | tx_done |
| in4 | tx_req | | out4 | arb_lost |
| in5 | id_sel(1) MSB | | out5 | rx_valid |
| in6 | id_sel(0) LSB | | out6 | err_frame |
| | | | out7 | bus_off |

**Node identities** (`id_sel`):
- U1 = `00` → both in5 and in6 to logic 0 → identifier 0x0A5 (wins)
- U2 = `01` → in5 to logic 0, in6 to logic 1 → identifier 0x123 (loses)

---

## Connections

Use **net labels** (press `L`) rather than long wires where convenient — it
keeps the sheet readable and eSim's netlister handles them fine.

### Clock, reset, request — shared by both nodes

```
V1 pulse  --> U3.in1 ;  U3.out1 --> label CLK  --> U1.in1, U2.in1
V2 pulse  --> U3.in2 ;  U3.out2 --> label RST  --> U1.in2, U2.in2
V3 pulse  --> U3.in3 ;  U3.out3 --> label REQ  --> U1.in4, U2.in4
```

### Bus feedback — the received level, shared

```
X1.rxo    --> U3.in4 ;  U3.out4 --> label RX   --> U1.in3, U2.in3
```

### Node identities

```
V4 (0 V)  --> U4.in1 ;  U4.out1 --> label SEL0 --> U1.in5, U1.in6, U2.in5
V5 (5 V)  --> U4.in2 ;  U4.out2 --> label SEL1 --> U2.in6
```

### Transmit outputs to the bus

```
U1.out1 --> U5.in1 ;  U5.out1 --> X1.txa
U2.out1 --> U5.in2 ;  U5.out2 --> X1.txb
```

### PHY supply

```
V6 (5 V) --> X1.vcc
GND      --> X1.gnd
```

### Probes

Attach `plot_v1` to at least:
- `X1.rxo` — the recovered bus level
- The analog node between U5.out1 and X1.txa — node A transmitting

Leave U1/U2 outputs 2–7 unconnected. Unconnected outputs are fine; add a
**no-connect flag** (press `Q`) on each to keep ERC quiet.

---

## Source parameters

Set by double-clicking each source. eSim will also ask for these again in the
Ki→Ng **Source Details** tab — the values there are what actually count.

| Source | Type | Parameters |
|---|---|---|
| V1 clock | pulse | initial 0, pulsed 5, delay 0, rise 5n, fall 5n, width 245n, period 500n |
| V2 reset | pulse | initial 0, pulsed 5, delay 2u, rise 10n, fall 10n, width 1, period 2 |
| V3 request | pulse | initial 0, pulsed 5, delay 10u, rise 20n, fall 20n, width 0.5u, period 100u |
| V4 | dc | 0 |
| V5 | dc | 5 |
| V6 | dc | 5 |

The clock is 500 ns period = 2.000 MHz = one time quantum, giving the frozen
8.000 µs bit time at 16 tq.

---

## After drawing

1. **Annotate** — Tools → Annotate Schematic
2. **ERC** — Inspect → Electrical Rules Checker. Fix real errors; unconnected
   outputs with no-connect flags are fine.
3. **Save**
4. Back in eSim, click **KiCad to Ngspice**
5. In the converter:
   - **Analysis tab**: Transient, stop time 600u, step 100n
   - **Source Details tab**: enter the pulse/dc values from the table above
   - **Subcircuits tab**: it will ask for `can_phy` → browse to the folder
     containing `can_phy.sub`
   - **Device Model / NGHDL tab**: `can_node_top` should be found automatically
6. **Convert**, then **Simulate**

---

## Expected result

Node A (0x0A5) wins arbitration, node B (0x123) reports `arb_lost`, node A's
frame is acknowledged and node B receives it. On the bus you should see the
differential settle to about 2 V dominant and 0 V recessive, with a frame of
roughly 48 bit times at 8 µs each.

If the netlist converts but the simulation misbehaves, compare against
`spice/can_mixed.cir`, which is the same circuit as a hand-written netlist and
is known to work.
