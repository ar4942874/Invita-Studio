"""Category-specific original backgrounds: 10 motifs x 6 celebration palettes.

Complements tool/generate_art.py (the original nine designs). Each motif is drawn
once per category palette, so every category offers ten distinct designs whose
colouring matches the celebration. Decoration stays near the edges so the carved
text area in the middle is always legible.

Output: assets/art/<motif>_<category>_<format>.png and _thumb.png
"""
from PIL import Image, ImageDraw, ImageFilter
from pathlib import Path
import math
import random
import numpy as np

OUT = Path(__file__).resolve().parents[1] / 'assets' / 'art'
OUT.mkdir(parents=True, exist_ok=True)
FORMATS = {'classic': 1512, 'story': 1920, 'square': 1080}
S = 2

MOTIFS = [
    'botanical',
    'celestial',
    'petals',
    'foilframe',
    'arches',
    'confetti',
    'clouds',
    'constellation',
    'laurel',
    'sunburst',
]

# category -> (paper, ink, accent, dark)
CATEGORY_PALETTES = {
    'wedding': ('#F7F2E9', '#3B4A38', '#8A7A4E', False),
    'engagement': ('#FCF1F1', '#6E3F4C', '#C08A93', False),
    'birthday': ('#FFF8EC', '#2E3A59', '#F07A5F', False),
    'anniversary': ('#0F2A26', '#F6EFDC', '#C8A24B', True),
    'babyShower': ('#EFF6FB', '#4A6B86', '#F2B8C6', False),
    'other': ('#F7EFE7', '#7A4A32', '#C87F5A', False),
}


def hx(value):
    return tuple(int(value[i:i + 2], 16) for i in (1, 3, 5))


def paper_base(wl, hl, paper):
    """Flat paper with a very soft top/bottom shade; rows are uniform so the
    PNG stays small."""
    base = np.array(hx(paper), float)
    t = np.linspace(0, 1, hl * S)
    band = 1 - 0.030 * np.exp(-((t / 0.16) ** 2)) - 0.034 * np.exp(-(((1 - t) / 0.16) ** 2))
    row = (base[None, :] * band[:, None]).clip(0, 255).astype(np.uint8)
    grid = np.repeat(row[:, None, :], wl * S, axis=1)
    return Image.fromarray(grid, 'RGB')


def leaf(d, x, y, angle, length, width, fill):
    c, s = math.cos(angle), math.sin(angle)

    def tr(a, b):
        return ((x + a * c - b * s) * S, (y + a * s + b * c) * S)

    pts = []
    for i in range(25):
        t = i / 24
        pts.append(tr(length * t, width * math.sin(math.pi * t) * 0.5))
    for i in range(24, -1, -1):
        t = i / 24
        pts.append(tr(length * t, -width * math.sin(math.pi * t) * 0.5))
    d.polygon(pts, fill=fill)


def branch(d, base, angle, length, color):
    x, y = base
    c, s = math.cos(angle), math.sin(angle)
    pts = []
    for i in range(61):
        t = i / 60
        pts.append(((x + c * length * t + math.sin(t * math.pi) * 22) * S,
                    (y + s * length * t) * S))
    d.line(pts, fill=color, width=2, joint='curve')
    for i in range(2, 9):
        t = i / 10
        xx = x + c * length * t + math.sin(t * math.pi) * 22
        yy = y + s * length * t
        for side in (-1, 1):
            le = (1 - t * 0.5) * 58
            leaf(d, xx, yy, angle + side * 0.8, le, le * 0.30, color)


