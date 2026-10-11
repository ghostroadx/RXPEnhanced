# Draws the guide card from a layout dump written by test/test_card.lua, so the layout can be
# checked (and shown) without the game. python3 -I render_card.py <media dir> <out.png> dump1.json [dump2.json ...]
import json, re, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

args = sys.argv[1:]
bg_path = None
if "--bg" in args:
    i = args.index("--bg")
    bg_path = args[i + 1]
    del args[i:i + 2]
media, out_path, dumps = args[0], args[1], args[2:]
S = 2  # render scale
FONTS = {"regular": "Inter-Regular.ttf", "medium": "Inter-Medium.ttf", "semibold": "Inter-SemiBold.ttf"}
atlas = Image.open(media + "/icons.tga").convert("RGBA")
_font_cache = {}


def font(weight, size):
    key = (weight, size)
    if key not in _font_cache:
        _font_cache[key] = ImageFont.truetype(media + "/" + FONTS.get(weight, FONTS["regular"]), round(size * S))
    return _font_cache[key]


def rgba(c, alpha_mul=1.0):
    r, g, b = c[0], c[1], c[2]
    a = c[3] if len(c) > 3 else 1
    return (round(r * 255), round(g * 255), round(b * 255), round(a * alpha_mul * 255))


def background(w, h):
    if bg_path:
        # A crop of a real game screenshot (the forest, away from any UI), scaled to cover.
        src = Image.open(bg_path).convert("RGB").crop((420, 0, 1023, 425))
        scale = max(w / src.width, h / src.height)
        src = src.resize((round(src.width * scale), round(src.height * scale)), Image.LANCZOS)
        return src.crop((0, 0, w, h)).convert("RGBA")
    return synthetic_background(w, h)


def synthetic_background(w, h):
    # Something like a dim, out-of-focus game world behind the card.
    bg = Image.new("RGB", (w, h))
    px = bg.load()
    for y in range(h):
        t = y / max(1, h - 1)
        for x in range(w):
            u = x / max(1, w - 1)
            r = int(52 + 30 * u - 20 * t)
            g = int(66 + 18 * (1 - u) - 18 * t)
            b = int(54 + 10 * t)
            px[x, y] = (r, g, b)
    d = ImageDraw.Draw(bg)
    for i, (cx, cy, rad, col) in enumerate([(0.2, 0.3, 0.35, (90, 110, 80)), (0.85, 0.8, 0.4, (70, 60, 50)), (0.6, 0.1, 0.25, (110, 120, 130))]):
        d.ellipse(((cx - rad) * w, (cy - rad) * h, (cx + rad) * w, (cy + rad) * h), fill=col)
    return bg.filter(ImageFilter.GaussianBlur(60)).convert("RGBA")


CODE = re.compile(r"\|c([0-9a-fA-F]{8})|\|r|\|T.*?\|t")


def draw_text(layer, op, ox, oy):
    d = ImageDraw.Draw(layer)
    f = font(op["weight"], op["size"])
    base = rgba(op["color"])
    color = base
    lh = op["lineHeight"] * S
    shadow = op.get("shadow")
    def put(x, y, seg, col):
        if shadow:
            d.text((x + S, y + S), seg, font=f, fill=(0, 0, 0, 178), anchor="la")
        d.text((x, y), seg, font=f, fill=col, anchor="la")
    for i, line in enumerate(op["lines"]):
        x = (ox + op["x"]) * S
        if op.get("justify") == "RIGHT":
            plain = CODE.sub("", line)
            x += op["w"] * S - d.textlength(plain, font=f)
        y = (oy + op["y"]) * S + i * lh
        pos = 0
        for m in CODE.finditer(line):
            seg = line[pos:m.start()]
            if seg:
                put(x, y, seg, color)
                x += d.textlength(seg, font=f)
            tok = m.group(0)
            if tok.startswith("|c"):
                h = m.group(1)
                color = (int(h[2:4], 16), int(h[4:6], 16), int(h[6:8], 16), 255)
            elif tok == "|r":
                color = base
            else:
                x += d.textlength("  ", font=f)
            pos = m.end()
        seg = line[pos:]
        if seg:
            put(x, y, seg, color)


_textures = {}


def texture_for(file):
    # Any of the addon's own textures (Media\<name>); others (RestedXP's arrow) aren't drawn.
    name = re.split(r"[\\/]", file)[-1]
    if name not in _textures:
        try:
            _textures[name] = Image.open(media + "/" + name + ".tga").convert("RGBA")
        except OSError:
            _textures[name] = None
    return _textures[name]


