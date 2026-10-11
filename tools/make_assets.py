# Builds RXP Next Step's card assets: an icon atlas from Lucide's font, rounded-panel textures,
# and copies the Inter font files. Run with: python3 -I make_assets.py <lucide pkg> <inter pkg> <out Media dir>
import json, os, shutil, sys
from PIL import Image, ImageDraw, ImageFont

lucide, inter, out = sys.argv[1:4]
os.makedirs(out, exist_ok=True)

# ---------------------------------------------------------------- icon atlas
ICONS = [
    "circle-alert", "circle-help", "swords", "map-pin", "message-circle", "bird", "flag", "house",
    "bed", "graduation-cap", "coins", "shopping-bag", "chevrons-up", "sparkles", "package", "trash-2",
    "lightbulb", "triangle-alert", "check", "circle", "chevron-left", "chevron-right", "chevron-up", "chevron-down",
    "settings", "eye", "eye-off", "info", "x", "skip-forward", "menu", "circle-check",
    "circle-dashed", "footprints", "lock", "hand", "scroll-text", "hourglass", "undo-2", "navigation",
]
codepoints = json.load(open(os.path.join(lucide, "font", "codepoints.json")))
CELL, GRID = 64, 8
atlas = Image.new("RGBA", (CELL * GRID, CELL * GRID), (255, 255, 255, 0))
font = ImageFont.truetype(os.path.join(lucide, "font", "lucide.ttf"), 52)
order = []
for i, name in enumerate(ICONS):
    cp = codepoints[name]
    glyph = chr(cp)
    cell = Image.new("L", (CELL, CELL), 0)
    d = ImageDraw.Draw(cell)
    l, t, r, b = d.textbbox((0, 0), glyph, font=font)
    d.text(((CELL - (r - l)) / 2 - l, (CELL - (b - t)) / 2 - t), glyph, font=font, fill=255)
    white = Image.new("RGBA", (CELL, CELL), (255, 255, 255, 0))
    white.putalpha(cell)
    atlas.paste(white, ((i % GRID) * CELL, (i // GRID) * CELL))
    order.append(name)
atlas.save(os.path.join(out, "icons.tga"))
json.dump(order, open(os.path.join(out, "..", "..", "tools", "icons.json"), "w"), indent=1)

# ---------------------------------------------------------------- rounded panel (9-slice)
# 64x64, drawn 4x larger then reduced for smooth corners. Corner radius 16 texels; the card shows
# the corners at 8 UI px. border.tga is a 2-texel ring (1 px on screen) with the same shape.
def rounded(size, radius, ring=None, scale=4):
    big = Image.new("L", (size * scale, size * scale), 0)
    d = ImageDraw.Draw(big)
    d.rounded_rectangle((0, 0, size * scale - 1, size * scale - 1), radius=radius * scale, fill=255)
    if ring:
        w = ring * scale
        d.rounded_rectangle((w, w, size * scale - 1 - w, size * scale - 1 - w), radius=(radius - ring) * scale, fill=0)
    mask = big.resize((size, size), Image.LANCZOS)
    im = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    im.putalpha(mask)
    return im
rounded(64, 16).save(os.path.join(out, "panel.tga"))
rounded(64, 16, ring=2).save(os.path.join(out, "border.tga"))

# ---------------------------------------------------------------- fonts and licences
for weight, name in (("400Regular", "Inter-Regular.ttf"), ("500Medium", "Inter-Medium.ttf"), ("600SemiBold", "Inter-SemiBold.ttf")):
    src = os.path.join(inter, weight, "Inter_%s.ttf" % weight)
    shutil.copyfile(src, os.path.join(out, name))
with open(os.path.join(out, "LICENSES.txt"), "w") as f:
    f.write("Inter (Inter-*.ttf)\n" + "=" * 60 + "\n")
    f.write(open(os.path.join(inter, "LICENSE_FONT")).read())
    f.write("\n\nLucide icons (icons.tga, rendered from lucide.ttf)\n" + "=" * 60 + "\n")
    f.write(open(os.path.join(lucide, "LICENSE")).read())
print("icons:", len(order))
