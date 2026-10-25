"""Vidéo de présentation de Mandarine (1920x1080, 30 i/s, sans son).
Les roues sont dessinées par l'app elle-même (--render) : la vidéo ne redessine que le décor.
Usage: /usr/bin/python3 make_video.py <dossier-travail> <sortie.mp4> <ffmpeg> <Mandarine.app>
       ... --sheet               planche-contact (contrôle visuel)
       ... --poster <t> <jpg>    image fixe à l'instant t
"""
import os, sys, math, subprocess
from functools import lru_cache
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

WORK, OUT, FFMPEG, APP = sys.argv[1:5]
EXE = f"{APP}/Contents/MacOS/Mandarine"
W, H, FPS = 1920, 1080, 30
SF = "/System/Library/Fonts/SFNS.ttf"
WHEEL_PX = 780                       # diamètre d'affichage de la fenêtre de la roue (372 pt dans l'app)
PX = WHEEL_PX / 372.0
CX, CY = 1330, 540                   # centre de la roue
ACCENT = (255, 159, 10)
os.makedirs(WORK, exist_ok=True)

@lru_cache(None)
def font(size, weight="Semibold"):
    f = ImageFont.truetype(SF, size)
    f.set_variation_by_name(weight)
    return f

def clamp(x): return max(0.0, min(1.0, x))
def out_cubic(t): t = clamp(t); return 1 - (1 - t) ** 3
def in_out(t): t = clamp(t); return 4 * t ** 3 if t < .5 else 1 - (-2 * t + 2) ** 3 / 2
def out_back(t, s=1.55): t = clamp(t) - 1; return t * t * ((s + 1) * t + s) + 1
def seg(t, a, d, f=out_cubic): return f((t - a) / d)
def lerp(a, b, k): return a + (b - a) * k

# ---------- ressources : roues rendues par l'app ----------
@lru_cache(None)
def items(mode, name):
    r = subprocess.run([EXE, "--list", mode, name], capture_output=True, text=True)
    return [l.split(" · ", 1) for l in r.stdout.strip().splitlines()]

@lru_cache(None)
def wheel(mode, name, hover):
    p = f"{WORK}/w-{mode}-{hover}.png"
    if not os.path.exists(p):
        env = dict(os.environ, HOVER=str(hover), SCALE="3")
        subprocess.run([EXE, "--render", mode, p, name], env=env, check=True, capture_output=True)
    return Image.open(p).convert("RGBA").resize((WHEEL_PX, WHEEL_PX), Image.LANCZOS)

def slice_index(n, dx, dy_up):
    r = math.hypot(dx, dy_up)
    if n == 0 or r < 56 or r > 172: return -1
    a = (math.pi / 2 - math.atan2(dy_up, dx)) % (2 * math.pi)
    return min(int(a / (2 * math.pi / n)), n - 1)

def slice_center(n, i):
    a = math.radians((i + .5) * 360 / n); r = 107 * PX
    return CX + r * math.sin(a), CY - r * math.cos(a)

def hover_at(n, x, y): return slice_index(n, (x - CX) / PX, -(y - CY) / PX)

@lru_cache(None)
def icon(px):
    if not os.path.exists(f"{WORK}/icon.png"):
        subprocess.run([EXE, "--icon", f"{WORK}/icon.png", "1024", "tile"], check=True)
    return Image.open(f"{WORK}/icon.png").convert("RGBA").resize((px, px), Image.LANCZOS)

_wall = None
def wallpaper():
    global _wall
    if _wall is None:
        base = Image.new("RGB", (W, H), (9, 9, 15))
        layer = Image.new("RGB", (W, H), (0, 0, 0)); d = ImageDraw.Draw(layer)
        d.ellipse((1250, -260, 2450, 760), fill=(255, 112, 18)); d.ellipse((-420, 520, 640, 1380), fill=(78, 44, 214))
        d.ellipse((560, 760, 1500, 1400), fill=(240, 56, 110)); d.ellipse((900, -400, 1500, 200), fill=(40, 90, 230))
        layer = layer.filter(ImageFilter.GaussianBlur(210))
        _wall = ImageChops.add(base, layer.point(lambda v: int(v * .42)))
    return _wall.copy().convert("RGBA")