def draw_icon(layer, op, ox, oy):
    c = op.get("coords") or [0, 1, 0, 1]
    atlas = texture_for(op["file"])
    if atlas is None:
        return
    W, H = atlas.size
    box = (round(c[0] * W), round(c[2] * H), round(c[1] * W), round(c[3] * H))
    icon = atlas.crop(box).resize((max(1, round(op["w"] * S)), max(1, round(op["h"] * S))), Image.LANCZOS)
    col = rgba(op["color"])
    tinted = Image.new("RGBA", icon.size, col[:3] + (0,))
    alpha = icon.getchannel("A").point(lambda a: a * col[3] // 255)
    tinted.putalpha(alpha)
    pos = (round((ox + op["x"]) * S), round((oy + op["y"]) * S))
    if op.get("rotation"):
        # WoW turns textures counter-clockwise, as PIL does; keep the centre where it was.
        import math
        w0, h0 = tinted.size
        tinted = tinted.rotate(math.degrees(op["rotation"]), resample=Image.BICUBIC, expand=True)
        pos = (pos[0] - (tinted.width - w0) // 2, pos[1] - (tinted.height - h0) // 2)
    layer.alpha_composite(tinted, pos)


def render(dump, margin=28):
    w, h = dump["w"], dump["h"]
    img = background(round((w + margin * 2) * S), round((h + margin * 2) * S))
    for op in dump["ops"]:
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        x0, y0 = (margin + op["x"]) * S, (margin + op["y"]) * S
        x1, y1 = x0 + op.get("w", 0) * S, y0 + op.get("h", 0) * S
        t = op["type"]
        if t == "rect" and "toastshadow" in op.get("file", ""):
            # The soft-shadow nine-slice (tools/make_ui_assets.py): edge 20/32 of a corner in,
            # corner radius 12/32, blur sigma 4.5/32.
            c = op["corner"] * S
            inset = c * 20 / 32
            mask = Image.new("L", img.size, 0)
            ImageDraw.Draw(mask).rounded_rectangle((x0 + inset, y0 + inset, x1 - inset - 1, y1 - inset - 1),
                                                   radius=c * 12 / 32, fill=255)
            mask = mask.filter(ImageFilter.GaussianBlur(c * 4.5 / 32))
            col = rgba(op["color"])
            shade = Image.new("RGBA", img.size, col[:3] + (0,))
            shade.putalpha(mask.point(lambda v: round(v * col[3] / 255)))
            layer = shade
        elif t == "rect" and op.get("top"):
            # A vertical gradient inside the rounded shape.
            mask = Image.new("L", img.size, 0)
            ImageDraw.Draw(mask).rounded_rectangle((x0, y0, x1 - 1, y1 - 1), radius=op["corner"] * S, fill=255)
            grad = Image.new("RGBA", img.size, (0, 0, 0, 0))
            gd = ImageDraw.Draw(grad)
            top, bot = rgba(op["top"]), rgba(op["bottom"])
            span = max(1, int(y1 - y0))
            for k in range(span):
                u = k / span
                gd.line((x0, y0 + k, x1, y0 + k), fill=tuple(round(top[j] + (bot[j] - top[j]) * u) for j in range(4)))
            layer.paste(grad, (0, 0), mask)
        elif t == "rect":
            d.rounded_rectangle((x0, y0, x1 - 1, y1 - 1), radius=op["corner"] * S, fill=rgba(op["color"]))
        elif t == "ring":
            d.rounded_rectangle((x0, y0, x1 - 1, y1 - 1), radius=op["corner"] * S, outline=rgba(op["color"]), width=S)
        elif t == "fill":
            if x1 - x0 >= 1 and y1 - y0 >= 1:
                d.rectangle((x0, y0, x1 - 1, y1 - 1), fill=rgba(op["color"]))
        elif t == "tex":
            draw_icon(layer, op, margin, margin)
        elif t == "text":
            draw_text(layer, op, margin, margin)
        img.alpha_composite(layer)
    return img


images = [render(json.load(open(p))) for p in dumps]
gap = 0
W = sum(i.width for i in images) + gap * (len(images) - 1)
H = max(i.height for i in images)
sheet = Image.new("RGBA", (W, H), (30, 34, 32, 255))
x = 0
for i in images:
    sheet.alpha_composite(i, (x, 0))
    x += i.width + gap
sheet.convert("RGB").save(out_path)
print(out_path, sheet.size)
