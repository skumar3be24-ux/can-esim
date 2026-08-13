p = '/usr/share/kicad/symbols/eSim_Subckt.kicad_sym'
s = open(p).read()

if 'symbol "can_phy"' in s:
    print("can_phy symbol already present - nothing to do")
    raise SystemExit(0)

# Pin NUMBER determines netlist order, so it must match
#   .subckt can_phy txa txb rxo vcc gnd
# Positions are cosmetic: inputs left, output right.
pins = [
    ("input",  1, "txa", -5.15, 12.7,  0),
    ("input",  2, "txb", -5.15, 10.16, 0),
    ("input",  4, "vcc", -5.15, 7.62,  0),
    ("input",  5, "gnd", -5.15, 5.08,  0),
    ("output", 3, "rxo", 20.38, 8.89,  180),
]

body = ""
for kind, num, name, x, y, rot in pins:
    body += ('(pin %s line(at %s %s %d )(length 5.08 )'
             '(name "%s" (effects(font(size 1.27 1.27))))'
             '(number "%d" (effects (font (size 1.27 1.27)))))\n'
             % (kind, x, y, rot, name, num))

sym = (
'\t(symbol "can_phy" (pin_names (offset 1.016)) (in_bom yes) (on_board yes)\n'
'(property "Reference" "X" (id 0) (at 6 7 0)(effects (font (size 1.524 1.524))))\n'
'(property "Value" "can_phy" (id 1) (at 8 10 0)(effects (font (size 1.524 1.524))))\n'
'(property "Footprint" "" (id 2) (at 72.39 49.53 0)(effects (font (size 1.524 1.524))))\n'
'(property "Datasheet" "" (id 3) (at 72.39 49.53 0)(effects (font (size 1.524 1.524))))\n'
'(symbol "can_phy_0_1"(rectangle (start 0 0 ) (end 15.25 15.5 )'
'(stroke (width 0) (type default) (color 0 0 0 0))(fill (type none))))\n'
'(symbol "can_phy_1_1"\n' + body + '))\n')

# insert before the final closing paren of the library
i = s.rstrip().rfind(')')
s = s[:i] + sym + s[i:]
open(p, 'w').write(s)
print("can_phy symbol added with 5 pins, reference prefix X")