@lru_cache(None)
def glow_sprite():
    s = Image.new("RGBA", (1100, 1100), (0, 0, 0, 0))
    ImageDraw.Draw(s).ellipse((190, 190, 910, 910), fill=ACCENT + (255,))
    return s.filter(ImageFilter.GaussianBlur(120))

# ---------- éléments dessinés ----------
def paste(img, src, cx, cy, scale=1.0, alpha=1.0):
    if alpha <= 0 or scale <= 0: return
    s = src if scale == 1 else src.resize((max(1, int(src.width * scale)), max(1, int(src.height * scale))), Image.LANCZOS)
    if alpha < 1:
        s = s.copy(); s.putalpha(s.getchannel("A").point(lambda v: int(v * alpha)))
    img.alpha_composite(s, (int(cx - s.width / 2), int(cy - s.height / 2)))

def text(img, xy, s, f, fill=(255, 255, 255), alpha=1.0, anchor="la"):
    if alpha <= 0: return
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).text(xy, s, font=f, fill=tuple(fill) + (int(255 * alpha),), anchor=anchor)
    img.alpha_composite(layer)

def shadowed(sprite, blur=26, dy=18, opacity=.5):
    pad = blur * 3
    out = Image.new("RGBA", (sprite.width + pad * 2, sprite.height + pad * 2), (0, 0, 0, 0))
    sh = Image.new("RGBA", out.size, (0, 0, 0, 0)); sh.paste((0, 0, 0, int(255 * opacity)), (pad, pad + dy), sprite.getchannel("A"))
    out.alpha_composite(sh.filter(ImageFilter.GaussianBlur(blur))); out.alpha_composite(sprite, (pad, pad))
    return out

