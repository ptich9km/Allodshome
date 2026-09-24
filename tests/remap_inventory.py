#!/usr/bin/env python3
"""Remap inventory item images with color/brightness variations.

For each PNG in assets/inventory/, create a modified version in import/
that looks different but keeps the same shape (hue shift + brightness/contrast).
"""

import os
import random
import colorsys
from PIL import Image, ImageEnhance, ImageFilter

SRC = "/media/alexey/EEF4D0F9F4D0C4CD/Work/Allodshome/assets/inventory"
DST = "/media/alexey/EEF4D0F9F4D0C4CD/Work/Allodshome/import"

random.seed(42)


def shift_hue(img, degrees):
    """Rotate hue by given degrees, preserving alpha."""
    if img.mode != "RGBA":
        img = img.convert("RGBA")

    # Work on RGB channels only
    r, g, b, a = img.split()
    rgb = Image.merge("RGB", (r, g, b))
    hsv = rgb.convert("HSV")
    h, s, v = hsv.split()

    # Hue is 0-255 in PIL HSV, rotate
    h_arr = list(h.getdata())
    shift = int(degrees / 360 * 256) % 256
    h_arr = [(x + shift) % 256 for x in h_arr]
    h.putdata(h_arr)

    hsv_rotated = Image.merge("HSV", (h, s, v))
    rgb_rotated = hsv_rotated.convert("RGB")
    rr, gg, bb = rgb_rotated.split()

    return Image.merge("RGBA", (rr, gg, bb, a))


def process_image(src_path, dst_path):
    img = Image.open(src_path).convert("RGBA")

    # Random hue shift: -60 to +60 degrees (subtle, keeps item recognizable)
    hue_shift = random.uniform(-60, 60)
    img = shift_hue(img, hue_shift)

    # Random brightness: 0.85 to 1.15
    brightness = random.uniform(0.85, 1.15)
    enhancer = ImageEnhance.Brightness(img)
    img = enhancer.enhance(brightness)

    # Random contrast: 0.9 to 1.2
    contrast = random.uniform(0.9, 1.2)
    enhancer = ImageEnhance.Contrast(img)
    img = enhancer.enhance(contrast)

    # Random saturation: 0.8 to 1.3
    saturation = random.uniform(0.8, 1.3)
    enhancer = ImageEnhance.Color(img)
    img = enhancer.enhance(saturation)

    img.save(dst_path, "PNG")


def main():
    os.makedirs(DST, exist_ok=True)

    files = sorted(f for f in os.listdir(SRC) if f.endswith(".png"))
    total = len(files)
    print(f"Processing {total} files...")

    for i, fname in enumerate(files):
        src = os.path.join(SRC, fname)
        dst = os.path.join(DST, fname)
        process_image(src, dst)
        if (i + 1) % 50 == 0:
            print(f"  {i + 1}/{total}")

    print(f"Done! {total} files saved to {DST}")


if __name__ == "__main__":
    main()
