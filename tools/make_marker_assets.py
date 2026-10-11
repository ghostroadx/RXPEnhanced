# Waypoint marker art for RXP Next Step: a light beam (Beacon), a filled map pin (Pin) and a soft
# ground shadow. All white, tinted in the game. python3 -I make_marker_assets.py <Media dir>
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter

out = sys.argv[1]

# Beacon: 64 x 256, brightest at the bottom, a bright core inside a soft halo.
W, H = 64, 256
beam = Image.new("RGBA", (W, H), (255, 255, 255, 0))
px = beam.load()
for y in range(H):
    t = 1 - y / (H - 1)            # 0 at the bottom, 1 at the top
    v = (1 - t) ** 0.85
    for x in range(W):
        u = (x - (W - 1) / 2) / ((W - 1) / 2)
        core = math.exp(-(u / 0.24) ** 2)
        halo = math.exp(-(u / 0.6) ** 2) * 0.6
        a = min(1.0, (core + halo)) * v
        px[x, y] = (255, 255, 255, round(a * 255))
beam.save(os.path.join(out, "beam.tga"))

# Pin: 128 x 128, a teardrop with a hole, light from the top left, a dark rim for bright scenes.
S = 4
N = 128 * S
big = Image.new("RGBA", (N, N), (0, 0, 0, 0))
d = ImageDraw.Draw(big)
cx, cy, r = 64 * S, 46 * S, 38 * S
tip = (64 * S, 124 * S)
ang = math.asin(r / (tip[1] - cy))
pts = [tip]
for k in range(0, 181):
    a = math.pi / 2 + ang + (2 * math.pi - 2 * ang) * k / 180   # around the top of the circle
    pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
# outer rim (dark), then the body
rim = Image.new("L", (N, N), 0)
ImageDraw.Draw(rim).polygon(pts, fill=255)
rim = rim.filter(ImageFilter.MaxFilter(3 * S + 1))
body = Image.new("L", (N, N), 0)
ImageDraw.Draw(body).polygon(pts, fill=255)
shade = Image.new("L", (N, N), 0)
sp = shade.load()
for y in range(0, N, 1):
    for x in range(0, N, 4):
        v = 255 - int(70 * ((x / N) * 0.6 + (y / N) * 0.6))
        for k in range(4):
            if x + k < N:
                sp[x + k, y] = max(150, min(255, v))
hole = Image.new("L", (N, N), 0)
ImageDraw.Draw(hole).ellipse((cx - 15 * S, cy - 15 * S, cx + 15 * S, cy + 15 * S), fill=255)
img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
img.paste((20, 20, 24, 170), (0, 0), rim)
lum = Image.merge("RGB", (shade, shade, shade))
bodyrgba = Image.merge("RGBA", (*lum.split(), body))
img.alpha_composite(bodyrgba)
img.paste((40, 40, 46, 255), (0, 0), hole)
img = img.resize((128, 128), Image.LANCZOS)
img.save(os.path.join(out, "markerpin.tga"))

# Ground shadow: 64 x 32 soft ellipse.
sh = Image.new("RGBA", (64, 32), (0, 0, 0, 0))
p = sh.load()
for y in range(32):
    for x in range(64):
        u, v = (x - 31.5) / 31.5, (y - 15.5) / 15.5
        q = u * u + v * v
        p[x, y] = (0, 0, 0, round(max(0.0, 1 - q) ** 1.5 * 200))
sh.save(os.path.join(out, "shadow.tga"))
print("ok")
