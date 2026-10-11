# Art for the toast and the settings window. python3 -I make_ui_assets.py <Media dir>
#  - toastshadow.tga: the toast's soft drop shadow, a blurred rounded rectangle, white (tinted black
#    in the game), drawn as a nine-slice with quarter corners. Toast.lua's SHADOW numbers depend
#    on these: 128 px, the card's edge 20 px in, blur sigma 4.5.
#  - controls.tga: the settings controls, four 32 px cells side by side: a rounded box, its ring,
#    a dot, and its ring (checkboxes, radio buttons, slider thumbs, colour swatches).
import os, sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter

out = sys.argv[1]
SS = 4

# ---------------------------------------------------------------- toast shadow
SIZE, INSET, RADIUS, SIGMA = 128, 20, 12, 4.5
mask = Image.new("L", (SIZE * SS, SIZE * SS), 0)
ImageDraw.Draw(mask).rounded_rectangle(
    (INSET * SS, INSET * SS, (SIZE - INSET) * SS - 1, (SIZE - INSET) * SS - 1), radius=RADIUS * SS, fill=255)
mask = mask.resize((SIZE, SIZE), Image.LANCZOS).filter(ImageFilter.GaussianBlur(SIGMA))
img = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
img.putalpha(mask)
img.save(os.path.join(out, "toastshadow.tga"))

# ---------------------------------------------------------------- settings controls
CELL, PAD, BOX_RADIUS, STROKE = 32, 1, 7, 3


def shape(kind, inset, radius):
    m = Image.new("L", (CELL * SS, CELL * SS), 0)
    d = ImageDraw.Draw(m)
    box = (inset * SS, inset * SS, (CELL - inset) * SS - 1, (CELL - inset) * SS - 1)
    if kind == "box":
        d.rounded_rectangle(box, radius=radius * SS, fill=255)
    else:
        d.ellipse(box, fill=255)
    return m


cells = []
for kind in ("box", "dot"):
    fill = shape(kind, PAD, BOX_RADIUS)
    ring = ImageChops.subtract(fill, shape(kind, PAD + STROKE, max(1, BOX_RADIUS - STROKE)))
    cells += [fill, ring]
atlas = Image.new("RGBA", (CELL * 4, CELL), (255, 255, 255, 0))
for i, m in enumerate(cells):
    cell = Image.new("RGBA", (CELL, CELL), (255, 255, 255, 0))
    cell.putalpha(m.resize((CELL, CELL), Image.LANCZOS))
    atlas.paste(cell, (i * CELL, 0))
atlas.save(os.path.join(out, "controls.tga"))
print("ok")
