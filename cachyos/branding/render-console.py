#!/usr/bin/env python3
"""Render an SVG mark as Linux-console block art.

Each character cell shows two stacked pixels, so the mark is rasterised at
COLS x (2 * rows) and each pixel pair becomes ' ', '▀', '▄' or '█'. The
console draws these in one foreground colour, so the art works with the
16-colour VT palette. Needs ImageMagick (`magick`) with SVG support.

  render-console.py owl.svg --cols 48 --ansi > owl.ansi
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

CELLS = " ▀▄█"   # index = top + 2 * bottom


def raster(svg_path: str, cols: int) -> list[list[bool]]:
    svg = Path(svg_path).read_text().replace("currentColor", "#000000")
    m = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', svg)
    if not m:
        sys.exit(f"render-console: {svg_path} has no viewBox")
    w, h = float(m.group(1)), float(m.group(2))
    rows = max(1, round(cols * h / w / 2))
    px_h = rows * 2
    raw = subprocess.run(
        ["magick", "-background", "none", "-density", "600", "svg:-",
         "-resize", f"{cols}x{px_h}!", "-alpha", "extract", "-depth", "8", "gray:-"],
        input=svg.encode(), capture_output=True, check=True).stdout
    if len(raw) != cols * px_h:
        sys.exit(f"render-console: expected {cols * px_h} pixels, got {len(raw)}")
    return [[raw[y * cols + x] >= 128 for x in range(cols)] for y in range(px_h)]


def blocks(px: list[list[bool]]) -> list[str]:
    lines = []
    for top, bottom in zip(px[0::2], px[1::2]):
        lines.append("".join(CELLS[t + 2 * b] for t, b in zip(top, bottom)).rstrip())
    while lines and not lines[0]:
        lines.pop(0)
    while lines and not lines[-1]:
        lines.pop()
    return lines


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("svg")
    ap.add_argument("--cols", type=int, default=48)
    ap.add_argument("--ansi", action="store_true", help="wrap lines in an SGR colour")
    ap.add_argument("--sgr", default="97", help="SGR colour code for --ansi (default 97 = slot 15)")
    a = ap.parse_args()
    lines = blocks(raster(a.svg, a.cols))
    if a.ansi:
        lines = [f"\x1b[{a.sgr}m{line}\x1b[0m" if line else line for line in lines]
    print("\n".join(lines))


if __name__ == "__main__":
    main()
