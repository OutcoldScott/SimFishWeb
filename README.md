# Vivarium — generative pixel-art aquarium

A starter kit for the game. Four pieces, each standalone:

| Folder | What it is | Start here if you want to... |
|---|---|---|
| [`style-guide/`](./style-guide/) | Palettes, pixel rules, dithering, sprite conventions | See the look and feel locked in |
| [`shaders-godot/`](./shaders-godot/) | Godot 4 rendering pipeline (low-res viewport + palette LUT + dither) | Get pixels on screen this weekend |
| [`sim-rust/`](./sim-rust/) | Standalone Rust crate: falling-sand substrate + chemistry diffusion + nitrogen cycle | Prove the sim works headless |
| [`data-schemas/`](./data-schemas/) | JSON schemas for plant, fauna, substrate species + example data | Add content without recompiling |

## Recommended order

1. **Skim `style-guide/`** so you have the palette in your head.
2. **Run `sim-rust/`** (`cd sim-rust && cargo run --example cycle`) — watch a tank cycle in your terminal. This proves the chemistry sim before you write a single shader.
3. **Open `shaders-godot/`** in Godot 4.x and run the demo scene — chunky bubbles in a palette-quantized tank.
4. **Use `data-schemas/`** as the contract between (2) and (3) — load species JSON, sim them in Rust, render them in Godot.

The four pieces are deliberately decoupled. You can throw any of them out later.