def motif_layer(motif, wl, hl, ink, accent, dark=False):
    ov = Image.new('RGBA', (wl * S, hl * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov, 'RGBA')

    def ia(a):
        return (ink[0], ink[1], ink[2], a)

    def aa(a):
        return (accent[0], accent[1], accent[2], a)

    top = hl * (0.075 if hl == 1080 else 0.105)
    cx = wl / 2

    if motif == 'botanical':
        d.rectangle((64 * S, 64 * S, (wl - 64) * S, (hl - 64) * S), outline=ia(70), width=2)
        branch(d, (16, 300), -0.95, 345, ia(120))
        branch(d, (68, 150), -0.25, 310, ia(95))
        branch(d, (wl - 16, hl - 300), 2.19, 345, ia(120))
        branch(d, (wl - 68, hl - 150), 2.89, 310, ia(95))
        for a in range(0, 360, 45):
            leaf(d, cx, top, math.radians(a), 22, 13, ia(150))
        d.ellipse(((cx - 4) * S, (top - 4) * S, (cx + 4) * S, (top + 4) * S), fill=aa(210))
    elif motif == 'celestial':
        for i in range(10):
            r = 64 + i * 16
            d.arc(((-r + 70) * S, (-r + 70) * S, (r + 70) * S, (r + 70) * S), 0, 90, fill=aa(95), width=2)
            d.arc(((wl - 70 - r) * S, (hl - 70 - r) * S, (wl - 70 + r) * S, (hl - 70 + r) * S), 180, 270, fill=aa(95), width=2)
        d.ellipse(((cx - 30) * S, (top - 30) * S, (cx + 30) * S, (top + 30) * S), outline=ia(200), width=2)
        for a in range(0, 360, 90):
            leaf(d, cx, top, math.radians(a), 20, 7, ia(200))
        rp = random.Random(3 + hl)
        for _ in range(60):
            px, py = rp.uniform(40, wl - 40), rp.uniform(40, hl - 40)
            if wl * 0.24 < px < wl * 0.76 and hl * 0.22 < py < hl * 0.82:
                continue
            r = rp.choice([1.3, 2.0, 2.8])
            d.ellipse(((px - r) * S, (py - r) * S, (px + r) * S, (py + r) * S), fill=aa(150))
    elif motif == 'petals':
        wash = Image.new('RGBA', ov.size)
        wd = ImageDraw.Draw(wash)
        for wx, wy, rx, ry in ((30, 90, 240, 240), (wl - 30, hl - 90, 260, 260), (wl - 60, 180, 120, 200)):
            wd.ellipse(((wx - rx) * S, (wy - ry) * S, (wx + rx) * S, (wy + ry) * S),
                       fill=(accent[0], accent[1], accent[2], 26))
        ov = Image.alpha_composite(ov, wash.filter(ImageFilter.GaussianBlur(40 * S)))
        d = ImageDraw.Draw(ov, 'RGBA')
        for x in (56, 70):
            d.rounded_rectangle((x * S, x * S, (wl - x) * S, (hl - x) * S), radius=420 * S, outline=aa(95), width=2)
        rp = random.Random(11 + hl)
        for _ in range(46):
            px, py = rp.uniform(50, wl - 50), rp.uniform(50, hl - 50)
            if wl * 0.24 < px < wl * 0.76 and hl * 0.24 < py < hl * 0.82:
                continue
            leaf(d, px, py, rp.uniform(0, 6.28), rp.uniform(13, 22), rp.uniform(5, 9), aa(150))
    elif motif == 'foilframe':
        for inset, alpha in ((50, 160), (64, 75)):
            d.rectangle((inset * S, inset * S, (wl - inset) * S, (hl - inset) * S), outline=aa(alpha), width=2)
        branch(d, (26, 290), -0.9, 330, ia(150))
        branch(d, (64, 240), -0.3, 290, ia(110))
        branch(d, (wl - 26, hl - 290), 2.25, 330, ia(150))
        branch(d, (wl - 64, hl - 240), 2.85, 290, ia(110))
        d.ellipse(((cx - 54) * S, (top - 54) * S, (cx + 54) * S, (top + 54) * S), outline=aa(210), width=2)
        d.ellipse(((cx - 42) * S, (top - 42) * S, (cx + 42) * S, (top + 42) * S), outline=aa(120), width=1)
        for a in range(0, 360, 60):
            leaf(d, cx, top, math.radians(a), 18, 6, aa(190))
        d.ellipse(((cx - 5) * S, (top - 5) * S, (cx + 5) * S, (top + 5) * S), fill=aa(235))
    elif motif == 'arches':
        cy, rr = hl * 0.31, hl * 0.215
        d.arc(((cx - rr) * S, (cy - rr) * S, (cx + rr) * S, (cy + rr) * S), 180, 360, fill=ia(115), width=2)
        for r in range(int(rr * 0.5), int(rr), max(1, int(rr * 0.16))):
            d.arc(((cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S), 180, 360, fill=ia(55), width=2)
        for a in range(20, 161, 18):
            ar = math.radians(a)
            d.line((cx * S, 0, (cx + math.cos(ar) * hl * 0.16) * S, (math.sin(ar) * hl * 0.16) * S), fill=aa(45), width=2)
        d.line((80 * S, (hl - 90) * S, (wl - 80) * S, (hl - 90) * S), fill=ia(90), width=2)
        d.arc(((120 * S, (hl - hl * 0.18) * S), ((wl - 120) * S, (hl + hl * 0.10) * S)), 180, 360, fill=aa(110), width=2)
        branch(d, (70, hl - 230), -1.2, 240, ia(120))
        branch(d, (wl - 70, hl - 230), -1.95, 240, ia(120))
    elif motif == 'confetti':
        rp = random.Random(21 + hl)
        palette = [(accent[0], accent[1], accent[2]), (ink[0], ink[1], ink[2]), (219, 178, 110)]

        def conf(px, py):
            c = rp.choice(palette)
            a, sz = rp.uniform(0, 6.28), rp.uniform(7, 13)
            cc, ss = math.cos(a), math.sin(a)

            def tr(ux, uy):
                return ((px + ux * cc - uy * ss) * S, (py + ux * ss + uy * cc) * S)

            d.polygon([tr(-sz, -sz * 0.4), tr(sz, -sz * 0.4), tr(sz, sz * 0.4), tr(-sz, sz * 0.4)],
                      fill=(c[0], c[1], c[2], 190))

        for _ in range(190):
            px, py = rp.uniform(36, wl - 36), rp.uniform(36, hl - 36)
            edge = px < 210 or px > wl - 210 or py < hl * 0.20 or py > hl * 0.82
            if not edge and rp.random() < 0.85:
                continue
            conf(px, py)
        d.rectangle((38 * S, 38 * S, (wl - 38) * S, (hl - 38) * S), outline=ia(55), width=2)
    elif motif == 'clouds':
        cloud = (255, 255, 255, 225) if not dark else (ink[0], ink[1], ink[2], 205)

        def cloud_at(ccx, ccy, sc):
            for dx, dy, r in ((-62, 2, 44), (0, -16, 58), (62, 2, 44), (32, 12, 40), (-32, 12, 40)):
                d.ellipse(((ccx + (dx - r) * sc) * S, (ccy + (dy - r) * sc) * S,
                           (ccx + (dx + r) * sc) * S, (ccy + (dy + r) * sc) * S), fill=cloud)

        cloud_at(190, hl * 0.13, 1.0)
        cloud_at(900, hl * 0.10, 0.82)
        cloud_at(cx, hl * 0.06, 0.6)
        cloud_at(150, hl * 0.90, 0.9)
        cloud_at(cx, hl * 0.965, 1.25)
        cloud_at(935, hl * 0.92, 0.95)
        rp = random.Random(5 + hl)
        for _ in range(40):
            px, py = rp.uniform(60, wl - 60), rp.uniform(60, hl - 60)
            if wl * 0.24 < px < wl * 0.76 and hl * 0.24 < py < hl * 0.82:
                continue
            r = rp.uniform(2, 4)
            d.ellipse(((px - r) * S, (py - r) * S, (px + r) * S, (py + r) * S), fill=aa(180))
        bx, by = 960, hl * 0.22
        d.line((bx * S, (by + 34) * S, (bx - 8) * S, (by + 140) * S), fill=ia(120), width=2)
        d.ellipse(((bx - 26) * S, (by - 32) * S, (bx + 26) * S, (by + 32) * S), fill=aa(210))
    elif motif == 'constellation':
        left = [(140, hl * 0.20), (230, hl * 0.30), (180, hl * 0.42), (300, hl * 0.50)]
        right = [(wl - 150, hl * 0.72), (wl - 250, hl * 0.80), (wl - 190, hl * 0.90), (wl - 320, hl * 0.84)]
        for pts in (left, right):
            for i in range(len(pts) - 1):
                d.line((pts[i][0] * S, pts[i][1] * S, pts[i + 1][0] * S, pts[i + 1][1] * S), fill=aa(90), width=1)
            for px, py in pts:
                d.ellipse(((px - 3) * S, (py - 3) * S, (px + 3) * S, (py + 3) * S), fill=aa(200))
        d.ellipse(((cx - 34) * S, (top - 34) * S, (cx + 34) * S, (top + 34) * S), outline=aa(200), width=2)
        d.ellipse(((cx - 24) * S, (top - 24) * S, (cx + 24) * S, (top + 24) * S), outline=aa(110), width=1)
        for a in range(30, 360, 60):
            leaf(d, cx, top, math.radians(a), 15, 5, aa(150))
        for inset in (44, 56):
            d.rectangle((inset * S, inset * S, (wl - inset) * S, (hl - inset) * S), outline=aa(60), width=1)
    elif motif == 'laurel':
        cy = hl * 0.50
        R = hl * 0.30
        for i in range(28):
            deg = i * 360 / 28
            if 240 < deg < 300:
                continue
            ang = math.radians(deg)
            lx, ly = cx + math.cos(ang) * R, cy + math.sin(ang) * R
            leaf(d, lx, ly, ang + math.pi / 2, 26, 10, ia(160))
        d.ellipse(((cx - 26) * S, (cy - R - 26) * S, (cx + 26) * S, (cy - R + 26) * S), outline=aa(210), width=2)
        d.ellipse(((cx - 6) * S, (cy - R - 6) * S, (cx + 6) * S, (cy - R + 6) * S), fill=aa(230))
    elif motif == 'sunburst':
        apex_y = -40
        for i in range(-8, 9):
            ang = math.radians(90 + i * 11)
            d.line((cx * S, apex_y * S,
                    (cx + math.cos(ang) * hl * 0.95) * S,
                    (apex_y + math.sin(ang) * hl * 0.95) * S), fill=aa(38), width=2)
        d.arc(((cx - 72) * S, (apex_y - 72) * S, (cx + 72) * S, (apex_y + 72) * S), 0, 360, fill=aa(165), width=2)
        d.arc(((cx - 58) * S, (apex_y - 58) * S, (cx + 58) * S, (apex_y + 58) * S), 0, 360, fill=aa(90), width=1)
        for i in range(-3, 4):
            ang = math.radians(90 + i * 15)
            leaf(d, cx, apex_y, ang, 40, 12, ia(150))
        step = wl / 18
        for i in range(1, 18):
            d.ellipse(((i * step - 2) * S, 30 * S, (i * step + 2) * S, 34 * S), fill=ia(120))
            d.ellipse(((i * step - 2) * S, (hl - 34) * S, (i * step + 2) * S, (hl - 30) * S), fill=ia(120))
        d.rectangle((26 * S, 26 * S, (wl - 26) * S, (hl - 26) * S), outline=ia(45), width=2)

    return ov


def art(motif, palette, hl):
    wl = 1080
    paper, ink, accent, dark = palette
    im = paper_base(wl, hl, paper).convert('RGBA')
    ov = motif_layer(motif, wl, hl, hx(ink), hx(accent), dark)
    return Image.alpha_composite(im, ov).convert('RGB')


def main():
    total = 0
    for category, palette in CATEGORY_PALETTES.items():
        for motif in MOTIFS:
            name = f'{motif}_{category}'
            for fmt, hl in FORMATS.items():
                im = art(motif, palette, hl)
                path = OUT / f'{name}_{fmt}.png'
                im.convert('P', palette=Image.ADAPTIVE, colors=256).save(path, optimize=True)
                total += path.stat().st_size
                if fmt == 'classic':
                    thumb = im.copy()
                    thumb.thumbnail((360, 504))
                    thumb.convert('P', palette=Image.ADAPTIVE, colors=256).save(
                        OUT / f'{name}_thumb.png', optimize=True)
            print(name, 'ok')
    print(f'generated {len(CATEGORY_PALETTES) * len(MOTIFS)} designs, {total / 1024 / 1024:.1f} MB')


if __name__ == '__main__':
    main()
