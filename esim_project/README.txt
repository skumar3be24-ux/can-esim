CAN Bus - Mixed-Signal Modelling and Verification in eSim
==========================================================

Sourabh Kumar
Thapar Institute of Engineering and Technology
FOSSEE eSim Circuit Simulation Project


WHAT THIS IS
------------
A CAN (Controller Area Network) bus modelled in eSim as a mixed-signal
system. The physical layer is an Ngspice subcircuit; the protocol
controller is VHDL compiled by GHDL and run as an Ngspice code model
through NGHDL. Two controller instances share one differential pair
and contend for it.


FILES
-----
CAN_Bus_MixedSignal.kicad_sch   the schematic (KiCad 6 format)
CAN_Bus_MixedSignal.cir         netlist exported from eeschema
                                 (Spice format, which is what eSim reads)
CAN_Bus_MixedSignal.cir.out     the Ngspice netlist produced by eSim's
                                 KiCad-to-Ngspice conversion. This is the
                                 file that is simulated.
CAN_Bus_MixedSignal.proj        eSim project file
CAN_Bus_MixedSignal_Previous_Values.xml   saved conversion parameters
analysis                        analysis settings

can_phy.sub                     the analog transceiver and bus, as an
                                 Ngspice subcircuit
can_phy/can_phy.sub             the same file in the directory layout
                                 eSim's Subcircuits tab expects

vhdl/                           the ten VHDL modules that make up the
                                 controller, in dependency order:
                                   crc15.vhdl
                                   bit_timing.vhdl
                                   bit_stuff.vhdl
                                   frame_gen.vhdl
                                   frame_rx.vhdl
                                   can_tx_path.vhdl
                                   error_gen.vhdl
                                   error_mgmt.vhdl
                                   can_node.vhdl
                                   can_node_top.vhdl   <- top level, the
                                                          NGHDL model

can_esim_ascii.raw.gz           simulation output, ASCII raw format
plot_data_v.txt.gz              node voltages over time


REPRODUCING THE SIMULATION
--------------------------
1. Build the NGHDL model. Open eSim, select this project, and click the
   NGHDL icon in the left toolbar (it must be launched from inside eSim,
   not standalone, or the KiCad symbol is not generated).
   Browse to vhdl/can_node_top.vhdl as the main file, then use Add Files
   to add the other nine. Upload.

   NOTE: NGHDL as shipped cannot build a model split across several
   files - the generated start_server.sh analyses only the uploaded
   file. The fix is to replace the fixed analysis list with GHDL make
   mode:
       ghdl -i *.vhdl &&
       ghdl -m -Wl,ghdlserver.o <entity>_tb &&
   This also removes a locale-dependent file-ordering bug in the same
   script.

2. Open the schematic and export the netlist:
   File - Export - Netlist - Spice tab - Export Netlist
   Save as CAN_Bus_MixedSignal.cir.
   The KiCad tab produces an S-expression file that eSim cannot parse,
   with no error message.

3. In eSim click KiCad to Ngspice. Set the transient analysis, the
   source values, and point the Subcircuits tab at the can_phy folder.
   Convert.

4. Simulate:
       ngspice -b CAN_Bus_MixedSignal.cir.out


DESIGN PARAMETERS
-----------------
bit rate                125 kbit/s, 8.000 us bit time
time quanta per bit     16, so tq = 500 ns and the controller runs at
                        2.000 MHz
segments                SYNC 1, PROP 5, PHASE1 6, PHASE2 4 tq
sample point            12 tq = 75 per cent
driver on-resistance    45 ohm
termination             120 ohm at each end
bus capacitance         500 pF per line
receiver thresholds     0.9 V dominant, 0.5 V recessive
identifiers             node A 0x0A5, node B 0x123

The propagation segment is measured, not assumed: over a 220 m bus the
one-way delay is 1.1136 us and the transceiver adds 21.6 ns, so the
round trip is 2.27 us against the 2.500 us that five time quanta allow.


WHAT THE SIMULATION SHOWS
-------------------------
Reset releases at 2 us and both nodes are asked to transmit at 10 us.
They contend, and node A wins because 0x0A5 is lower than 0x123.

Arbitration is visible in the analog waveform. Between about 26 us and
55 us the bus differential reaches 2.85 V rather than 2.0 V, because
both nodes are driving dominant simultaneously and two 45 ohm drivers
in parallel present 22.5 ohm. After 55 us it settles to 2.0 V: one node
has withdrawn and a single driver remains.

Bus levels follow ISO 11898-2 - CANH 2.5 to 3.5 V, CANL 2.5 to 1.5 V,
differential 0 V recessive and 2 V dominant.


KNOWN LIMITATIONS
-----------------
Standard 11-bit identifiers only. No extended identifiers, no overload
frames. A node that loses arbitration abandons the frame rather than
retrying. This netlist drives both nodes from one clock, though
resynchronisation itself is verified against independent oscillators
in simulation: node B was swept from 0 to 6 per cent skew and
reception stayed correct to 3 per cent, three times the derived 0.98
per cent bound, failing safely above that by flagging an error rather
than accepting corrupt data. The comparator has no common-mode
input range, so the
model is optimistic outside the range where real transceivers saturate.


REFERENCES
----------
ISO 11898-1:2015  Road vehicles - Controller area network (CAN)
                  Part 1: Data link layer and physical signalling
ISO 11898-2:2016  Part 2: High-speed medium access unit
Bosch CAN Specification Version 2.0, Robert Bosch GmbH, 1991

================================================================
NOTE ON SUBMISSION GUIDELINE 3 (required file list)
================================================================

The guideline lists these files:

    analysis, .bak, .cir, .cir.out, .pro, .sch, .sub,
    cache.bak, .lib.xml

This project was built with eSim 2.5, which uses KiCad 6. Some
names in that list date from the KiCad 5 era and are not produced
by the current toolchain. The mapping is:

    analysis     present
    .cir         present  CAN_Bus_MixedSignal.cir
    .cir.out     present  CAN_Bus_MixedSignal.cir.out
    .sub         present  can_phy.sub  (and can_phy/can_phy.sub)
    .pro         present  CAN_Bus_MixedSignal.proj
                          eSim 2.5 names the project file .proj
    .sch         present  CAN_Bus_MixedSignal.kicad_sch
                          KiCad 6 schematic format

    .bak         not generated by KiCad 6
    cache.bak    not generated. KiCad 5 kept symbols in a separate
                 cache library; KiCad 6 embeds them inside the
                 schematic file under the lib_symbols section, so
                 the schematic is self-contained and no cache is
                 written
    .lib.xml     not generated by this flow

Nothing has been omitted. Every file the toolchain produces is
included.

Per the NOTE in guideline 3, this is a mixed-signal project using
NGHDL, so the VHDL sources are included in vhdl/ (10 files).

Also included, beyond the required list:

    ngspice_bus.svg     ngspice plot, CANH and CANL
    ngspice_diff.svg    ngspice plot, differential voltage
    can_esim_ascii.raw.gz, plot_data_v.txt.gz
                        compressed simulation output
    CAN_Bus_MixedSignal.pdf
                        printed schematic
