#!/usr/bin/env python3
"""v2: wider whiteout erase-zone (leftover corruption bled past the table's
own right edge), and page 27 rebuilt with tighter single-line phrasing and
a smaller font so it fits its original height with zero room to spare."""
import io
import shutil

import pikepdf
import pypdf
from reportlab.lib.colors import Color
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph, Table, TableStyle

SRC = "docs/CAN_Project_Technical_Report.pdf"
BAK = "docs/CAN_Project_Technical_Report.pdf.bak"
STAGE1 = "_stage1_entities.pdf"

PAGE_W, PAGE_H = 595.2756, 841.8898
REBUILT_PAGES = {5, 11, 18, 27}
ERASE_X0, ERASE_X1 = 0, 595.28

NAVY = Color(0.078431, 0.215686, 0.368627)
STRIPE = Color(0.956863, 0.964706, 0.976471)
WHITE = Color(1, 1, 1)
GRID = Color(0.8, 0.8, 0.8)

ENTITY_FIXES = [
    (b"&mdash;", b" - "), (b"&minus;", b"-"),
    (b"&lt;", b"<"), (b"&gt;", b">"), (b"&ge;", b">="),
]


def fix_entities():
    pdf = pikepdf.open(SRC)
    total = 0
    for i, page in enumerate(pdf.pages, 1):
        if i in REBUILT_PAGES:
            continue
        data = page.Contents.read_bytes()
        changed = False
        for old, new in ENTITY_FIXES:
            n = data.count(old)
            if n:
                data = data.replace(old, new)
                total += n
                changed = True
        if changed:
            page.Contents = pdf.make_stream(data)
    pdf.save(STAGE1)
    pdf.close()
    print(f"step 1: decoded {total} entity occurrences outside the rebuilt pages")


def style_for(size, bold=False, white=False):
    return ParagraphStyle(
        f"s{size}{bold}{white}",
        fontName="Times-Bold" if bold else "Times-Roman",
        fontSize=size, leading=size * 1.15,
        textColor=WHITE if white else Color(0, 0, 0),
        alignment=TA_LEFT,
    )


def build_table(rows, col_widths, font_size, pad=4):
    head_style = style_for(font_size, bold=True, white=True)
    body_style = style_for(font_size, bold=False, white=False)
    data = [[Paragraph(v, head_style if r == 0 else body_style) for v in row]
            for r, row in enumerate(rows)]
    t = Table(data, colWidths=col_widths)
    style = [
        ("BACKGROUND", (0, 0), (-1, 0), NAVY),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), pad),
        ("RIGHTPADDING", (0, 0), (-1, -1), pad),
        ("TOPPADDING", (0, 0), (-1, -1), pad - 1),
        ("BOTTOMPADDING", (0, 0), (-1, -1), pad - 1),
        ("GRID", (0, 0), (-1, -1), 0.4, GRID),
    ]
    for r in range(1, len(rows)):
        style.append(("BACKGROUND", (0, r), (-1, r), WHITE if r % 2 == 1 else STRIPE))
    t.setStyle(TableStyle(style))
    return t


def rl(y):
    return PAGE_H - y


def render_overlay(pageno, x0, pdf_top, x1, pdf_bottom, col_widths, rows, font_size, pad=4):
    rl_top = rl(pdf_top)
    rl_bottom_orig = rl(pdf_bottom)
    orig_height = rl_top - rl_bottom_orig

    t = build_table(rows, col_widths, font_size, pad)
    tw, th = t.wrap(x1 - x0, PAGE_H)

    grew = th - orig_height
    status = "OK" if grew <= 0.5 else f"OVERFLOW by {grew:.1f}pt - will eat into following text"
    print(f"  page {pageno}: table height {th:.1f}pt vs budget {orig_height:.1f}pt -> {status}")

    draw_bottom = rl_top - th
    erase_bottom = min(rl_bottom_orig, draw_bottom) - 6
    erase_top = rl_top + 6
    return t, x0, draw_bottom, (ERASE_X0, erase_bottom, ERASE_X1, erase_top)


