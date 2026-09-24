#!/usr/bin/env python3
"""Recolor gold ingot photo to create 19 material variants."""

from PIL import Image, ImageEnhance, ImageFilter
import colorsys

# Base ingot image (user provided)
BASE_IMAGE = "/media/alexey/EEF4D0F9F4D0C4CD/Work/Allodshome/import/636d848e-8699-4c84-8fc4-f5bab096bcfd.png"
DST = "/media/alexey/EEF4D0F9F4D0C4CD/Work/Allodshome/import"

# Material colors (RGB)
MATERIALS = {
    # Base
    "bronze": (184, 115, 51),
    "iron": (120, 120, 125),
    "steel": (192, 192, 200),
    # Alliance of Light
    "argentum": (200, 200, 210),
    "lutetium": (230, 220, 180),
    "lanthanum": (210, 220, 240),
    "terbium": (220, 240, 220),
    # Hordes of Fire
    "wolfram": (100, 90, 80),
    "chromium": (160, 170, 190),
    "cobalt": (60, 80, 140),
    "titanium": (140, 120, 160),
    # Reapers
    "thorium": (80, 90, 70),
    "uranium": (100, 160, 100),
    "plutonium": (60, 40, 80),
    "radium": (100, 180, 220),
    # Druid Circle
    "gallium": (140, 180, 150),
    "yttrium": (60, 160, 100),
    "promethium": (80, 180, 200),
    "neodymium": (200, 190, 220),
}


def recolor_image(img, target_rgb):
    """Recolor image to target color while preserving luminosity."""
    # Convert to RGBA if needed
    if img.mode != "RGBA":
        img = img.convert("RGBA")

    # Get pixel data
    pixels = img.load()
    width, height = img.size

    target_r, target_g, target_b = target_rgb

    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]

            # Skip transparent pixels
            if a < 10:
                continue

            # Convert to HSV to get luminosity
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)

            # Keep luminosity (v) from original, apply target color
            # Blend: 70% target color, 30% original luminosity
            new_r = int(target_r * 0.7 + (r * v) * 0.3)
            new_g = int(target_g * 0.7 + (g * v) * 0.3)
            new_b = int(target_b * 0.7 + (b * v) * 0.3)

            # Clamp
            new_r = max(0, min(255, new_r))
            new_g = max(0, min(255, new_g))
            new_b = max(0, min(255, new_b))

            pixels[x, y] = (new_r, new_g, new_b, a)

    return img


def main():
    # Load base image
    img = Image.open(BASE_IMAGE)
    print(f"Loaded: {BASE_IMAGE} ({img.size})")

    # Resize to 80x80
    img_resized = img.resize((80, 80), Image.LANCZOS)
    print(f"Resized to: 80x80")

    # Generate variants
    for mat_name, color_rgb in MATERIALS.items():
        # Recolor
        variant = recolor_image(img_resized.copy(), color_rgb)

        # Save
        path = f"{DST}/{mat_name}_ingot.png"
        variant.save(path)
        print(f"  {mat_name}_ingot.png → RGB{color_rgb}")

    print(f"\nDone! {len(MATERIALS)} ingot variants saved to {DST}")


if __name__ == "__main__":
    print("Recoloring gold ingot to 19 materials...")
    main()
