"""
Store art for "Fight Entities to Escape The Backrooms".

Drawn rather than screenshotted: the game is untextured blocks right now, and
store art has to read at ~150px wide in a search result. Built as a true
one-point perspective corridor so it has real depth, using the level's own
palette so it doesn't misrepresent the game.
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops
import os

OUT = "/Users/ash.whiting/sites/arlo-backrooms-game/assets/branding"
FONTS = "/System/Library/Fonts/Supplemental"

WALL_L = (150, 127, 66)   # left wall
WALL_R = (128, 108, 56)   # right wall, a little darker for form
CEIL   = (146, 124, 65)
FLOOR  = (96,  80,  43)
BACK   = (58,  49,  27)   # far end, swallowed by gloom
TUBE   = (248, 244, 214)
TUBE_D = (74,  71,  63)
INK    = (14,  13,  12)
EYE    = (255, 66, 50)
CREAM  = (243, 230, 163)

def font(name, size):
    for c in (name, "Arial Bold.ttf", "Helvetica.ttc"):
        p = os.path.join(FONTS, c)
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                pass
    return ImageFont.load_default()

def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))

def corridor(w, h, vp=(0.5, 0.5), back=0.13):
    """One-point perspective: ceiling, floor, two walls, far wall."""
    img = Image.new("RGB", (w, h), BACK)
    d = ImageDraw.Draw(img)
    vx, vy = vp[0] * w, vp[1] * h
    bw, bh = w * back, h * back
    l, r = vx - bw / 2, vx + bw / 2
    t, b = vy - bh / 2, vy + bh / 2

    # Walls, floor and ceiling as trapezoids, shaded in bands so they fall off
    # toward the vanishing point rather than being flat colour.
    BANDS = 26
    for i in range(BANDS):
        f0, f1 = i / BANDS, (i + 1) / BANDS          # 0 = near, 1 = far
        sh = 1.0 - f1 * 0.88                          # near lit, far dark

        def edge(f, corner, target):
            return (corner[0] + (target[0] - corner[0]) * f,
                    corner[1] + (target[1] - corner[1]) * f)

        # ceiling
        d.polygon([edge(f0, (0, 0), (l, t)), edge(f0, (w, 0), (r, t)),
                   edge(f1, (w, 0), (r, t)), edge(f1, (0, 0), (l, t))],
                  fill=mix(BACK, CEIL, sh))
        # floor
        d.polygon([edge(f0, (0, h), (l, b)), edge(f0, (w, h), (r, b)),
                   edge(f1, (w, h), (r, b)), edge(f1, (0, h), (l, b))],
                  fill=mix(BACK, FLOOR, sh))
        # left wall
        d.polygon([edge(f0, (0, 0), (l, t)), edge(f0, (0, h), (l, b)),
                   edge(f1, (0, h), (l, b)), edge(f1, (0, 0), (l, t))],
                  fill=mix(BACK, WALL_L, sh))
        # right wall
        d.polygon([edge(f0, (w, 0), (r, t)), edge(f0, (w, h), (r, b)),
                   edge(f1, (w, h), (r, b)), edge(f1, (w, 0), (r, t))],
                  fill=mix(BACK, WALL_R, sh))

    d.rectangle([l, t, r, b], fill=BACK)

    # A side opening on each wall, so it reads as rooms rather than a tube.
    for side, f0, f1 in ((0, 0.30, 0.46), (1, 0.52, 0.68)):
        def wedge(f, corner, target):
            return (corner[0] + (target[0] - corner[0]) * f,
                    corner[1] + (target[1] - corner[1]) * f)
        cx0, cy0 = (0, 0) if side == 0 else (w, 0)
        cx1, cy1 = (0, h) if side == 0 else (w, h)
        tx, ty = (l, t) if side == 0 else (r, t)
        bx, by = (l, b) if side == 0 else (r, b)
        d.polygon([wedge(f0, (cx0, cy0), (tx, ty)), wedge(f1, (cx0, cy0), (tx, ty)),
                   wedge(f1, (cx1, cy1), (bx, by)), wedge(f0, (cx1, cy1), (bx, by))],
                  fill=mix(BACK, (86, 72, 39), 0.55))

    # Ceiling tubes receding toward the vanishing point.
    tubes = []
    for i in range(7):
        f = 0.06 + i * 0.135
        cx = w * 0.5 + (vx - w * 0.5) * f
        cy = (0 + (t - 0) * f) + h * 0.035 * (1 - f)
        half_w = (w * 0.115) * (1 - f) + bw * 0.14 * f
        half_h = max(2.0, (h * 0.014) * (1 - f) + 2 * f)
        dead = (i == 2 or i == 5)
        d.rectangle([cx - half_w, cy - half_h, cx + half_w, cy + half_h],
                    fill=TUBE_D if dead else mix(CEIL, TUBE, 0.55 + 0.45 * (1 - f)))
        if not dead:
            tubes.append((cx, cy, half_w, half_h, 1 - f))
    return img, tubes

def bloom(img, tubes):
    """Additive glow so the tubes read as light sources."""
    layer = Image.new("RGB", img.size, (0, 0, 0))
    ld = ImageDraw.Draw(layer)
    for cx, cy, hw, hh, near in tubes:
        k = 0.55 + 0.45 * near
        ld.ellipse([cx - hw * 2.6, cy - hh * 9, cx + hw * 2.6, cy + hh * 11],
                   fill=(int(96 * k), int(90 * k), int(66 * k)))
    layer = layer.filter(ImageFilter.GaussianBlur(min(img.size) * 0.035))
    return ImageChops.add(img, layer)

def entity(d, cx, foot, height, pale=True):
    """Tall, thin, faceless. Proportions match the in-game Slender variant."""
    head_h = height * 0.135
    torso_h = height * 0.38
    leg_h = height * 0.485
    body_w = height * 0.150
    limb_w = body_w * 0.30

    hip = foot - leg_h
    # legs
    d.rectangle([cx - body_w*0.34, hip, cx - body_w*0.34 + limb_w, foot], fill=INK)
    d.rectangle([cx + body_w*0.34 - limb_w, hip, cx + body_w*0.34, foot], fill=INK)
    # torso
    d.rectangle([cx - body_w/2, hip - torso_h, cx + body_w/2, hip], fill=INK)
    # arms hanging well past the hip
    arm_len = torso_h + leg_h * 0.20
    gap = limb_w * 0.55
    d.rectangle([cx - body_w/2 - gap - limb_w, hip - torso_h*0.92,
                 cx - body_w/2 - gap, hip - torso_h*0.92 + arm_len], fill=INK)
    d.rectangle([cx + body_w/2 + gap, hip - torso_h*0.92,
                 cx + body_w/2 + gap + limb_w, hip - torso_h*0.92 + arm_len], fill=INK)
    # head
    top = hip - torso_h
    hw = body_w * 0.40
    d.rectangle([cx - hw, top - head_h, cx + hw, top],
                fill=(240, 238, 231) if pale else INK)
    if pale:
        ew, eh = hw * 0.34, head_h * 0.20
        ey = top - head_h * 0.58
        for s in (-0.48, 0.48):
            d.rectangle([cx + hw*s - ew/2, ey, cx + hw*s + ew/2, ey + eh], fill=EYE)

def vignette(img, strength=0.78):
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).ellipse([w*0.06, h*0.02, w*0.94, h*1.10], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(min(w, h) * 0.16))
    mask = mask.point(lambda v: int(255 - (255 - v) * strength))
    return Image.composite(img, Image.new("RGB", (w, h), (7, 6, 5)), mask)

def outlined(d, xy, text, fnt, fill, px=6, anchor="mm"):
    x, y = xy
    for ox in range(-px, px + 1):
        for oy in range(-px, px + 1):
            if ox*ox + oy*oy <= px*px and (ox or oy):
                d.text((x + ox, y + oy), text, font=fnt, fill=(9, 8, 7), anchor=anchor)
    d.text((x, y), text, font=fnt, fill=fill, anchor=anchor)

TITLE = ["FIGHT ENTITIES", "TO ESCAPE THE", "BACKROOMS"]

def draw_title(img, scale=1.0):
    """
    The title appears on every piece of store art, so it is one function.

    Anchored to the BOTTOM: the entity is the thing worth looking at, and a
    title block across the middle was covering it. A dark band behind the text
    keeps it legible over a lit corridor without hiding the scene.
    """
    w, h = img.size
    one_line = "FIGHT TO ESCAPE THE BACKROOMS"
    fnt = font("Impact.ttf", int(h * 0.105 * scale))

    d = ImageDraw.Draw(img)
    # Shrink to fit rather than wrapping: one line reads better in a search result.
    while d.textlength(one_line, font=fnt) > w * 0.92 and fnt.size > 12:
        fnt = font("Impact.ttf", fnt.size - 2)

    band_h = int(h * 0.175 * scale)
    band = Image.new("RGB", (w, band_h), (9, 8, 7))
    img.paste(Image.blend(img.crop((0, h - band_h, w, h)), band, 0.62), (0, h - band_h))

    d = ImageDraw.Draw(img)
    outlined(d, (w * 0.5, h - band_h * 0.52), one_line, fnt, CREAM,
             px=max(3, int(h * 0.005)))
    return img

def hero(w=1920, h=1080):
    img, tubes = corridor(w, h, vp=(0.5, 0.52))
    img = bloom(img, tubes)
    d = ImageDraw.Draw(img)
    entity(d, w*0.775, h*0.880, h*0.60)          # near, right of the title block
    entity(d, w*0.315, h*0.690, h*0.26)          # further down the corridor
    img = vignette(img, 0.80)
    img = draw_title(img, scale=1.0)
    d = ImageDraw.Draw(img)
    outlined(d, (w*0.5, h*0.075), "LEVEL 0  ·  NO WAY OUT",
             font("Arial Bold.ttf", int(h*0.048)), (222, 208, 156), px=4)
    return img

def entities_shot(w=1920, h=1080):
    img, tubes = corridor(w, h, vp=(0.40, 0.50))
    img = bloom(img, tubes)
    d = ImageDraw.Draw(img)
    entity(d, w*0.700, h*0.870, h*0.62)
    entity(d, w*0.895, h*0.800, h*0.42)
    entity(d, w*0.515, h*0.695, h*0.26)
    img = vignette(img, 0.82)
    img = draw_title(img, scale=0.78)
    d = ImageDraw.Draw(img)
    outlined(d, (w*0.5, h*0.085), "THEY HUNT IN PACKS",
             font("Impact.ttf", int(h*0.070)), (238, 92, 74), px=5)
    return img

def arsenal_shot(w=1920, h=1080):
    img, tubes = corridor(w, h, vp=(0.60, 0.54))
    img = bloom(img, tubes)
    d = ImageDraw.Draw(img)
    entity(d, w*0.220, h*0.855, h*0.54)
    # blocky first-person weapon in the near corner
    d.polygon([(w*0.62, h*1.03), (w*0.735, h*0.63), (w*0.90, h*0.675), (w*0.83, h*1.03)],
              fill=(40, 40, 45))
    d.polygon([(w*0.722, h*0.638), (w*0.752, h*0.560), (w*0.815, h*0.582), (w*0.792, h*0.660)],
              fill=(25, 25, 29))
    img = vignette(img, 0.80)
    img = draw_title(img, scale=0.78)
    d = ImageDraw.Draw(img)
    outlined(d, (w*0.5, h*0.085), "PISTOL · MACHINE GUN · SNIPER",
             font("Impact.ttf", int(h*0.058)), CREAM, px=5)
    return img

def icon(size=512):
    img, tubes = corridor(size, size, vp=(0.5, 0.47), back=0.16)
    img = bloom(img, tubes)
    d = ImageDraw.Draw(img)
    entity(d, size*0.5, size*0.585, size*0.44)
    img = vignette(img, 0.86)
    d = ImageDraw.Draw(img)
    # Full title, stacked so it stays readable at icon size.
    band_h = int(size * 0.42)
    band = Image.new("RGB", (size, band_h), (9, 8, 7))
    img.paste(Image.blend(img.crop((0, size - band_h, size, size)), band, 0.60),
              (0, size - band_h))
    d = ImageDraw.Draw(img)
    big = font("Impact.ttf", int(size*0.125))
    small = font("Impact.ttf", int(size*0.108))
    outlined(d, (size*0.5, size*0.655), "FIGHT TO", small, CREAM, px=3)
    outlined(d, (size*0.5, size*0.775), "ESCAPE THE", small, CREAM, px=3)
    outlined(d, (size*0.5, size*0.900), "BACKROOMS", big, CREAM, px=3)
    return img

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, im in [
        ("thumbnail-1-hero.png",     hero()),
        ("thumbnail-2-entities.png", entities_shot()),
        ("thumbnail-3-arsenal.png",  arsenal_shot()),
        ("icon-512.png",             icon()),
    ]:
        im.save(os.path.join(OUT, name))
        print(f"{name}  {im.size[0]}x{im.size[1]}")
