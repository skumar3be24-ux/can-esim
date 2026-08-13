#!/usr/bin/env python3
"""
CAN standard frame reference model and vector generator.

Emits the complete expected bit sequence for a standard data
frame, together with the per-bit stuff_en flag, so the VHDL
frame_gen can be checked bit-exactly against an independent
model rather than against my own expectations.

Written from ISO 11898-1, NOT from the RTL.

Output: frame_vectors.txt, one frame per line:

    <id_hex> <rtr> <dlc> <databytes_hex> <nbits> <bitstring> <stuffstring>

  bitstring   : the frame bits BEFORE stuffing, MSB first
  stuffstring : '1' where the downstream stuffer must be active

Field layout and stuffing scope:

  SOF            1   dominant                stuffed
  Identifier    11   MSB first               stuffed
  RTR            1                           stuffed
  IDE            1   0 = standard            stuffed
  r0             1   reserved dominant       stuffed
  DLC            4                           stuffed
  Data       0..64   MSB first               stuffed
  CRC sequence  15                           stuffed
  CRC delimiter  1   recessive               NOT stuffed
  ACK slot       1   recessive from TX       NOT stuffed
  ACK delimiter  1   recessive               NOT stuffed
  EOF            7   recessive               NOT stuffed
  IFS            3   recessive               NOT stuffed

  DLC=0 -> 44 frame bits + 3 IFS = 47 emitted
  DLC=8 -> 108 frame bits + 3 IFS = 111 emitted

  NOTE: interframe space is NOT part of the frame. The frame ends
  after EOF. IFS is the mandatory gap BEFORE the next frame, and
  during it the bus is idle and any node may start transmitting.
  frame_active must therefore drop at the end of EOF, not after
  IFS, or arbitration is blocked for 3 bit times.
"""

import random

POLY = 0x4599
CRC_BITS = 15
CRC_MASK = (1 << CRC_BITS) - 1


def crc15(bits):
    crc = 0
    for b in bits:
        msb = (crc >> (CRC_BITS - 1)) & 1
        crc = (crc << 1) & CRC_MASK
        if (msb ^ b) & 1:
            crc ^= POLY
    return crc & CRC_MASK


def bits_from_int(value, width):
    return [(value >> (width - 1 - i)) & 1 for i in range(width)]


def build_frame(can_id, rtr, dlc, data_bytes):
    """
    Returns (bits, stuff_flags).
    bits are the UNSTUFFED frame bits; stuff_flags[i] is 1 where
    the downstream stuffer must be active for bits[i].
    """
    bits = []
    stuff = []

    def add(bs, stuffed):
        for b in bs:
            bits.append(b)
            stuff.append(1 if stuffed else 0)

    # ---- CRC-covered portion ----
    add([0], True)                            # SOF
    add(bits_from_int(can_id, 11), True)      # identifier
    add([rtr], True)                          # RTR
    add([0], True)                            # IDE
    add([0], True)                            # r0
    add(bits_from_int(dlc, 4), True)          # DLC
    for byte in data_bytes:
        add(bits_from_int(byte, 8), True)     # data

    # the CRC covers exactly what has been added so far
    crc = crc15(bits)

    # ---- CRC sequence: stuffed, but NOT covered by itself ----
    add(bits_from_int(crc, 15), True)

    # ---- fixed-form fields: NOT stuffed ----
    add([1], False)          # CRC delimiter
    add([1], False)          # ACK slot - transmitter sends recessive
    add([1], False)          # ACK delimiter
    add([1] * 7, False)      # EOF
    add([1] * 3, False)      # IFS

    return bits, stuff


