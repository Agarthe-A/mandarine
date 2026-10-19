import sys, subprocess
from PIL import Image, ImageDraw, ImageFont

WORK, OUT, FFMPEG = sys.argv[1], sys.argv[2], sys.argv[3]
W, H, FPS = 1280, 720, 30
PAPER, INK, MUTED, ORANGE = (246, 241, 231), (23, 19, 14), (107, 98, 86), (255, 140, 26)
SER = "/System/Library/Fonts/Supplemental/Georgia Bold.ttf"
MONO = "/System/Library/Fonts/SFNSMono.ttf"
SYM = "/System/Library/Fonts/SFNS.ttf"
SANS = "/System/Library/Fonts/HelveticaNeue.ttc"
EMO = "/System/Library/Fonts/Apple Color Emoji.ttc"
f = lambda p, s: ImageFont.truetype(p, s)

wheels = [Image.open(f"{WORK}/w{i}.png").convert("RGBA") for i in (1, 2, 3)]

def ease(t):
    t = max(0.0, min(1.0, t)); return 1 - (1 - t) ** 3
def seg(t, a, d):  # progress 0..1 of an event starting at a lasting d
    return ease((t - a) / d)

def text(img, xy, s, font, fill, alpha=1.0, anchor="la"):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).text(xy, s, font=font, fill=fill + (int(255 * alpha),), anchor=anchor)
    img.alpha_composite(layer)

def paste_scaled(img, src, cx, cy, scale, alpha=1.0):
    w = max(1, int(src.width * scale)); h = max(1, int(src.height * scale))
    s = src.resize((w, h), Image.LANCZOS)
    if alpha < 1:
        a = s.getchannel("A").point(lambda v: int(v * alpha)); s.putalpha(a)
    img.alpha_composite(s, (int(cx - w / 2), int(cy - h / 2)))

def emoji(img, cx, cy, size_px=160, scale=1.0, alpha=1.0):
    tile = Image.new("RGBA", (200, 200), (0, 0, 0, 0))
    ImageDraw.Draw(tile).text((100, 100), "🍊", font=ImageFont.truetype(EMO, size_px), embedded_color=True, anchor="mm")
    paste_scaled(img, tile, cx, cy, scale, alpha)

def chip(img, x, y, label, alpha=1.0):
    fnt = f(MONO, 26); tw = int(fnt.getlength(label))
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    d.rounded_rectangle((x, y, x + tw + 44, y + 58), 14, fill=(255, 255, 255, int(255 * alpha)), outline=(214, 204, 184, int(255 * alpha)), width=2)
    d.text((x + 22, y + 29), label, font=fnt, fill=INK + (int(255 * alpha),), anchor="lm")
    img.alpha_composite(layer)

SCENES = [  # (start, end)
    (0.0, 3.4), (3.4, 7.4), (7.4, 11.0), (11.0, 14.6), (14.6, 18.0)]
DUR = SCENES[-1][1]

def scene_intro(img, t):
    for i, (word, col) in enumerate((("Glisse.", INK), ("Tape.", INK), ("Dépose.", ORANGE))):
        p = seg(t, 0.2 + i * 0.7, 0.5)
        text(img, (110, 150 + i * 150 + (1 - p) * 30), word, f(SER, 120), col, p)

def key_scene(img, t, idx, glyph, title, sub, fname, hold_label, in_chip):
    p_txt = seg(t, 0.1, 0.5)
    text(img, (110, 150 + (1 - p_txt) * 20), glyph, f(SYM, 170), ORANGE, p_txt)
    text(img, (110, 360 + (1 - p_txt) * 20), title, f(SER, 70), INK, p_txt)
    text(img, (110, 455), sub, f(SANS, 27), MUTED, seg(t, 0.4, 0.5))
    text(img, (110, 590), hold_label, f(MONO, 22), MUTED, seg(t, 0.2, 0.4))
    # file chip glides toward the wheel
    cx, cy = 985, 335
    pw = seg(t, 0.5, 0.7)
    paste_scaled(img, wheels[idx], cx, cy, 0.5 + 0.3 * pw, pw)
    gl = seg(t, 1.2, 1.0)
    if t > 0.3:
        x = 470 + gl * 430; y = 560 - gl * 255
        chip(img, x, y, fname, alpha=min(1, (t - 0.3) / 0.3) * (1 - seg(t, 2.3, 0.3)))
    # confirmation ticks
    ok = seg(t, 2.5, 0.4)
    if ok > 0:
        text(img, (cx, 650), in_chip, f(MONO, 30), ORANGE, ok, "ma")

def scene_outro(img, t):
    p = seg(t, 0.1, 0.6)
    emoji(img, W // 2, 250, scale=0.8 + 0.2 * p, alpha=p)
    text(img, (W // 2, 420), "Mandarine", f(SER, 110), INK, seg(t, 0.4, 0.5), "mm")
    text(img, (W // 2, 520), "Un fichier, une roue, c'est fait.", f(SANS, 36), MUTED, seg(t, 0.9, 0.5), "mm")
    text(img, (W // 2, 600), "Pour Mac · fait maison", f(MONO, 22), ORANGE, seg(t, 1.4, 0.5), "mm")

def frame(t):
    img = Image.new("RGBA", (W, H), PAPER + (255,))
    s = next(i for i, (a, b) in enumerate(SCENES) if a <= t < b or i == len(SCENES) - 1)
    a, b = SCENES[s]; lt = t - a
    if s == 0: scene_intro(img, lt)
    elif s == 1: key_scene(img, lt, 0, "⇧", "Convertir", "Un PNG devient JPG, WEBP, HEIC, PDF…", "photo.png", "maintiens Maj pendant le glisser", "→ JPG")
    elif s == 2: key_scene(img, lt, 1, "⌘", "Outils", "Compresser, réduire, retirer les métadonnées.", "photo.png", "maintiens Cmd pendant le glisser", "→ compressé")
    elif s == 3: key_scene(img, lt, 2, "⌃", "Actions", "Copier le chemin, AirDrop, déplacer, Terminal.", "photo.png", "maintiens Ctrl pendant le glisser", "→ AirDrop")
    else: scene_outro(img, lt)
    # fade between scenes
    edge = min(t - a, b - t) if s < len(SCENES) - 1 or True else 1
    fade = 1.0
    if t - a < 0.25 and s > 0: fade = (t - a) / 0.25
    if s == len(SCENES) - 1 and False: pass
    if fade < 1:
        bg = Image.new("RGBA", (W, H), PAPER + (255,)); img = Image.blend(bg, img, fade)
    return img.convert("RGB")

if __name__ == "__main__":
    if "--sheet" in sys.argv:
        pts = [1.0, 2.8, 4.8, 6.4, 8.8, 10.2, 12.4, 13.9, 15.6, 17.4]
        cols = 2; tw, th = 640, 360
        sheet = Image.new("RGB", (cols * tw, ((len(pts) + 1) // cols) * th))
        for i, t in enumerate(pts):
            sheet.paste(frame(t).resize((tw, th)), ((i % cols) * tw, (i // cols) * th))
        sheet.save(f"{WORK}/sheet.png"); sys.exit()
    n = int(DUR * FPS)
    p = subprocess.Popen([FFMPEG, "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
                          "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", "-movflags", "+faststart", OUT], stdin=subprocess.PIPE)
    for i in range(n):
        p.stdin.write(frame(i / FPS).tobytes())
    p.stdin.close(); p.wait()
    print("frames", n, "->", OUT)
