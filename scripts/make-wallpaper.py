# Draws the Yoga wallpaper (minimalist Japanese countryside at dusk) as SVG on stdout.
# Render: python3 scripts/make-wallpaper.py > wall.svg
#         rsvg-convert -w 3840 -h 2160 wall.svg -o profiles/wallpaper/japan-countryside-4k.png
import math, random, sys
random.seed(7)
W, H = 3840, 2160
out = []
a = out.append
a(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">')
a('''<defs>
<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#1c1f44"/>
  <stop offset="0.38" stop-color="#4a4479"/>
  <stop offset="0.62" stop-color="#b9839f"/>
  <stop offset="0.78" stop-color="#f2b7a6"/>
  <stop offset="1" stop-color="#ffd9bf"/>
</linearGradient>
<radialGradient id="sunglow" cx="0.5" cy="0.5" r="0.5">
  <stop offset="0" stop-color="#fff1e4" stop-opacity="0.55"/>
  <stop offset="1" stop-color="#fff1e4" stop-opacity="0"/>
</radialGradient>
<linearGradient id="water" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#e9b3a8"/>
  <stop offset="1" stop-color="#5a4c7d"/>
</linearGradient>
<filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="2.2"/></filter>
</defs>''')
a(f'<rect width="{W}" height="{H}" fill="url(#sky)"/>')
# stars in the upper sky
for _ in range(140):
    x, y = random.uniform(0, W), random.uniform(0, H*0.35)
    r = random.uniform(1.2, 3.2)
    a(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.1f}" fill="#ffffff" opacity="{random.uniform(0.25,0.8):.2f}"/>')
# sun
sx, sy = 1500, 1180
a(f'<circle cx="{sx}" cy="{sy}" r="720" fill="url(#sunglow)"/>')
a(f'<circle cx="{sx}" cy="{sy}" r="300" fill="#ffe9da" opacity="0.92"/>')
# Mt Fuji
fx, fy, base = 2500, 640, 1400
a(f'<path d="M {fx-1250} {base} L {fx-210} {fy+40} Q {fx} {fy-10} {fx+210} {fy+40} L {fx+1250} {base} Z" fill="#5d5487"/>')
a(f'<path d="M {fx-210} {fy+40} Q {fx} {fy-10} {fx+210} {fy+40} L {fx+330} {fy+190} L {fx+210} {fy+160} L {fx+120} {fy+230} L {fx+20} {fy+170} L {fx-90} {fy+240} L {fx-180} {fy+170} L {fx-330} {fy+190} Z" fill="#efe6f1" opacity="0.95"/>')
# hill layers (back to front)
def hills(y0, amp, color, seed, step=480):
    rnd = random.Random(seed)
    pts = []
    x = -200
    while x <= W + 2 * step:
        pts.append((x, y0 + rnd.uniform(-amp, amp)))
        x += step
    d = f'M -200 {H} L {pts[0][0]} {pts[0][1]:.0f} '
    for i in range(1, len(pts)):
        x0, y0_ = pts[i-1]; x1, y1 = pts[i]
        cx = (x0 + x1) / 2
        d += f'C {cx:.0f} {y0_:.0f} {cx:.0f} {y1:.0f} {x1:.0f} {y1:.0f} '
    d += f'L {pts[-1][0]:.0f} {H} Z'
    a(f'<path d="{d}" fill="{color}"/>')
hills(1330, 70, "#6e5f8f", 1)
hills(1430, 60, "#57497a", 2, 560)
# lake with sun reflection
lake_top = 1520
a(f'<rect x="0" y="{lake_top}" width="{W}" height="{H-lake_top}" fill="url(#water)"/>')
for i in range(14):
    y = lake_top + 40 + i * 34
    w = max(80, 520 - i * 30) * random.uniform(0.6, 1.0)
    off = random.uniform(-60, 60)
    a(f'<rect x="{sx - w/2 + off:.0f}" y="{y}" width="{w:.0f}" height="4" rx="2" fill="#fff1e4" opacity="{max(0.06, 0.32 - i*0.02):.2f}"/>')
# torii standing in the lake, with a soft reflection
def torii(tx, ty, sc, op, flip=False):
    sg = -1 if flip else 1
    def Y(v): return ty + sg * v * sc
    red = "#c94052"
    g = []
    g.append(f'<rect x="{tx-70*sc:.0f}" y="{min(Y(0),Y(-150)):.0f}" width="{16*sc:.0f}" height="{150*sc:.0f}"/>')
    g.append(f'<rect x="{tx+54*sc:.0f}" y="{min(Y(0),Y(-150)):.0f}" width="{16*sc:.0f}" height="{150*sc:.0f}"/>')
    g.append(f'<rect x="{tx-92*sc:.0f}" y="{min(Y(-118),Y(-106)):.0f}" width="{184*sc:.0f}" height="{12*sc:.0f}"/>')
    g.append(f'<path d="M {tx-120*sc:.0f} {Y(-162):.0f} Q {tx:.0f} {Y(-182):.0f} {tx+120*sc:.0f} {Y(-162):.0f} L {tx+112*sc:.0f} {Y(-146):.0f} Q {tx:.0f} {Y(-162):.0f} {tx-112*sc:.0f} {Y(-146):.0f} Z"/>')
    a(f'<g fill="{red}" opacity="{op}">' + "".join(g) + '</g>')
torii(3020, lake_top + 120, 1.35, 1.0)
torii(3020, lake_top + 120, 1.35, 0.28, flip=True)
# near shore
hills(1700, 40, "#3a3260", 3, 640)
hills(1880, 50, "#2a2448", 4, 700)
# cherry tree on the left foreground
bark = "#2a1f33"
def branch(x, y, ang, length, width, depth, rnd):
    if depth == 0 or length < 40:
        return [(x, y)]
    x2 = x + math.cos(ang) * length
    y2 = y + math.sin(ang) * length
    cx = (x + x2) / 2 + rnd.uniform(-length*0.15, length*0.15)
    cy = (y + y2) / 2 + rnd.uniform(-length*0.15, length*0.15)
    a(f'<path d="M {x:.0f} {y:.0f} Q {cx:.0f} {cy:.0f} {x2:.0f} {y2:.0f}" stroke="{bark}" stroke-width="{width:.1f}" stroke-linecap="round" fill="none"/>')
    tips = []
    for _ in range(2 if depth > 1 else 1):
        tips += branch(x2, y2, ang + rnd.uniform(-0.55, 0.55), length * rnd.uniform(0.62, 0.78), width * 0.66, depth - 1, rnd)
    if depth <= 3:
        tips.append((x2, y2))
    return tips
rnd = random.Random(11)
tips = []
tips += branch(330, H + 40, -1.25, 620, 64, 6, rnd)
tips += branch(420, 1500, -0.55, 520, 30, 5, rnd)
tips += branch(360, 1350, -1.75, 420, 24, 4, rnd)
pinks = ["#f7a8c4", "#f9c3d5", "#f28db1", "#fbd6e1", "#ee7fa6"]
blossoms = []
for (x, y) in tips:
    for _ in range(14):
        bx = x + rnd.gauss(0, 70); by = y + rnd.gauss(0, 55)
        r = rnd.uniform(16, 42)
        blossoms.append((by, bx, r, rnd.choice(pinks), rnd.uniform(0.55, 0.95)))
blossoms.sort()
for by, bx, r, c, o in blossoms:
    a(f'<circle cx="{bx:.0f}" cy="{by:.0f}" r="{r:.0f}" fill="{c}" opacity="{o:.2f}"/>')
# falling petals
for _ in range(110):
    x = rnd.uniform(200, W * 0.85); y = rnd.uniform(500, H - 60)
    rot = rnd.uniform(0, 180); s2 = rnd.uniform(0.7, 1.6)
    a(f'<ellipse cx="{x:.0f}" cy="{y:.0f}" rx="{10*s2:.1f}" ry="{5*s2:.1f}" transform="rotate({rot:.0f} {x:.0f} {y:.0f})" fill="{rnd.choice(pinks)}" opacity="{rnd.uniform(0.5,0.9):.2f}"/>')
a('</svg>')
sys.stdout.write("\n".join(out))
