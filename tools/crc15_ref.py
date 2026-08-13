#!/usr/bin/env python3
"""
CAN CRC-15 reference model and test-vector generator.

Polynomial: x^15 + x^14 + x^10 + x^8 + x^7 + x^4 + x^3 + 1 = 0x4599

This is an INDEPENDENT implementation. Its whole purpose is to
disagree with the VHDL if the VHDL is wrong, so it is written
directly from the ISO 11898-1 definition rather than from the RTL.

Two hand-computed vectors prove essentially nothing about a CRC -
a broken implementation passes them routinely. This generates
several hundred random vectors instead, plus targeted edge cases.

Output: crc_vectors.txt, one vector per line:
    <nbits> <bitstring> <crc_hex>
"""

import random

POLY = 0x4599
CRC_BITS = 15
CRC_MASK = (1 << CRC_BITS) - 1     # 0x7FFF


def crc15(bits):
    """
    bits: iterable of 0/1 ints, MSB-first in transmission order.
    Returns the 15-bit CRC as an int.

    Per ISO 11898-1: register starts at 0; for each bit, XOR the
    incoming bit with the register MSB; shift left; if that XOR
    was 1, XOR the polynomial in.
    """
    crc = 0
    for b in bits:
        msb = (crc >> (CRC_BITS - 1)) & 1
        crc = (crc << 1) & CRC_MASK
        if (msb ^ b) & 1:
            crc ^= POLY
    return crc & CRC_MASK


def bits_from_int(value, width):
    """MSB-first bit list of `value` in `width` bits."""
    return [(value >> (width - 1 - i)) & 1 for i in range(width)]


def build_frame_bits(can_id, rtr, dlc, data_bytes):
    """
    Assemble the CRC-covered portion of a standard CAN data frame:
      SOF(1) + ID(11) + RTR(1) + IDE(1) + r0(1) + DLC(4) + data(8*n)

    This is the field sequence the CRC covers - everything from SOF
    up to but NOT including the CRC sequence. Note these are
    DESTUFFED bits: the CRC is computed on the payload, never on
    the stuffed bus stream. Computing it over stuffed bits yields a
    value the receiver can never match.
    """
    bits = []
    bits.append(0)                          # SOF is dominant
    bits += bits_from_int(can_id, 11)       # 11-bit identifier
    bits.append(rtr)                        # RTR
    bits.append(0)                          # IDE = 0 (standard)
    bits.append(0)                          # r0 reserved
    bits += bits_from_int(dlc, 4)           # DLC
    for byte in data_bytes:
        bits += bits_from_int(byte, 8)
    return bits


def main():
    random.seed(20260812)      # deterministic - vectors reproduce exactly
    vectors = []

    # ---------- targeted edge cases ----------
    # all-zero input: CRC must stay 0 (nothing ever sets a bit)
    vectors.append([0] * 19)

    # single 1 in the MSB position: exercises the polynomial XOR
    vectors.append([1] + [0] * 18)

    # single 1 in the LSB position
    vectors.append([0] * 18 + [1])

    # all ones
    vectors.append([1] * 19)

    # alternating
    vectors.append([i % 2 for i in range(19)])

    # exactly 15 bits - same width as the register
    vectors.append([1, 0, 1, 1, 0, 0, 0, 1, 0, 1, 0, 0, 1, 1, 0])

    # a single bit
    vectors.append([1])
    vectors.append([0])

    # ---------- the frozen node IDs from the spec ----------
    for can_id in (0x0A5, 0x123, 0x2AA):
        vectors.append(build_frame_bits(can_id, 0, 0, []))
        vectors.append(build_frame_bits(can_id, 0, 1, [0x5A]))
        vectors.append(build_frame_bits(can_id, 0, 8,
                                        [0xDE, 0xAD, 0xBE, 0xEF,
                                         0x01, 0x23, 0x45, 0x67]))

    # ---------- random realistic frames ----------
    for _ in range(200):
        can_id = random.randrange(0, 1 << 11)
        rtr = random.randrange(0, 2)
        dlc = random.randrange(0, 9)
        data = [random.randrange(0, 256) for _ in range(dlc)]
        vectors.append(build_frame_bits(can_id, rtr, dlc, data))

    # ---------- random bit strings of assorted lengths ----------
    for _ in range(200):
        n = random.randrange(1, 100)
        vectors.append([random.randrange(0, 2) for _ in range(n)])

    # ---------- write ----------
    with open('crc_vectors.txt', 'w') as f:
        for bits in vectors:
            s = ''.join(str(b) for b in bits)
            f.write('%d %s %04X\n' % (len(bits), s, crc15(bits)))

    print('wrote crc_vectors.txt: %d vectors' % len(vectors))
    print()
    print('Sanity values:')
    print('  all-zero  x19       -> %04X' % crc15([0] * 19))
    print('  MSB only  x19       -> %04X' % crc15([1] + [0] * 18))
    print('  all-ones  x19       -> %04X' % crc15([1] * 19))
    print('  ID 0x0A5, DLC 0     -> %04X'
          % crc15(build_frame_bits(0x0A5, 0, 0, [])))
    print('  ID 0x0A5, DLC 1 5A  -> %04X'
          % crc15(build_frame_bits(0x0A5, 0, 1, [0x5A])))
    print()
    print('Note: the all-zero CRC MUST be 0000. If the VHDL gives')
    print('anything else its register is not initialising to zero.')


if __name__ == '__main__':
    main()