def stuff_stream(bits, stuff_flags):
    """
    Apply bit stuffing to a payload, returning the bus stream.

    Insert a bit of opposite polarity AFTER five consecutive
    identical bits, while stuffing is active for that field. The
    stuffed bit itself begins the next run, so twelve identical
    bits yield TWO stuff bits.

    Day 27 note: an earlier version of this function tracked the
    run with an index that was one behind the bit being appended,
    placing every stuff bit one position early. The VHDL was
    correct and this model was not. Verified against the captured
    DUT stream: for ID 0x0A5 DLC 0 the run of five completes at
    payload index 16 and the stuff bit sits at bus position 17.
    """
    out = []
    run_val = None
    run_len = 0
    for idx, b in enumerate(bits):
        out.append(b)
        if b == run_val:
            run_len += 1
        else:
            run_val = b
            run_len = 1
        if run_len == 5 and stuff_flags[idx] == 1:
            s = 1 - b
            out.append(s)
            run_val = s
            run_len = 1
    return out


def main():
    random.seed(20260813)
    frames = []

    # ---- targeted cases ----
    # the frozen node IDs at DLC 0
    for can_id in (0x0A5, 0x123, 0x2AA):
        frames.append((can_id, 0, 0, []))

    # DLC 1 and DLC 8 on the primary ID
    frames.append((0x0A5, 0, 1, [0x5A]))
    frames.append((0x0A5, 0, 8, [0xDE, 0xAD, 0xBE, 0xEF,
                                 0x01, 0x23, 0x45, 0x67]))

    # all-zero ID and data: maximum dominant run, heavy stuffing
    frames.append((0x000, 0, 8, [0x00] * 8))

    # all-ones ID and data: maximum recessive run
    frames.append((0x7FF, 0, 8, [0xFF] * 8))

    # RTR frame (remote): DLC nonzero but no data field
    frames.append((0x0A5, 1, 0, []))

    # ---- random frames ----
    for _ in range(60):
        can_id = random.randrange(0, 1 << 11)
        rtr = 0
        dlc = random.randrange(0, 9)
        data = [random.randrange(0, 256) for _ in range(dlc)]
        frames.append((can_id, rtr, dlc, data))

    with open('frame_vectors.txt', 'w') as f:
        for can_id, rtr, dlc, data in frames:
            bits, stuff = build_frame(can_id, rtr, dlc, data)
            datahex = ''.join('%02X' % b for b in data)
            if datahex == '':
                datahex = '-'
            busbits = stuff_stream(bits, stuff)
            f.write('%03X %d %d %s %d %s %s %d %s\n' % (
                can_id, rtr, dlc, datahex, len(bits),
                ''.join(str(b) for b in bits),
                ''.join(str(s) for s in stuff),
                len(busbits),
                ''.join(str(b) for b in busbits)))

    print('wrote frame_vectors.txt: %d frames' % len(frames))
    print()

    # sanity display of one complete frame
    bits, stuff = build_frame(0x0A5, 0, 0, [])
    print('Example: ID 0x0A5, RTR 0, DLC 0')
    print('  total bits      : %d  (44 frame + 3 IFS)' % len(bits))
    print('  bits            : %s' % ''.join(str(b) for b in bits))
    print('  stuff_en        : %s' % ''.join(str(s) for s in stuff))
    print('  stuffed bits    : %d  (SOF+11+1+1+1+4+15 = 34)'
          % sum(stuff))
    print('  CRC             : %04X' % crc15(bits[:19]))
    print()

    bits8, stuff8 = build_frame(0x0A5, 0, 8,
                                [0xDE, 0xAD, 0xBE, 0xEF,
                                 0x01, 0x23, 0x45, 0x67])
    print('Example: ID 0x0A5, RTR 0, DLC 8')
    print('  total bits      : %d  (108 frame + 3 IFS)' % len(bits8))
    print('  stuffed bits    : %d  (34 + 64 data = 98)' % sum(stuff8))
    print()
    print('The stuff_en boundary is the thing this day exists to')
    print('verify: high through the last CRC bit, low from the CRC')
    print('delimiter onward. One bit either way corrupts every frame.')


if __name__ == '__main__':
    main()
