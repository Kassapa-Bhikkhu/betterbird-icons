#!/usr/bin/env python3
"""
Turn an SVG into a Windows .ico with every size Windows uses (16-256 px), for use with
Set-BetterbirdIcon.ps1 -Icon <file.ico>.

Each size is rendered fresh from the SVG rather than scaled down from one big bitmap, so small
sizes stay crisp. Sizes below 256 are stored as 32-bit BMP entries and 256 as PNG - the classic
ICO layout every Windows icon loader understands.

usage: python tools/svg_to_ico.py <input.svg> <output.ico>      (needs: pip install resvg-py pillow)
"""

import io
import struct
import sys
from pathlib import Path

import resvg_py
from PIL import Image

SIZES = [16, 32, 48, 128, 256]


def render(svg, size):
    png = bytes(resvg_py.svg_to_bytes(svg_path=str(svg), width=size, height=size))
    return Image.open(io.BytesIO(png)).convert("RGBA")


def bmp_entry(img):
    """32-bit BGRA DIB (bottom-up, double height) plus a 1-bit AND mask."""
    w, h = img.size
    header = struct.pack("<IiiHHIIiiII", 40, w, h * 2, 1, 32, 0, 0, 0, 0, 0, 0)
    bgra = img.transpose(Image.FLIP_TOP_BOTTOM).tobytes("raw", "BGRA")
    stride = ((w + 31) // 32) * 4
    alpha = img.getchannel("A").transpose(Image.FLIP_TOP_BOTTOM).tobytes()
    mask = bytearray(stride * h)
    for y in range(h):
        for x in range(w):
            if alpha[y * w + x] == 0:
                mask[y * stride + x // 8] |= 0x80 >> (x % 8)
    return header + bgra + bytes(mask)


def write_ico(images, path):
    blobs = []
    for img in images:
        if img.size[0] >= 256:
            buf = io.BytesIO()
            img.save(buf, "PNG", optimize=True)
            blobs.append(buf.getvalue())
        else:
            blobs.append(bmp_entry(img))
    offset = 6 + 16 * len(images)
    out = struct.pack("<HHH", 0, 1, len(images))
    for img, blob in zip(images, blobs):
        w = img.size[0] % 256  # 0 means 256
        out += struct.pack("<BBBBHHII", w, w, 0, 0, 1, 32, len(blob), offset)
        offset += len(blob)
    Path(path).write_bytes(out + b"".join(blobs))


def svg_to_ico(svg, ico):
    write_ico([render(svg, s) for s in SIZES], ico)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[-1])
    svg, ico = Path(sys.argv[1]), Path(sys.argv[2])
    if not svg.is_file():
        sys.exit(f"Can't find {svg}")
    svg_to_ico(svg, ico)
    print(f"wrote {ico} ({', '.join(str(s) for s in SIZES)} px)")


if __name__ == "__main__":
    main()
