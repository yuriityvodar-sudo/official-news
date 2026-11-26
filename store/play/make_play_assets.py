#!/usr/bin/env python3
"""Google Play's icon (512x512) and feature graphic (1024x500) for Outer News (#343).
The graphic is the App Store header's light and words (store/assets, #338) without phones:
Play asks that it show no device frames. Run from the repo root: python3 store/play/make_play_assets.py
Out: store/play/out/ (not in git)."""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.environ.get("ASSETS_DIR", os.path.join(HERE, "..", "assets")))
from make_assets import backdrop, text_block  # noqa: E402
from texts import TEXTS  # noqa: E402

ICON = os.path.join(HERE, "..", "..", "app", "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset", "Icon-App-1024x1024@1x.png")


def main():
    out = os.path.join(HERE, "out")
    os.makedirs(out, exist_ok=True)
    icon = Image.open(ICON).convert("RGBA")
    icon.resize((512, 512), Image.LANCZOS).save(os.path.join(out, "icon-512.png"))
    W, H = 1024, 500
    im = backdrop((W, H)).convert("RGBA")
    # the icon on the right, with rounded corners as a launcher draws it
    size = 300
    from PIL import ImageDraw
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size * 4 - 1, size * 4 - 1), radius=size * 4 // 5, fill=255)
    ic = icon.resize((size, size), Image.LANCZOS)
    ic.putalpha(mask.resize((size, size), Image.LANCZOS))
    im.alpha_composite(ic, (W - size - 110, (H - size) // 2))
    title, tagline = TEXTS["en-US"]
    text = text_block(title, tagline, 520, 84, 38)
    im.alpha_composite(text, (80, (H - text.height) // 2))
    im.convert("RGB").save(os.path.join(out, "feature-graphic.png"))
    print("ok")


if __name__ == "__main__":
    main()
