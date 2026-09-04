CAN Bus - Mixed-Signal Modelling and Verification in eSim
==========================================================

Sourabh Kumar
Thapar Institute of Engineering and Technology


================================================================
HOW TO TEST THIS PROJECT   (please read first)
================================================================

This is a mixed-signal project. The analog side is an Ngspice
subcircuit and runs immediately. The digital side is VHDL compiled
into an Ngspice code model by NGHDL, and that model must be BUILT
ON THE TESTING MACHINE before the netlist will simulate.

The netlist contains:

    .model u3 can_node_top(...)
    .model u4 can_node_top(...)

can_node_top is an XSPICE code model created by NGHDL. It lives
inside the local Ngspice installation, not in this project folder,
so it cannot be shipped. Without building it, Ngspice reports an
unknown model and the simulation stops. Everything needed to build
it is included here.


ROUTE A - CHECK THE RESULTS WITHOUT REBUILDING  (about 2 minutes)
-----------------------------------------------------------------
The completed simulation and all its output are included, so the
results can be verified without installing anything.

    CAN_Bus_MixedSignal.cir.out   the exact netlist that was run
    can_esim_ascii.raw            full Ngspice output, ASCII raw
    plot_data_v.txt               every node voltage over time
    plot_data_i.txt               every branch current
    ngspice_bus.svg               Ngspice plot, CANH and CANL
    ngspice_diff.svg              Ngspice plot, the differential

can_bus_nodes.txt is present but empty. The control block writes it
with "print v(txa_a) v(txb_a) v(rx_a) v(vcc5)", and Ngspice produced
no output for that line. The same data is in plot_data_v.txt and in
can_esim_ascii.raw, so nothing is lost. It is left in place because
this folder is the workspace exactly as it stands.

To view the raw output in Ngspice without re-running:

    ngspice
    load can_esim_ascii.raw
    plot v(x1.canh) v(x1.canl)
    plot v(x1.canh)-v(x1.canl)

Expected: both lines rest at 2.5 V, separate to 3.5 V and 1.5 V
when dominant. The differential is 0 V recessive and 2.0 V
dominant, rising to 2.85 V between roughly 26 and 55 microseconds
where both nodes drive dominant during arbitration.


ROUTE B - FULL REBUILD AND SIMULATE
------------------------------------

STEP 1.  Patch NGHDL.  THIS STEP IS REQUIRED.

Stock NGHDL cannot build a model made of more than one VHDL file.
Its generated start_server.sh analyses a fixed list containing only
the single uploaded file, so a controller split across ten files
never compiles. Three further defects also block this project. All
four fixes are included:

    cd nghdl_patches
    python3 patch_nghdl_multifile.py      REQUIRED, multi-file models
    python3 patch_nghdl_ghdl_order.py     VHDL dependency order
    python3 patch_nghdl_no_gtkwave.py     stops GTKWave auto-launch
    python3 patch_esim_microcontroller.py eSim project-open crash

Each script is idempotent, keeps the original as .orig, and prints
what it changed. They were written against eSim 2.5 and NGHDL as
shipped with it.

What patch_nghdl_multifile.py does: replaces the fixed analysis
list in NGHDL's model_generation.py with GHDL make mode, which
resolves dependency order by itself:

    ghdl -i *.vhdl &&
    ghdl -m -Wl,ghdlserver.o <entity>_tb &&

STEP 2.  Build the can_node_top model.

Launch NGHDL from INSIDE eSim, using the NGHDL icon in the left
toolbar. Launching it standalone works but does not generate the
KiCad symbol.

    Upload    :  vhdl/can_node_top.vhdl        (the top level)
    Add Files :  the other nine files in vhdl/

Then build. The ten files are:

    crc15.vhdl          bit_timing.vhdl     bit_stuff.vhdl
    frame_gen.vhdl      frame_rx.vhdl       can_tx_path.vhdl
    error_gen.vhdl      error_mgmt.vhdl     can_node.vhdl
    can_node_top.vhdl   <- top level, this is the model

These copies have no comments, deliberately. NGHDL's entity parser
scans every line for the words "port" and "end", including inside
comments, and mis-reads the port list if it finds them. The fully
commented sources are in the project repository.

STEP 3.  Open the project in eSim and simulate.

    cd <eSim workspace>
    esim

Double-click CAN_Bus_MixedSignal in the Projects tree. Single
clicking selects it without loading; the log must show
"The current project is: ...". Then click the Simulation icon.

Or run the netlist directly:

    ngspice -b CAN_Bus_MixedSignal.cir.out

Expect several minutes. Every digital event crossing the analog
boundary is a socket round trip to the GHDL server, so run time
scales with boundary traffic rather than with VHDL complexity.

