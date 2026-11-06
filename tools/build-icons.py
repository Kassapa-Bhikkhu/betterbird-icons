#!/usr/bin/env python3
"""
Build the icon sets in icons/ from the Betterbird designs in source/.

Each set is a folder holding messengerWindow.ico (main window) and, when the
design has an "unread" variant, newmail.ico (new-mail notification). Those are
the two file names Betterbird reads from <install dir>\\chrome\\icons\\default.

  - SVG designs are converted with svg_to_ico.py (rendered fresh at every size).
  - The ready-made .ico files from betterbird.eu are copied as they are.

usage: python tools/build-icons.py          (needs: pip install resvg-py pillow)
"""

import importlib.util
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "source"
OUT = ROOT / "icons"

# Loaded by path so this also works with python -I (which leaves the script's folder off sys.path).
_spec = importlib.util.spec_from_file_location("svg_to_ico", Path(__file__).resolve().parent / "svg_to_ico.py")
svg_to_ico = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(svg_to_ico)

# set name -> (main window design, new-mail design or None)
SVG_SETS = {
    "blue": ("betterbird-blue.svg", "betterbird-unread-blue.svg"),
    "lightgrey": ("betterbird-lightgrey.svg", "betterbird-unread-lightgrey.svg"),
    "green2": ("betterbird-green2.svg", "betterbird-unread-green2.svg"),
    "uk": ("betterbird-uk.svg", "betterbird-unread-uk.svg"),
}
# set name -> (main window .ico or None, new-mail .ico or None)
ICO_SETS = {
    "bb": ("messengerWindow-bb.ico", "newmail-bb.ico"),
    "bb-green": ("messengerWindow-bb-green.ico", "newmail-bb-green.ico"),
    "newmail-sm": (None, "newmail-sm.ico"),
}


def set_folder(name, has_main, has_newmail):
    """The set's folder, without a file left over from an earlier build that the set no longer has."""
    folder = OUT / name
    folder.mkdir(parents=True, exist_ok=True)
    for file, wanted in (("messengerWindow.ico", has_main), ("newmail.ico", has_newmail)):
        if not wanted:
            (folder / file).unlink(missing_ok=True)
    return folder


def build_popup():
    """The large new-mail popup uses two PNGs inside omni.ja, not the .ico files.

    yours is rendered from the blue design. factory is Betterbird's own logo,
    copied from source/popup-factory so the popup can be put back.
    """
    yours = OUT / "popup" / "yours"
    yours.mkdir(parents=True, exist_ok=True)
    for size, name in ((64, "icon64.png"), (128, "icon128.png")):
        svg_to_ico.render(SRC / "betterbird-blue.svg", size).save(yours / name, "PNG")
    factory = OUT / "popup" / "factory"
    factory.mkdir(parents=True, exist_ok=True)
    for name in ("icon64.png", "icon128.png"):
        shutil.copyfile(SRC / "popup-factory" / name, factory / name)
    print("popup      yours from betterbird-blue.svg, factory copied")


def main():
    for name, (main_svg, unread_svg) in SVG_SETS.items():
        folder = set_folder(name, True, unread_svg)
        svg_to_ico.svg_to_ico(SRC / main_svg, folder / "messengerWindow.ico")
        if unread_svg:
            svg_to_ico.svg_to_ico(SRC / unread_svg, folder / "newmail.ico")
        print(f"{name:10} built from {main_svg}" + (f" + {unread_svg}" if unread_svg else ""))
    for name, (main_ico, newmail_ico) in ICO_SETS.items():
        folder = set_folder(name, main_ico, newmail_ico)
        if main_ico:
            shutil.copyfile(SRC / main_ico, folder / "messengerWindow.ico")
        if newmail_ico:
            shutil.copyfile(SRC / newmail_ico, folder / "newmail.ico")
        print(f"{name:10} copied from {main_ico or '-'} / {newmail_ico or '-'}")
    build_popup()
    known = set(SVG_SETS) | set(ICO_SETS) | {"popup"}
    stale = sorted(p.name for p in OUT.iterdir() if p.is_dir() and p.name not in known)
    if stale:
        print(f"Not built from source/, check whether these are still wanted: {', '.join(stale)}")


if __name__ == "__main__":
    main()
