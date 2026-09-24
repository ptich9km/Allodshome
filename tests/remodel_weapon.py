#!/usr/bin/env python3
"""Remodel weapon/armor by modifying SHAPE ONLY, preserving original colors.

Applies geometric transformations to change item silhouette:
- Blade width (wider/narrower)
- Blade length (longer/shorter)
- Curvature (bent blade)
- Guard shape (wider/narrower crossguard)
- Overall proportions

Original color palette is preserved exactly.
"""

from PIL import Image, ImageDraw, ImageFilter
import math

SRC = "/media/alexey/EEF4D0F9F4D0C4CD/Work/Allodshome/assets/inventory/0001002-000.png"
DST_DIR = "/media/alexey/EEF4D0F9F4D0C4CD/Work/Allodshome/import"


def reshape_item(img, variant):
    """Apply geometric shape transformation, preserving colors."""
    w, h = img.size

    if variant == 0:
        # Original - no change
        return img.copy()

    elif variant == 1:
        # Wider blade - stretch horizontally
        # Scale X by 1.2, keep Y same
        scaled = img.resize((int(w * 1.2), h), Image.LANCZOS)
        # Center crop back to original size
        offset = (scaled.size[0] - w) // 2
        return scaled.crop((offset, 0, offset + w, h))

    elif variant == 2:
        # Narrower blade - compress horizontally
        scaled = img.resize((int(w * 0.85), h), Image.LANCZOS)
        # Pad with transparent to original size
        result = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        offset = (w - scaled.size[0]) // 2
        result.paste(scaled, (offset, 0))
        return result

    elif variant == 3:
        # Longer blade - stretch vertically
        scaled = img.resize((w, int(h * 1.15)), Image.LANCZOS)
        # Crop from top (keep handle at bottom)
        offset = scaled.size[1] - h
        return scaled.crop((0, offset, w, h))

    elif variant == 4:
        # Shorter blade - compress vertically
        scaled = img.resize((w, int(h * 0.88)), Image.LANCZOS)
        # Pad at top
        result = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        offset = h - scaled.size[1]
        result.paste(scaled, (0, offset))
        return result

    elif variant == 5:
        # Curved blade - apply shear transformation
        # Shear X based on Y position (top shifts more than bottom)
        result = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        for y in range(h):
            # Shear amount: 0 at bottom (handle), increases toward top (blade)
            shear_factor = (h - y) / h * 8  # max 8px shift at top
            # Copy row with offset
            row = img.crop((0, y, w, y + 1))
            result.paste(row, (int(shear_factor), y))
        return result

    elif variant == 6:
        # Wider guard - stretch middle section horizontally
        # Split image into thirds: top (blade), middle (guard), bottom (handle)
        third = h // 3
        top = img.crop((0, 0, w, third))
        middle = img.crop((0, third, w, third * 2))
        bottom = img.crop((0, third * 2, w, h))

        # Stretch middle (guard) horizontally
        middle_stretched = middle.resize((int(w * 1.3), middle.size[1]), Image.LANCZOS)
        offset = (middle_stretched.size[0] - w) // 2
        middle_cropped = middle_stretched.crop((offset, 0, offset + w, middle.size[1]))

        # Recombine
        result = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        result.paste(top, (0, 0))
        result.paste(middle_cropped, (0, third))
        result.paste(bottom, (0, third * 2))
        return result

    elif variant == 7:
        # Thinner guard - compress middle section
        third = h // 3
        top = img.crop((0, 0, w, third))
        middle = img.crop((0, third, w, third * 2))
        bottom = img.crop((0, third * 2, w, h))

        middle_compressed = middle.resize((int(w * 0.75), middle.size[1]), Image.LANCZOS)
        result = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        offset = (w - middle_compressed.size[0]) // 2
        result.paste(top, (0, 0))
        result.paste(middle_compressed, (offset, third))
        result.paste(bottom, (0, third * 2))
        return result


def main():
    img = Image.open(SRC).convert("RGBA")

    # Generate 8 shape variants (colors preserved)
    variants = [
        "original",
        "wider_blade",
        "narrower_blade",
        "longer_blade",
        "shorter_blade",
        "curved_blade",
        "wider_guard",
        "thinner_guard",
    ]

    for i, shape in enumerate(variants):
        modified = reshape_item(img, i)
        path = f"{DST_DIR}/variant_{i:02d}_{shape}.png"
        modified.save(path)
        print(f"Saved: {path} ({shape})")


if __name__ == "__main__":
    main()