Do not click the KiCad-to-Ngspice icon unless you intend to
regenerate the netlist; it overwrites CAN_Bus_MixedSignal.cir.out.


================================================================
FILES
================================================================

CAN_Bus_MixedSignal.kicad_sch   the schematic, KiCad 6 format
CAN_Bus_MixedSignal.cir         netlist exported from eeschema
                                 (Spice format, which eSim reads)
CAN_Bus_MixedSignal.cir.out     the Ngspice netlist produced by
                                 eSim's KiCad-to-Ngspice conversion.
                                 This is the file that is simulated.
CAN_Bus_MixedSignal.proj        eSim project file
CAN_Bus_MixedSignal_Previous_Values.xml   saved conversion parameters
analysis                        analysis settings
CAN_Bus_MixedSignal.pdf         printed schematic

can_phy.sub                     the analog transceiver and bus as an
                                 Ngspice subcircuit
can_phy/can_phy.sub             the same file in the directory layout
                                 eSim's Subcircuits tab expects

vhdl/                           the ten VHDL modules of the
                                 controller, NGHDL-ready
nghdl_patches/                  the four fixes needed before NGHDL
                                 can build this model

can_esim_ascii.raw              simulation output, ASCII raw
plot_data_v.txt                 node voltages
plot_data_i.txt                 branch currents
can_bus_nodes.txt               written empty by Ngspice, see above
client.log                      NGHDL socket log from the run
ngspice_bus.svg                 Ngspice plot, CANH and CANL
ngspice_diff.svg                Ngspice plot, differential
CAN_Bus_MixedSignal.kicad_sch.bak_gnd
                                schematic backup kept by the
                                workspace, not part of the design


================================================================
DESIGN PARAMETERS
================================================================

bit rate                125 kbit/s, 8.000 us bit time
time quanta per bit     16, so tq = 500 ns and the controller runs
                        at 2.000 MHz
segments                SYNC 1, PROP 5, PHASE1 6, PHASE2 4 tq
sample point            12 tq = 75 per cent
driver on-resistance    45 ohm
termination             120 ohm at each end
bus capacitance         500 pF per line
receiver thresholds     0.9 V dominant, 0.5 V recessive
identifiers             node A 0x0A5, node B 0x123

The propagation segment is measured, not assumed: over a 220 m bus
the one-way delay is 1.1136 us and the transceiver adds 21.6 ns, so
the round trip is 2.27 us against the 2.500 us that five time
quanta allow.


================================================================
WHAT THE SIMULATION SHOWS
================================================================

Reset releases at 2 us. Both nodes are asked to transmit at 10 us.
They contend, and node A wins because 0x0A5 is lower than 0x123.

Arbitration is visible in the analog waveform. Between about 26 us
and 55 us the differential reaches 2.85 V rather than 2.0 V,
because both nodes drive dominant at once and two 45 ohm drivers
in parallel present 22.5 ohm. After 55 us it settles to 2.0 V: one
node has withdrawn and a single driver remains.

Bus levels follow ISO 11898-2. CANH moves 2.5 to 3.5 V, CANL 2.5
to 1.5 V, differential 0 V recessive to 2 V dominant.


================================================================
KNOWN LIMITATIONS
================================================================

Standard 11-bit identifiers only. No extended identifiers, no
overload frames. A node that loses arbitration abandons the frame
rather than retrying.

This netlist drives both nodes from one clock, though
resynchronisation itself is verified against independent
oscillators in simulation: one node was swept from 0 to 6 per cent
skew and reception stayed correct to 3 per cent, three times the
derived 0.98 per cent bound, failing safely above that by flagging
an error rather than accepting corrupt data.

The comparator has no common-mode input range, so the model is
optimistic outside the range where real transceivers saturate.


================================================================
REFERENCES
================================================================

ISO 11898-1:2015  Road vehicles - Controller area network (CAN)
                  Part 1: Data link layer and physical signalling
ISO 11898-2:2016  Part 2: High-speed medium access unit
Bosch CAN Specification Version 2.0, Robert Bosch GmbH, 1991


================================================================
NOTE ON THE GUIDELINE 3 FILE LIST
================================================================

Guideline 3 lists .bak, cache.bak and .lib.xml. These are not
generated by eSim 2.5 with KiCad 6. KiCad 5 kept symbols in a
separate cache library; KiCad 6 embeds them in the schematic under
lib_symbols, so no cache is written. Under current naming, .pro
and .sch appear as .proj and .kicad_sch.

Everything the toolchain produces is included, and this folder is
the eSim workspace directory exactly as it stands.
