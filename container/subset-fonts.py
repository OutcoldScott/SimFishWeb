#!/usr/bin/env python3
"""Download + subset the web fallback fonts for the Vivarium web export.

Run in the container's font-builder stage. Produces several tiny TTFs in the
output dir, each holding only the glyphs the UI actually uses as icons. They
get copied into res://fonts/ before `godot --export-debug Web`, then chained
onto ThemeDB.fallback_font at runtime by web_emoji_fallback.gd.

No single freely-licensed font covers the whole glyph set, so the monochrome
symbols are split across three Noto sources (the runtime fallback chain tries
each until a glyph is found):

  web_fallback_symbols2.ttf  Noto Sans Symbols2  -> pause, star, warning,
                             geometric, dingbats, Latin punctuation
  web_fallback_math.ttf      Noto Sans Math      -> arrows, box drawing,
                             joined-squares, phi
  web_fallback_text.ttf      Noto Sans           -> subscript two
  web_fallback_emoji.ttf     Noto Color Emoji    -> the 11 color emoji

Each source is asked for the full symbol set and keeps only what it has
(ignore_missing_unicodes), so overlap is harmless and the files stay tiny.

Nothing here is committed except this script; the font binaries live only
inside the build.

Usage:  subset-fonts.py <output_dir>
"""

import sys
import os
import tempfile
import urllib.request

from fontTools import subset
from fontTools.ttLib import TTFont

# Monochrome BMP symbols used as UI glyphs. Keep in sync with the non-ASCII
# inventory in scripts/*.gd string literals AND the .tscn scene files
# (main.tscn defines the top-bar buttons).
SYMBOL_CODEPOINTS = [
    0x00B7,  # MIDDLE DOT
    0x2014,  # EM DASH
    0x2022,  # BULLET
    0x00D7,  # MULTIPLICATION SIGN
    0x2550,  # BOX DRAWINGS DOUBLE HORIZONTAL
    0x00B0,  # DEGREE SIGN
    0x2192,  # RIGHTWARDS ARROW
    0x23F8,  # DOUBLE VERTICAL BAR (pause)
    0x2082,  # SUBSCRIPT TWO
    0x25F4,  # WHITE CIRCLE WITH UPPER LEFT QUADRANT
    0x2665,  # BLACK HEART SUIT
    0x2726,  # BLACK FOUR POINTED STAR
    0x26A0,  # WARNING SIGN
    0x03C6,  # GREEK SMALL LETTER PHI
    0x25B6,  # BLACK RIGHT-POINTING TRIANGLE
    0x21A9,  # LEFTWARDS ARROW WITH HOOK
    0x2194,  # LEFT RIGHT ARROW
    0x29C9,  # TWO JOINED SQUARES
    0x2261,  # IDENTICAL TO (hamburger "Menu" button)
    0x25A6,  # SQUARE WITH ORTHOGONAL CROSSHATCH FILL ("Render" button)
    0x2303,  # UP ARROWHEAD (Ctrl key, "click feed" legend)
    0x2699,  # GEAR (settings button)
]

EMOJI_CODEPOINTS = [
    0x1F642,  # SLIGHTLY SMILING FACE
    0x1F60C,  # RELIEVED FACE
    0x1F61F,  # WORRIED FACE
    0x1F6A8,  # POLICE CARS REVOLVING LIGHT
    0x1F41F,  # FISH
    0x1F990,  # SHRIMP
    0x1F40C,  # SNAIL
    0x1F33F,  # HERB
    0x1F4A7,  # DROPLET
    0x1F4F7,  # CAMERA
    0x1F5D1,  # WASTEBASKET
    0x1F441,  # EYE (follow-cam button)
    0x1FAA8,  # ROCK (aquascape button)
]

# (output filename, [candidate URLs], codepoints). First URL that downloads
# wins. All OFL-licensed. The google/fonts mirror layout is the most stable;
# variable-font filenames use %5B/%5D for the [] axis tags.
SOURCES = [
    ("web_fallback_symbols2.ttf", [
        "https://github.com/google/fonts/raw/main/ofl/notosanssymbols2/NotoSansSymbols2-Regular.ttf",
    ], SYMBOL_CODEPOINTS),
    ("web_fallback_math.ttf", [
        "https://github.com/google/fonts/raw/main/ofl/notosansmath/NotoSansMath-Regular.ttf",
    ], SYMBOL_CODEPOINTS),
    # Original Noto Sans Symbols (variable). Covers the up-arrowhead (Ctrl)
    # and gear that none of the others have.
    ("web_fallback_symbols1.ttf", [
        "https://github.com/google/fonts/raw/main/ofl/notosanssymbols/NotoSansSymbols%5Bwght%5D.ttf",
    ], SYMBOL_CODEPOINTS),
    ("web_fallback_text.ttf", [
        "https://github.com/google/fonts/raw/main/ofl/notosans/NotoSans%5Bwdth,wght%5D.ttf",
    ], SYMBOL_CODEPOINTS),
    # Classic CBDT/CBLC bitmap build renders as color in FreeType (Godot's
    # rasterizer). The google/fonts COLRv1 build is the fallback URL.
    ("web_fallback_emoji.ttf", [
        "https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf",
        "https://github.com/google/fonts/raw/main/ofl/notocoloremoji/NotoColorEmoji-Regular.ttf",
    ], EMOJI_CODEPOINTS),
]


