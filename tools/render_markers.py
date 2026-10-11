# A preview of the waypoint markers over a game screenshot. python3 -I render_markers.py <Media> <bg.png> <out.png>
import sys
from PIL import Image, ImageChops, ImageDraw, ImageFont
media, bg_path, out = sys.argv[1:4]
S = 2
src = Image.open(bg_path).convert("RGB").crop((420, 0, 1023, 425))
W, H = 4 * 230 * S, 300 * S
bg = src.resize((round(src.width * max(W / src.width, H / src.height)), round(src.height * max(W / src.width, H / src.height))), Image.LANCZOS).crop((0, 0, W, H)).convert("RGBA")
gold = (242, 199, 92)
font = ImageFont.truetype(media + "/Inter-Medium.ttf", 12 * S)
title = ImageFont.truetype(media + "/Inter-SemiBold.ttf", 14 * S)

def tint(img, col, alpha=1.0):
    r, g, b, a = img.split()
    a = a.point(lambda v: int(v * alpha))
    solid = Image.new("RGBA", img.size, col + (0,))
    solid.putalpha(a)
    lum = Image.merge("RGBA", (r, g, b, Image.new("L", img.size, 255)))
    mul = ImageChops.multiply(lum, Image.new("RGBA", img.size, col + (255,)))
    mul.putalpha(a)
    return mul

def add(base, img, pos):
    # additive blend
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    layer.paste(img, pos, img)
    r, g, b, a = layer.split()
    pre = Image.merge("RGB", [ImageChops.multiply(c, a) for c in (r, g, b)])
    out = ImageChops.add(base.convert("RGB"), pre)
    return out.convert("RGBA")

def text(img, xy, s, f=font, fill=(255, 255, 255, 255), anchor="mt"):
    d = ImageDraw.Draw(img)
    d.text((xy[0] + S, xy[1] + S), s, font=f, fill=(0, 0, 0, 200), anchor=anchor)
    d.text(xy, s, font=f, fill=fill, anchor=anchor)

ground_y = 200 * S
cols = [115 * S + i * 230 * S for i in range(4)]
# Gold ring: frame 3 of the first sheet, with its glow.
sheet = Image.open(media + "/Ring/Ring1.tga").convert("RGBA")
cell = sheet.crop((256 * 3, 0, 256 * 4, 256)).resize((104 * S, 104 * S), Image.LANCZOS)
glow = Image.open(media + "/Ring/Glow.tga").convert("RGBA").resize((176 * S, 176 * S), Image.LANCZOS)
x = cols[0]
bg = add(bg, tint(glow, (255, 255, 255), 0.3), (x - 88 * S, ground_y - 8 * S - 52 * S - 88 * S + 52 * S - 52 * S))
bg.alpha_composite(cell, (x - 52 * S, ground_y - 8 * S - 104 * S))
# Beacon
beam = Image.open(media + "/beam.tga").convert("RGBA").resize((52 * S, 300 * S // 1), Image.LANCZOS)
beam = beam.resize((52 * S, 290 * S - 110 * S))
x = cols[1]
bg = add(bg, tint(beam, gold, 0.9), (x - 26 * S, ground_y - beam.height + 6 * S))
base = Image.open(media + "/Ring/Glow.tga").convert("RGBA").resize((104 * S, 52 * S), Image.LANCZOS)
bg = add(bg, tint(base, gold, 0.9), (x - 52 * S, ground_y - 26 * S))
# Pin
pin = Image.open(media + "/markerpin.tga").convert("RGBA").resize((60 * S, 60 * S), Image.LANCZOS)
sh = Image.open(media + "/shadow.tga").convert("RGBA").resize((42 * S, 17 * S), Image.LANCZOS)
x = cols[2]
bg.alpha_composite(sh, (x - 21 * S, ground_y - 8 * S))
bg.alpha_composite(tint(pin, gold), (x - 30 * S, ground_y - 10 * S - 60 * S))
# Off-screen arrow (navigation icon from the atlas), rotated toward the edge.
atlas = Image.open(media + "/icons.tga").convert("RGBA")
i = 39
icon = atlas.crop(((i % 8) * 64, (i // 8) * 64, (i % 8 + 1) * 64, (i // 8 + 1) * 64)).resize((40 * S, 40 * S), Image.LANCZOS)
x = cols[3]
arrow = tint(icon, gold).rotate(-45 + 0, resample=Image.BICUBIC, expand=True)
bg.alpha_composite(arrow, (x - arrow.width // 2, ground_y - 70 * S))
names = ["Gold ring", "Beacon", "Pin", "Off screen"]
for k, n in enumerate(names):
    text(bg, (cols[k], 16 * S), n, f=title)
    if k < 3:
        text(bg, (cols[k], ground_y + 12 * S), "Talk to Shadow Priest Sarvis  ·  72 yd")
    else:
        text(bg, (cols[k], ground_y - 22 * S), "640 yd")
        text(bg, (cols[k], ground_y + 12 * S), "points the way from the screen's edge", fill=(220, 225, 230, 255))
bg.convert("RGB").save(out)
print(out, bg.size)
