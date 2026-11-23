#!/usr/bin/env python3
"""App Store header (3840x1646, 8 s silent loop) and search-results picture (3840x2560)
for every language in texts.py, in the look of Roman's 1.0 screenshots (#338).

Run from the repo root:  python3 -I store/assets/make_assets.py [locale ...]
Out: store/assets/out/<locale>/header.mp4, header-poster.jpg, search.png, and
iphone-header.jpg (the part an iPhone shows, to check by eye). out/ is not in git.

Sizes and safe areas are Apple's (the playbook of our other apps:
~/Documents/independence-army-alarm/products/army-alarm/store/ASSET-PLAYBOOK.md):
- header: key art inside the safe area 1646x661 at (1097, 493); an iPhone shows
  about x 555-3285, and the store's back/share buttons float over y 400-665;
- search results: key art inside 2168x1030 at (836, 765).
"""
import math
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from texts import TEXTS  # noqa: E402

SHOTS = [os.path.join(HERE, "..", "shots-1.0", f) for f in ("1-feed.jpg", "2-chat.jpg", "3-article.jpg")]
FONTS = "/System/Library/Fonts/Supplemental"
TITLE_FONT = os.path.join(FONTS, "Georgia Bold.ttf")
TAG_FONT = os.path.join(FONTS, "Georgia.ttf")
INK = (22, 18, 20)        # near-black, the app's headlines
GARNET = (128, 20, 38)    # the tagline, a darker tone of the app's red
FPS, SECS = 30, 8

HEADER = (3840, 1646)
HEADER_SAFE = (1097, 493, 2743, 1154)
SEARCH = (3840, 2560)
SEARCH_SAFE = (836, 765, 3004, 1795)


def panorama():
    """Roman's three screenshots side by side: one picture of three phones."""
    ims = [Image.open(p).convert("RGB") for p in SHOTS]
    pano = Image.new("RGB", (sum(i.width for i in ims), ims[0].height))
    x = 0
    for im in ims:
        pano.paste(im, (x, 0))
        x += im.width
    return pano


def cover(im, size):
    """Scale to cover size, centred."""
    w, h = size
    s = max(w / im.width, h / im.height)
    r = im.resize((math.ceil(im.width * s), math.ceil(im.height * s)), Image.LANCZOS)
    left, top = (r.width - w) // 2, (r.height - h) // 2
    return r.crop((left, top, left + w, top + h))


def backdrop(size):
    """Roman's light: blush on the left, the app's red on the right, with a soft glow."""
    W, H = size
    small = Image.new("RGB", (64, 64))
    left, mid, right = (250, 230, 237), (238, 150, 170), (214, 46, 76)
    for x in range(64):
        t = x / 63
        a, b, u = (left, mid, t / 0.6) if t < 0.6 else (mid, right, (t - 0.6) / 0.4)
        col = tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3))
        for y in range(64):
            small.putpixel((x, y), col)
    glow = Image.new("L", (64, 64), 0)
    ImageDraw.Draw(glow).ellipse((36, -20, 90, 40), fill=120)
    small = Image.composite(Image.new("RGB", (64, 64), (255, 214, 224)), small, glow.filter(ImageFilter.GaussianBlur(8)))
    return small.resize(size, Image.BICUBIC).filter(ImageFilter.GaussianBlur(20))


# The three phones in Roman's panorama as four corners each (top-left, top-right,
# bottom-right, bottom-left), read off the 3618x2622 panorama by hand; back to front.
PHONES = [
    [(372, 572), (1203, 452), (1540, 2232), (905, 2300)],   # feed, left
    [(2486, 432), (3312, 598), (2918, 2276), (2060, 2175)],  # article, right
    [(1318, 452), (2252, 478), (2508, 2392), (1555, 2410)],  # chat, front
]
ICON = (190, 170, 650, 610)