def download(urls, dest):
    last_err = None
    for url in urls:
        try:
            print(f"  fetching {url}")
            req = urllib.request.Request(url, headers={"User-Agent": "vivarium-build"})
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = resp.read()
            if len(data) < 1024:
                raise ValueError(f"suspiciously small ({len(data)} bytes)")
            with open(dest, "wb") as fh:
                fh.write(data)
            print(f"  -> {len(data)} bytes")
            return
        except Exception as e:  # noqa: BLE001 - try the next candidate URL
            print(f"  failed: {e}")
            last_err = e
    raise SystemExit(f"could not download any of {urls}: {last_err}")


def subset_font(src, dest, codepoints):
    opts = subset.Options()
    # Keep color tables (CBDT/CBLC, COLR/CPAL, sbix) so emoji stay in color.
    opts.passthrough_tables = False
    opts.layout_features = ["*"]
    # Don't choke if the source lacks a requested codepoint; just drop it.
    opts.ignore_missing_unicodes = True
    opts.recalc_bounds = True
    opts.recalc_timestamp = False
    # OFL compliance: retain the whole name table so the copyright (nameID 0)
    # AND the embedded license + URL (nameIDs 13/14) survive into the subset.
    # pyftsubset's default drops 13/14, which would ship the fonts without
    # their license. The OFL accepts the license living in machine-readable
    # metadata fields inside the binary, so this keeps each subset compliant
    # on its own.
    opts.name_IDs = ["*"]
    opts.name_legacy = True
    opts.name_languages = ["*"]

    font = subset.load_font(src, opts)
    subsetter = subset.Subsetter(options=opts)
    subsetter.populate(unicodes=codepoints)
    subsetter.subset(font)

    cmap = font.getBestCmap()
    kept = sorted(cp for cp in codepoints if cp in cmap)
    subset.save_font(font, dest, opts)
    size = os.path.getsize(dest)
    print(f"  {os.path.basename(dest)}: kept {len(kept)}/{len(codepoints)} "
          f"glyphs, {size} bytes")

    # Pull the copyright + license out of the subset for the aggregated notice.
    ft = TTFont(dest)
    info = {
        "copyright": ft["name"].getDebugName(0),
        "license": ft["name"].getDebugName(13),
        "license_url": ft["name"].getDebugName(14),
        "family": ft["name"].getDebugName(1),
    }
    return set(kept), info


def write_notices(path, notices):
    """Aggregate per-font copyright + the OFL license into one notice file.

    Bundled into the image/web root so the redistributed (subset) fonts ship
    with their license, satisfying OFL 1.1 condition 2 independently of the
    metadata embedded in the font binaries.
    """
    lines = [
        "Third-party font notices for the Vivarium web build",
        "===================================================",
        "",
        "The bundled web fallback fonts (res://fonts/web_fallback_*.ttf) are",
        "subsets of the fonts below, redistributed under the SIL Open Font",
        "License 1.1. Subsetting is a Modified Version permitted by the OFL;",
        "no Reserved Font Name is declared by any of these families.",
        "",
    ]
    license_text = None
    for fname, info in notices:
        lines.append(f"--- {fname}  (from {info.get('family')}) ---")
        lines.append(info.get("copyright") or "(no copyright string)")
        if info.get("license_url"):
            lines.append(info["license_url"])
        lines.append("")
        if license_text is None and info.get("license"):
            license_text = info["license"]
    lines.append("=" * 51)
    lines.append("SIL OPEN FONT LICENSE Version 1.1 (as embedded in the fonts)")
    lines.append("=" * 51)
    lines.append("")
    lines.append(license_text or "(license text unavailable)")
    lines.append("")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    print(f"  wrote {os.path.basename(path)} ({os.path.getsize(path)} bytes)")


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: subset-fonts.py <output_dir>")
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)

    covered = set()
    notices = []
    with tempfile.TemporaryDirectory() as tmp:
        for fname, urls, codepoints in SOURCES:
            print(f"{fname}:")
            src = os.path.join(tmp, fname + ".src")
            download(urls, src)
            kept, info = subset_font(src, os.path.join(out_dir, fname), codepoints)
            notices.append((fname, info))
            if codepoints is SYMBOL_CODEPOINTS:
                covered |= kept

    write_notices(os.path.join(out_dir, "THIRD_PARTY_NOTICES.txt"), notices)

    # Report any symbol the combined symbol fonts still miss, so a broken
    # build is obvious in the log rather than silently shipping tofu.
    missing = [hex(cp) for cp in SYMBOL_CODEPOINTS if cp not in covered]
    if missing:
        print(f"WARNING symbols not covered by any source: {missing}")
    else:
        print("all symbol glyphs covered")
    print("done")


if __name__ == "__main__":
    main()