OVERLAYS = {
    5: [dict(
        x0=72.28346, pdf_top=614.4237, x1=522.99216, pdf_bottom=717.6237,
        font_size=8.4, col_widths=[148, 118, 184.7],
        rows=[
            ["Originally planned", "What was done", "Why"],
            ["Four nodes from the start", "Two first, then four",
             "Two prove the mechanism, four prove it scales; debugging two is far easier"],
            ["eSim GUI throughout", "Command-line Ngspice for development",
             "The GUI loop is slow and fragile; direct Ngspice made the cycle seconds, not minutes"],
            ["Extended 29-bit identifiers", "Standard 11-bit only",
             "Adds frame-format complexity without demonstrating anything new about the bus"],
            ["Automatic retransmission", "Node abandons the frame",
             "Retransmission is a scheduling policy, not a bus mechanism"],
            ["Independent oscillators", "Now verified",
             "Verified over a 0 to 6 per cent skew sweep in tb_skew; the netlist itself still shares one clock"],
        ],
    )],
    11: [dict(
        x0=72.36535, pdf_top=368.7237, x1=522.99216, pdf_bottom=420.3237,
        font_size=8.4, col_widths=[65, 205, 180.6],
        rows=[
            ["Phase error", "Meaning", "Correction"],
            ["e > 0", "edge arrived late; node running early", "lengthen PHASE_SEG1 by min(e, SJW)"],
            ["e < 0", "edge arrived early; node running late", "TRUNCATE PHASE_SEG2, bounded by SJW"],
        ],
    )],
    18: [dict(
        x0=72.28346, pdf_top=711.62366, x1=522.99216, pdf_bottom=780.42366,
        font_size=8.4, col_widths=[90, 130, 230.7],
        rows=[
            ["State", "Condition", "Behaviour"],
            ["Error active", "TEC < 128 and REC < 128",
             "sends DOMINANT error flags; actively destroys frames it believes are bad"],
            ["Error passive", "TEC >= 128 or REC >= 128",
             "sends RECESSIVE error flags; signals without disrupting"],
            ["Bus off", "TEC >= 256",
             "disconnects entirely; recovery needs 128 occurrences of 11 recessive bits"],
        ],
    )],
    27: [
        dict(
            x0=77.28578, pdf_top=104.0237, x1=517.98981, pdf_bottom=224.4237,
            font_size=7.3, pad=2,
            col_widths=[14, 138, 138, 150.6],
            rows=[
                ["#", "Defect", "Effect", "Fix"],
                ["1", "UnboundLocalError on Convert",
                 "attr_microcontroller left unset",
                 "check added before first use"],
                ["2", "ghdl -a order is locale-dependent",
                 "testbench analysed before packages",
                 "fixed by GHDL make mode (#5)"],
                ["3", "GTKWave auto-launches per run",
                 "blocks batch runs",
                 "disabled in the generator"],
                ["4", "PyQt5 only in eSim's virtualenv",
                 "nghdl fails silently",
                 "installed system-wide"],
                ["5", "NGHDL can't build multi-file VHDL",
                 "analyses only the uploaded file",
                 "GHDL make mode: ghdl -i, ghdl -m"],
                ["6", "Entity parser scans for port/end",
                 "comments corrupt the port scan",
                 "comments stripped from sources"],
            ],
        ),
        dict(
            x0=77.28578, pdf_top=458.4237, x1=517.98981, pdf_bottom=596.0237,
            font_size=7.3, pad=2,
            col_widths=[138, 152, 150.7],
            rows=[
                ["Bug", "Cause", "Lesson"],
                ["Lost arbitration against empty bus",
                 "compared pre- vs post-stuffing bit",
                 "arbitration is a wire property"],
                ["Payload bit dropped per stuff bit",
                 "tx_stall registered a clock late",
                 "handshakes must be valid in-slot"],
                ["Counter overflow, fixed-form fields",
                 "13 recessive bits, counter not reset",
                 "isolated tests missed this path"],
                ["Counter overflow, error branch",
                 "same bug, unreached by isolated tests",
                 "bug recurs where tests can't reach"],
                ["ACK'd frames raised spurious errors",
                 "exclusion lagged the ACK by one field",
                 "registered signals lag by a cycle"],
                ["Remote frame kept old payload",
                 "RTR has no data field to clear it",
                 "clear decoded state every frame"],
                ["Ground shorted to a signal net",
                 "wire stubs met exactly halfway",
                 "route point-to-point; check geometry"],
            ],
        ),
    ],
}


def fix_tables():
    base = pypdf.PdfReader(STAGE1)
    writer = pypdf.PdfWriter()

    for i, page in enumerate(base.pages, 1):
        specs = OVERLAYS.get(i)
        if specs:
            buf = io.BytesIO()
            c = canvas.Canvas(buf, pagesize=(PAGE_W, PAGE_H))
            for spec in specs:
                pad = spec.get("pad", 4)
                t, x0, draw_bottom, wo = render_overlay(
                    i, spec["x0"], spec["pdf_top"], spec["x1"], spec["pdf_bottom"],
                    spec["col_widths"], spec["rows"], spec["font_size"], pad,
                )
                c.setFillColor(WHITE)
                c.setStrokeColor(WHITE)
                c.rect(wo[0], wo[1], wo[2] - wo[0], wo[3] - wo[1], fill=1, stroke=0)
                t.drawOn(c, x0, draw_bottom)
            c.save()
            buf.seek(0)
            overlay_page = pypdf.PdfReader(buf).pages[0]
            page.merge_page(overlay_page)
        writer.add_page(page)

    with open(SRC, "wb") as f:
        writer.write(f)
    print(f"\nwritten {SRC} (restore from {BAK} if needed)")


if __name__ == "__main__":
    fix_entities()
    fix_tables()
