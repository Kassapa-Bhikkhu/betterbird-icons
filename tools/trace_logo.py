#!/usr/bin/env python3
"""
Redraw a logo picture (PNG) as a clean vector SVG, then render a clean PNG from it.

Made for logos built like Betterbird's: one light shape (the bird) on a dark disc, each filled
with a top-to-bottom colour gradient, on a transparent background. This is how
source/betterbird-blue.svg was made from a PNG with jagged, grey-fringed edges.

  - the disc becomes a true <circle>, fitted to the picture's outline
  - the light shape is traced with potrace, which fits smooth curves through the pixel edges
    and keeps sharp tips as corners
  - both fills become linear gradients, sampled row by row from the solid parts of the picture

Writes <name>.svg and <name>-clean.png into the output folder. Check the result: a logo built
differently (several colours, no disc) will need a different approach.

usage: python tools/trace_logo.py <logo.png> <output folder>
       (needs: pip install potracer resvg-py pillow numpy opencv-python)
"""

import sys
from pathlib import Path

import cv2
import numpy as np
import potrace
import resvg_py
from PIL import Image


def fit_circle(alpha):
    """Centre and radius of the disc, from its outline, in SVG units (pixel edges)."""
    mask = (alpha > 127).astype(np.uint8)
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    if not contours or len(max(contours, key=len)) < 20:
        sys.exit("No disc found: the picture needs a solid disc on a transparent background.")
    pts = max(contours, key=len)[:, 0, :].astype(float) + 0.5   # pixel centres -> SVG coordinates
    a = np.c_[2 * pts, np.ones(len(pts))]
    cx, cy, c = np.linalg.lstsq(a, (pts ** 2).sum(1), rcond=None)[0]
    r = np.sqrt(c + cx * cx + cy * cy) + 0.5                       # outline pixel centres sit half a pixel in
    snap = lambda v: round(v * 2) / 2                              # tidy numbers: nearest half pixel
    return snap(cx), snap(cy), snap(r)


def row_profile(rgb, mask):
    """Median colour per row over masked pixels; NaN where a row has none."""
    prof = np.full((rgb.shape[0], 3), np.nan)
    for y in range(rgb.shape[0]):
        if mask[y].sum() >= 3:
            prof[y] = np.median(rgb[y][mask[y]], axis=0)
    return prof


def fill_profile(prof):
    """Fill NaN rows from the nearest rows, then smooth lightly."""
    ys = np.arange(len(prof))
    ok = ~np.isnan(prof[:, 0])
    out = np.stack([np.interp(ys, ys[ok], prof[ok, c]) for c in range(3)], 1)
    k = np.ones(9) / 9
    pad = np.pad(out, ((4, 4), (0, 0)), mode="edge")
    return np.stack([np.convolve(pad[:, c], k, mode="valid") for c in range(3)], 1)


def gradient_stops(prof, y0, y1, tol=1.0):
    """Fewest stops (greedy) whose straight-line blend stays within tol of the sampled colours."""
    stops, i = [y0], y0
    while i < y1:
        j = y1
        while j > i + 1:
            t = (np.arange(i, j + 1) - i) / (j - i)
            lin = prof[i] + t[:, None] * (prof[j] - prof[i])
            if np.abs(lin - prof[i:j + 1]).max() <= tol:
                break
            j -= 1
        stops.append(j)
        i = j
    return stops


def hexc(c):
    return "#%02x%02x%02x" % tuple(int(round(v)) for v in np.clip(c, 0, 255))


def gradient_xml(gid, prof, y0, y1, height):
    stops = gradient_stops(prof, y0, y1)
    rows = "\n".join(f'      <stop offset="{(y + 0.5) / height:.4f}" stop-color="{hexc(prof[y])}"/>' for y in stops)
    return (f'    <linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2="{height}">\n'
            f'{rows}\n    </linearGradient>'), len(stops)


