"""
Generate the 48x1 palette PNGs used by palette_quantize.gdshader.

Usage:
    python3 make_palette.py            # writes palettes/*.png

Requires Pillow:
    pip install Pillow
"""

from pathlib import Path
from PIL import Image


PALETTES = {
    "planted_48": [
        # water cool ramp (8)
        "#0b1a22", "#163040", "#23475a", "#356379",
        "#4b8095", "#69a1b3", "#92c3d0", "#c5e2e7",
        # plant green ramp (8)
        "#102614", "#1d3b22", "#2c5a30", "#3e7f40",
        "#57a253", "#79c069", "#a5d97e", "#d0eb9a",
        # substrate browns (8)
        "#1a120c", "#2c1f15", "#432f1f", "#5d4128",
        "#785538", "#95714e", "#b18f6a", "#cdb088",
        # stone grays (8)
        "#1a1a1f", "#2a2a30", "#3d3d44", "#555560",
        "#707081", "#8c8ca0", "#a8a8bd", "#c4c4d6",
        # highlights / glass (3)
        "#ffffff", "#e0eef2", "#b9d6df",
        # fish accents (7)
        "#c33b3b", "#d97e2c", "#e6c92a", "#2a7a4b",
        "#4a52c4", "#872cb0", "#c44a8e",
        # extra wood/decay browns (4) + deep slot (1) + light slot (1)
        "#2c1810", "#1a0f08", "#0d0805", "#503820",
        "#000000", "#f8f4e0",
    ],
    "blackwater_48": [
        "#0a0907", "#15110b", "#251c10", "#382a14",
        "#4d3a1c", "#6a5128", "#8c7042", "#b9986a",
        "#0c0905", "#1a130a", "#2b2014", "#3d2f1e",
        "#57442d", "#735c40", "#927758", "#b29575",
        "#0e1a0d", "#1b2d18", "#2c4527", "#4a6738",
        "#6c894e", "#95ad6f", "#0d1015", "#1a1d22",
        "#2c2f34", "#444751", "#5d6068", "#777a82",
        "#92959c", "#adb0b6", "#c8cad0", "#e2e3e7",
        "#ffffff", "#f4e4c8", "#e0c89a",
        "#a13a2a", "#b86a30", "#d4a838", "#2e5a3c",
        "#3a4ca0", "#5e2c80", "#9c3c70", "#000000",
        "#7d6240", "#5a4630", "#3c2f20", "#241b12",
    ],
    "hard_alkaline_48": [
        "#0d1f25", "#1a3947", "#2e5a6e", "#467c92",
        "#62a1b4", "#87c2cf", "#b3def0", "#dff1f6",
        "#2a2620", "#423d34", "#5d574b", "#7c7466",
        "#9e957f", "#c0b899", "#ddd6b5", "#f0ecd2",
        "#4a4943", "#6b685d", "#8b8678", "#aaa595",
        "#c5c0b0", "#ddd9c8", "#efeddc", "#fbfbf0",
        "#10301c", "#1d4a2c", "#2c6440", "#458056",
        "#6ba07a", "#94c0a0", "#ffffff", "#000000",
        "#c44848", "#d97e2c", "#e6c92a", "#2c6db3",
        "#3a4ca0", "#7c2cb0", "#c44a8e", "#202020",
        "#3a3a3a", "#5a5a5a", "#7a7a7a", "#9a9a9a",
        "#bababa", "#dadada", "#f0f0f0", "#ffffff",
    ],
}


def hex_to_rgb(hex_str: str) -> tuple[int, int, int]:
    h = hex_str.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def write_palette(name: str, hexes: list[str], out_dir: Path) -> Path:
    assert len(hexes) == 48, f"{name}: expected 48 colors, got {len(hexes)}"
    img = Image.new("RGBA", (48, 1))
    for i, h in enumerate(hexes):
        r, g, b = hex_to_rgb(h)
        img.putpixel((i, 0), (r, g, b, 255))
    out_path = out_dir / f"{name}.png"
    img.save(out_path)
    return out_path


def main() -> None:
    out_dir = Path(__file__).parent / "palettes"
    out_dir.mkdir(exist_ok=True)
    for name, hexes in PALETTES.items():
        path = write_palette(name, hexes, out_dir)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
