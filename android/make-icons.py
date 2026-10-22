"""Regenerate android/res/mipmap-*/ic_launcher.png from proxy/icons/icon-512.png.

Replace proxy/icons/icon-512.png with your own artwork first if you want a different icon.
Requires Pillow:  python make-icons.py [--src path/to/icon-512.png]
"""
import argparse
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DEFAULT_SRC = os.path.join(REPO, "proxy", "icons", "icon-512.png")
RES = os.path.join(HERE, "res")

DENSITIES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

parser = argparse.ArgumentParser()
parser.add_argument("--src", default=DEFAULT_SRC)
args = parser.parse_args()

img = Image.open(args.src).convert("RGBA")
print("source:", args.src, img.size)

for folder, size in DENSITIES.items():
    out_dir = os.path.join(RES, folder)
    os.makedirs(out_dir, exist_ok=True)
    dst = os.path.join(out_dir, "ic_launcher.png")
    img.resize((size, size), Image.LANCZOS).save(dst, "PNG", optimize=True)
    print(f"  {folder}: {size}px -> {os.path.getsize(dst)} bytes")