@lru_cache(None)
def file_card(label):
    S = 176; c = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    g = Image.new("RGBA", (S, S))
    for y in range(S):
        t = y / S; g.paste((255, int(lerp(176, 84, t)), int(lerp(86, 60, t)), 255), (0, y, S, y + 1))
    m = Image.new("L", (S, S), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, S - 1, S - 1), 30, fill=255)
    d = ImageDraw.Draw(g)
    d.ellipse((112, 30, 150, 68), fill=(255, 240, 200, 255))
    d.polygon([(0, 150), (52, 84), (92, 128), (122, 98), (S, 140), (S, S), (0, S)], fill=(60, 36, 90, 235))
    c.paste(g, (0, 0), m)
    f = font(30, "Semibold"); tw = int(f.getlength(label)) + 34
    out = Image.new("RGBA", (max(S, tw), S + 52), (0, 0, 0, 0))
    out.alpha_composite(c, ((out.width - S) // 2, 0))
    ImageDraw.Draw(out).rounded_rectangle(((out.width - tw) // 2, S + 12, (out.width + tw) // 2, S + 50), 19, fill=(10, 96, 255, 255))
    ImageDraw.Draw(out).text((out.width // 2, S + 31), label, font=f, fill=(255, 255, 255, 255), anchor="mm")
    return shadowed(out, 20, 14, .45)

@lru_cache(None)
def keycap(glyph, label, pressed, size):
    k = Image.new("RGBA", (size + 12, size + 24), (0, 0, 0, 0)); d = ImageDraw.Draw(k)
    off = int(8 * pressed)
    d.rounded_rectangle((6, 14, size + 6, size + 14), 26, fill=(112, 108, 102, 255))
    top = (int(lerp(238, 255, pressed)), int(lerp(234, 190, pressed)), int(lerp(226, 90, pressed)))
    d.rounded_rectangle((6, 6 + off, size + 6, size + 6 + off - 8 + 8), 26, fill=top + (255,))
    d.text((size // 2 + 6, size // 2 - 2 + off), glyph, font=font(int(size * .5), "Medium"), fill=(40, 36, 32, 255), anchor="mm")
    if label: d.text((22, size - 12 + off), label, font=font(int(size * .15), "Semibold"), fill=(90, 84, 78, 255), anchor="lm")
    return shadowed(k, 22, 16, .42)

@lru_cache(None)
def toast_sprite(label):
    f = font(40, "Semibold"); tw = int(f.getlength(label)); w = tw + 96; h = 84
    s = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(s)
    d.rounded_rectangle((0, 0, w - 1, h - 1), h // 2, fill=(28, 28, 32, 235), outline=(255, 255, 255, 38), width=2)
    d.ellipse((24, 22, 64, 62), fill=ACCENT + (255,)); d.line([(35, 43), (42, 50), (54, 34)], fill=(20, 20, 20, 255), width=5, joint="curve")
    d.text((80, h // 2 + 1), label, font=f, fill=(255, 255, 255, 255), anchor="lm")
    return shadowed(s, 22, 14, .5)

def toast(img, cx, cy, label, p):
    if p > 0: paste(img, toast_sprite(label), cx, cy + (1 - p) * 40, 0.94 + .06 * p, clamp(p))

@lru_cache(None)
def shelf_sprite():
    s = Image.new("RGBA", (300, 250), (0, 0, 0, 0)); d = ImageDraw.Draw(s)
    d.rounded_rectangle((0, 0, 299, 249), 44, fill=(32, 32, 36, 235), outline=(255, 255, 255, 40), width=2)
    card = file_card("photo.png"); card = card.crop((card.width // 2 - 120, 40, card.width // 2 + 120, 40 + 250))
    s.alpha_composite(card.resize((168, 175)), (66, 24))
    return shadowed(s, 24, 16, .5)

def path_pos(pts, t):
    if t <= pts[0][0]: return pts[0][1], pts[0][2]
    for (t0, x0, y0), (t1, x1, y1) in zip(pts, pts[1:]):
        if t <= t1:
            k = in_out((t - t0) / (t1 - t0)); return lerp(x0, x1, k), lerp(y0, y1, k)
    return pts[-1][1], pts[-1][2]

def left_column(img, lt, glyph, label, title, held):
    p = seg(lt, 0.0, .6)
    if p <= 0: return
    pressed = 1.0 if held[0] <= lt < held[1] else 0.0
    paste(img, keycap(glyph, label, pressed, 150), 335, 400 + (1 - p) * 30, 1, p)
    text(img, (250, 610 + (1 - p) * 24), title, font(112, "Bold"), (255, 255, 255), p)

# ---------- scènes ----------
def scene_intro(img, lt):
    a = seg(lt, 0.1, .7, out_back); fade = 1 - seg(lt, 1.15, .4)
    paste(img, shadowed(icon(300), 40, 26, .5), W / 2, H / 2 - 30, .8 + .2 * a, clamp(a) * fade)
    for i, (w, col) in enumerate((("Glisse.", (255, 255, 255)), ("Tape.", (255, 255, 255)), ("Dépose.", ACCENT))):
        p = seg(lt, 1.45 + i * .5, .55)
        text(img, (W / 2, 330 + i * 190 + (1 - p) * 34), w, font(176, "Bold"), col, p * (1 - seg(lt, 3.35, .35)), "ma")

def scene_wheel(img, lt, cfg):
    mode, name = cfg["mode"], cfg["name"]
    its = items(mode, name); n = len(its)
    held, drop, target = cfg["held"], cfg["drop"], cfg["target"]
    left_column(img, lt, cfg["glyph"], cfg["key"], cfg["title"], held)
    bloom = seg(lt, held[0] + .05, .4, out_back); gone = seg(lt, drop + .1, .35)
    cx, cy = path_pos(cfg["path"], lt)
    if lt >= drop:
        tx, ty = slice_center(n, target); k = seg(lt, drop, .3); cx, cy = lerp(cx, tx, k), lerp(cy, ty, k)
    hv = target if lt >= drop else hover_at(n, cx, cy)
    if bloom > 0:
        pulse = 1 + .035 * math.sin(clamp((lt - drop) / .25) * math.pi) if lt >= drop else 1
        g = glow_sprite(); a = clamp(.30 * bloom * (1 - gone))
        paste(img, g, CX, CY, 1, a)
        paste(img, wheel(mode, name, hv), CX, CY, (.86 + .14 * bloom) * pulse, clamp(bloom) * (1 - gone))
    shrink = 1 - seg(lt, drop, .3) if lt >= drop else 1
    if lt < drop + .3:
        enter = seg(lt, 0.15, .5)
        paste(img, file_card("photo.png"), cx, cy + (1 - enter) * 60, (1.0 if bloom < .05 else lerp(1.0, .72, clamp(bloom))) * shrink, enter * shrink)
    toast(img, CX, 960, cfg["toast"], seg(lt, drop + .35, .45, out_back))
    if cfg.get("shelf") and lt > drop + .3:
        p = seg(lt, drop + .35, .5)
        paste(img, shelf_sprite(), W - 210 + (1 - p) * 360, 470, 1, p)

def scene_capture(img, lt):
    p = seg(lt, 0.0, .6)
    if p > 0:
        pressed = 1.0 if 0.7 <= lt < 3.4 else 0.0
        for i, (g, lab) in enumerate((("⌃", "control"), ("⇧", "shift"), ("4", ""))):
            paste(img, keycap(g, lab, pressed, 118), 300 + i * 142, 400 + (1 - p) * 30, 1, p)
        text(img, (250, 610 + (1 - p) * 24), "Capturer", font(112, "Bold"), (255, 255, 255), p)
    box = (900, 250, 1800, 800)
    a = seg(lt, .2, .5)
    if a > 0:
        scr = Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), (0, 0, 0, 0)); d = ImageDraw.Draw(scr)
        d.rounded_rectangle((0, 0, scr.width - 1, scr.height - 1), 34, fill=(22, 22, 28, 255))
        for i in range(5): d.rounded_rectangle((44 + i * 168, 44, 44 + i * 168 + 140, 70), 10, fill=(60, 60, 72, 255))
        d.rounded_rectangle((44, 120, 520, 470), 20, fill=(240, 120, 40, 255)); d.rounded_rectangle((560, 120, 856, 290), 20, fill=(90, 80, 220, 255))
        d.rounded_rectangle((560, 310, 856, 470), 20, fill=(235, 70, 120, 255))
        paste(img, shadowed(scr, 30, 20, .5), (box[0] + box[2]) / 2, (box[1] + box[3]) / 2, 1, a)
        sel = seg(lt, 1.1, 1.3, in_out)
        if sel > 0 and lt < 3.15:
            x0, y0 = box[0] + 60, box[1] + 100; x1, y1 = lerp(x0, box[0] + 480, sel), lerp(y0, box[1] + 330, sel)
            lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); dd = ImageDraw.Draw(lay)
            dd.rectangle((x0, y0, x1, y1), fill=(255, 255, 255, 36), outline=(255, 255, 255, 235), width=3)
            dd.text((x1 + 14, y1 + 16), f"{int(x1 - x0)} × {int(y1 - y0)}", font=font(26, "Semibold"), fill=(255, 255, 255, 235))
            img.alpha_composite(lay)
        fl = seg(lt, 3.0, .12) * (1 - seg(lt, 3.14, .3))
        if fl > 0: img.alpha_composite(Image.new("RGBA", (W, H), (255, 255, 255, int(120 * fl))))
    toast(img, 1350, 960, "Capture copiée", seg(lt, 3.35, .45, out_back))

def scene_outro(img, lt):
    a = seg(lt, 0.1, .7, out_back)
    paste(img, shadowed(icon(380), 46, 30, .55), W / 2, 400, .86 + .14 * a, clamp(a))
    text(img, (W / 2, 720 + (1 - seg(lt, .5, .6)) * 24), "Mandarine", font(168, "Bold"), (255, 255, 255), seg(lt, .5, .6), "ma")

SCENES = [
    ("intro", 3.8, None),
    ("wheel", 5.2, dict(mode="convert", name="photo.png", glyph="⇧", key="shift", title="Convertir", held=(0.7, 3.9), drop=3.55, target=0, toast="photo.jpg",
                        path=[(0, 780, 930), (.7, 900, 800), (1.4, 1180, 640), (2.0, 1500, 470), (2.6, 1470, 330), (3.2, 1400, 335)])),
    ("wheel", 5.2, dict(mode="tools", name="photo.png", glyph="⌘", key="command", title="Outils", held=(0.7, 3.9), drop=3.55, target=0, toast="photo-compressé.png",
                        path=[(0, 780, 930), (.7, 900, 800), (1.5, 1230, 770), (2.2, 1180, 500), (2.9, 1262, 330), (3.2, 1400, 340)])),
    ("wheel", 5.2, dict(mode="actions", name="photo.png", glyph="⌃", key="control", title="Actions", held=(0.7, 3.9), drop=3.55, target=1, toast="Flotter", shelf=True,
                        path=[(0, 780, 930), (.7, 900, 800), (1.5, 1200, 700), (2.2, 1560, 640), (2.9, 1590, 520), (3.2, 1550, 540)])),
    ("capture", 4.6, None),
    ("outro", 3.2, None),
]
BOUNDS = []; _t = 0.0
for _n, _d, _c in SCENES: BOUNDS.append((_t, _t + _d)); _t += _d
DUR = _t

def frame(t):
    img = wallpaper()
    s = next(i for i, (a, b) in enumerate(BOUNDS) if a <= t < b or i == len(BOUNDS) - 1)
    a, b = BOUNDS[s]; lt = t - a; name, dur, cfg = SCENES[s]
    if name == "intro": scene_intro(img, lt)
    elif name == "wheel": scene_wheel(img, lt, cfg)
    elif name == "capture": scene_capture(img, lt)
    else: scene_outro(img, lt)
    if lt < .22 and s > 0:
        img.alpha_composite(Image.new("RGBA", (W, H), (0, 0, 0, int(255 * (1 - lt / .22) * .65))))
    if s < len(SCENES) - 1 and b - t < .22:
        img.alpha_composite(Image.new("RGBA", (W, H), (0, 0, 0, int(255 * (1 - (b - t) / .22) * .65))))
    return img.convert("RGB")

if __name__ == "__main__":
    if "--sheet" in sys.argv:
        pts = [.9, 2.7, 5.0, 6.6, 7.6, 8.9, 11.4, 12.2, 14.6, 16.6, 19.2, 21.0, 23.6, 25.6, 26.8, 28.4]
        pts = [p for p in pts if p < DUR]
        cols = 4; tw, th = 480, 270; rows = (len(pts) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * tw, rows * th))
        for i, t in enumerate(pts): sheet.paste(frame(t).resize((tw, th)), ((i % cols) * tw, (i // cols) * th))
        sheet.save(f"{WORK}/sheet.png"); print("durée", DUR); sys.exit()
    if "--poster" in sys.argv:
        i = sys.argv.index("--poster"); frame(float(sys.argv[i + 1])).save(sys.argv[i + 2], quality=90); sys.exit()
    n = int(DUR * FPS)
    p = subprocess.Popen([FFMPEG, "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
                          "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", "-preset", "slow", "-movflags", "+faststart", OUT], stdin=subprocess.PIPE)
    for i in range(n): p.stdin.write(frame(i / FPS).tobytes())
    p.stdin.close(); p.wait(); print("images", n, "->", OUT, "durée", round(DUR, 1), "s")