def trace_to_path(mask):
    """potrace the mask into one SVG path string (outer shapes and holes; evenodd)."""
    # potracer traces the "black" (falsy) pixels, so hand it the inverted mask
    plist = potrace.Bitmap(~mask).trace(turdsize=4, turnpolicy=potrace.POTRACE_TURNPOLICY_MINORITY,
                                        alphamax=1.0, opticurve=True, opttolerance=0.2)
    f = lambda p: f"{p.x:.2f},{p.y:.2f}"
    parts, nseg = [], 0
    for curve in plist:
        d = "M" + f(curve.start_point)
        for s in curve.segments:
            nseg += 1
            if s.is_corner:
                d += "L" + f(s.c) + "L" + f(s.end_point)
            else:
                d += "C" + f(s.c1) + " " + f(s.c2) + " " + f(s.end_point)
        parts.append(d + "Z")
    return "".join(parts), len(parts), nseg


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[-2].strip())
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    im = np.array(Image.open(src).convert("RGBA")).astype(np.float64)
    rgb, alpha = im[..., :3], im[..., 3]
    h, w = alpha.shape
    cx, cy, r = fit_circle(alpha)
    yy, xx = np.mgrid[:h, :w]
    d = np.hypot(xx + 0.5 - cx, yy + 0.5 - cy)
    lum = rgb.mean(axis=-1)

    # Light shape vs dark disc: Otsu finds the two groups of brightness inside the disc; split halfway
    # between their averages, so a disc that is lighter at the top doesn't count as part of the shape.
    inside = lum[(d < 0.96 * r) & (alpha > 250)]
    if inside.size < 100:
        sys.exit("The disc has almost no solid pixels: is this a logo on a solid disc?")
    otsu, _ = cv2.threshold(inside.astype(np.uint8).reshape(-1, 1), 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    dark_px, light_px = inside[inside <= otsu], inside[inside > otsu]
    if not dark_px.size or not light_px.size:
        sys.exit("The disc is one flat colour: no light shape found on it.")
    split = (dark_px.mean() + light_px.mean()) / 2
    light = (lum > split) & (d < 0.96 * r)

    # Colour profiles from solid pixels only, well away from every edge.
    k = np.ones((5, 5), np.uint8)
    erode = lambda m: cv2.erode(m.astype(np.uint8), k).astype(bool)
    solid = alpha > 250
    dark_core = erode(solid & ~light & (d < 0.98 * r))
    light_core = erode(solid & light & (d < 0.94 * r))
    light_rows = np.nonzero(light_core.sum(1) >= 3)[0]
    if not len(light_rows) or not (dark_core.sum(1) >= 3).any():
        sys.exit("Couldn't find both a solid light shape and a solid dark disc: this logo is built differently.")
    dark_prof = fill_profile(row_profile(rgb, dark_core))
    light_prof = fill_profile(row_profile(rgb, light_core))

    path_d, ncurves, nseg = trace_to_path(light)
    disc_grad, nd = gradient_xml("disc", dark_prof, 0, h - 1, h)
    shape_grad, nl = gradient_xml("shape", light_prof, int(light_rows.min()), int(light_rows.max()), h)
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">
  <defs>
{disc_grad}
{shape_grad}
  </defs>
  <circle cx="{cx:g}" cy="{cy:g}" r="{r:g}" fill="url(#disc)"/>
  <path fill="url(#shape)" fill-rule="evenodd" d="{path_d}"/>
</svg>
'''
    out.mkdir(parents=True, exist_ok=True)
    svg_path = out / (src.stem + ".svg")
    svg_path.write_text(svg, encoding="utf-8", newline="\n")
    print(f"wrote {svg_path}  (disc at {cx:g},{cy:g} r {r:g}; {ncurves} curves, {nseg} segments; "
          f"gradient stops {nd} + {nl}; {len(svg) / 1024:.0f} KB)")
    png_path = out / (src.stem + "-clean.png")
    png_path.write_bytes(bytes(resvg_py.svg_to_bytes(svg_string=svg, width=w, height=h)))
    print(f"wrote {png_path}")


if __name__ == "__main__":
    main()