def phones(pano):
    """The three phones and the app icon, cut out of the panorama on a transparent layer."""
    q = 4
    mask = Image.new("L", (pano.width // q, pano.height // q), 0)
    d = ImageDraw.Draw(mask)
    for quad in PHONES:
        d.polygon([(x / q, y / q) for x, y in quad], fill=255)
    # round the corners like an iPhone's: blur, then cut at the middle
    mask = mask.filter(ImageFilter.GaussianBlur(18)).point(lambda v: 255 if v > 128 else 0)
    ImageDraw.Draw(mask).rounded_rectangle([v / q for v in ICON], radius=110 / q, fill=255)
    mask = mask.resize(pano.size, Image.BICUBIC).filter(ImageFilter.GaussianBlur(2))
    layer = pano.convert("RGBA")
    layer.putalpha(mask)
    return layer.crop(mask.getbbox())


def with_shadow(layer, blur=40, offset=(0, 30), alpha=90):
    """A soft shadow under the phones, as in Roman's screenshots."""
    pad = blur * 3
    out = Image.new("RGBA", (layer.width + 2 * pad, layer.height + 2 * pad), (0, 0, 0, 0))
    shade = Image.new("RGBA", layer.size, (90, 10, 30, alpha))
    shade.putalpha(layer.getchannel("A").point(lambda v: v * alpha // 255))
    out.alpha_composite(shade, (pad + offset[0], pad + offset[1]))
    out = out.filter(ImageFilter.GaussianBlur(blur))
    out.alpha_composite(layer, (pad, pad))
    return out, pad


def scaled(layer, height):
    return layer.resize((int(layer.width * height / layer.height), height), Image.LANCZOS)


def fit_text(draw, text, font_path, max_w, size):
    while size > 20:
        font = ImageFont.truetype(font_path, size)
        if draw.textlength(text, font=font) <= max_w:
            return font
        size -= 4
    return ImageFont.truetype(font_path, size)


def text_block(title, tagline, width, title_size, tag_size):
    """Title and tagline, left-aligned, on a transparent layer."""
    probe = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    tf = fit_text(probe, title, TITLE_FONT, width, title_size)
    lines = wrap(probe, tagline, ImageFont.truetype(TAG_FONT, tag_size), width)
    gf = ImageFont.truetype(TAG_FONT, tag_size)
    th = tf.getbbox(title)[3]
    lh = int(tag_size * 1.25)
    h = th + int(tag_size * 0.6) + lh * len(lines) + 10
    layer = Image.new("RGBA", (width, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.text((0, 0), title, font=tf, fill=INK)
    y = th + int(tag_size * 0.6)
    for line in lines:
        d.text((0, y), line, font=gf, fill=GARNET)
        y += lh
    return layer


def wrap(draw, text, font, width):
    words, lines, cur = text.split(), [], ""
    for w in words:
        nxt = (cur + " " + w).strip()
        if draw.textlength(nxt, font=font) <= width or not cur:
            cur = nxt
        else:
            lines.append(cur)
            cur = w
    return lines + [cur]


def header_frames(cut, title, tagline):
    W, H = HEADER
    back = backdrop(HEADER).convert("RGBA")
    ph = 1080
    group, pad = with_shadow(scaled(cut, ph))
    # The phones sit right, inside what an iPhone shows (x 555-3285), low enough to clear
    # the store's floating buttons; the words sit left, inside Apple's safe area.
    gx = 3285 - (group.width - 2 * pad) - 40 - pad
    gy = H - ph - 60 - pad
    text = text_block(title, tagline, 640, 150, 62)
    tx, ty = HEADER_SAFE[0] + 10, 920 - text.height // 2
    for i in range(FPS * SECS):
        t = i / (FPS * SECS)
        im = back.copy()
        bob = int(14 * math.sin(2 * math.pi * t))   # one slow breath per loop: seamless
        im.alpha_composite(group, (gx, gy + bob))
        im.alpha_composite(text, (tx, ty))
        yield im.convert("RGB")


def search_picture(cut, title, tagline):
    W, H = SEARCH
    im = backdrop(SEARCH).convert("RGBA")
    x0, y0, x1, y1 = SEARCH_SAFE
    group, pad = with_shadow(scaled(cut, 1180))
    im.alpha_composite(group, (x1 - (group.width - 2 * pad) + 80 - pad, (y0 + y1) // 2 - 1180 // 2 - pad))
    text = text_block(title, tagline, 680, 160, 66)
    im.alpha_composite(text, (x0 + 10, (y0 + y1) // 2 - text.height // 2))
    return im.convert("RGB")


def label(text):
    from PIL.PngImagePlugin import PngInfo
    info = PngInfo()
    info.add_text("Title", text)
    return info


def encode(frames, path, title):
    W, H = HEADER
    enc = subprocess.Popen(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
         "-framerate", str(FPS), "-i", "-", "-c:v", "libx264", "-profile:v", "high", "-pix_fmt", "yuv420p",
         "-crf", "18", "-preset", "slow", "-movflags", "+faststart", "-an",
         # each language's file differs: Apple stalls byte-identical uploads (our other apps, 15 Nov)
         "-metadata", f"title={title}", path],
        stdin=subprocess.PIPE)
    first = None
    for f in frames:
        first = first or f
        enc.stdin.write(f.tobytes())
    enc.stdin.close()
    assert enc.wait() == 0
    return first


def main(locales):
    cut = phones(panorama())
    for loc in locales:
        title, tagline = TEXTS[loc]
        out = os.path.join(HERE, "out", loc)
        os.makedirs(out, exist_ok=True)
        first = encode(header_frames(cut, title, tagline), os.path.join(out, "header.mp4"), f"Outer News header {loc}")
        first.save(os.path.join(out, "header-poster.jpg"), quality=92)
        first.crop((555, 0, 3285, HEADER[1])).resize((1365, 823)).save(os.path.join(out, "iphone-header.jpg"), quality=85)
        search_picture(cut, title, tagline).save(os.path.join(out, "search.png"), pnginfo=label(f"Outer News search {loc}"))
        print("ok", loc)


if __name__ == "__main__":
    main(sys.argv[1:] or list(TEXTS))
