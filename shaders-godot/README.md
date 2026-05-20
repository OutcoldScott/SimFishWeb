# Godot 4 rendering pipeline

Two-shader pipeline for the Vivarium look:

1. **`palette_quantize.gdshader`** — applied to a `ColorRect` covering the low-res SubViewport output. Snaps incoming color to nearest palette entry, applies Bayer dither based on distance to next-nearest entry.
2. **`water_volumetrics.gdshader`** — applied to the water-column quad inside the tank. Samples a density texture (written by the sim each frame), produces depth-attenuated water color with caustics + dust motes.

## Scene structure

```
Main (Node2D)
├── SimDriver (Node)              # runs the Rust sim, writes textures
├── SubViewportContainer
│   └── SubViewport (384x216, stretch=true, render_mode=2D)
│       ├── Tank (Node2D)
│       │   ├── TankGlass (Sprite2D)        # hand-authored
│       │   ├── WaterVolume (ColorRect)      # water_volumetrics.gdshader
│       │   ├── Substrate (Sprite2D)         # texture written by sim
│       │   ├── Plants (Node2D)              # L-system meshes
│       │   ├── Fauna (Node2D)               # sprite per agent
│       │   ├── Bubbles (GPUParticles2D)
│       │   └── Detritus (GPUParticles2D)
│       └── Room (Sprite2D)                  # backdrop behind tank
└── Display (TextureRect)         # nearest-neighbor upscale, palette_quantize.gdshader
```

Set the `SubViewport` size to `384 × 216`, `Snap 2D Transforms to Pixel = true`, default canvas item filter = `Nearest`.

The `Display` `TextureRect` sources `SubViewportContainer`'s output as its texture, sized to the window, with the palette quantize shader as material.

## Quickstart

1. Open Godot 4.2+, create a new project at this folder.
2. Generate a starter palette PNG: run `python3 make_palette.py` (script included) to write `palettes/planted_48.png`.
3. Build the scene above; assign shaders.
4. Press play. You should see a chunky-pixel tank with rising bubbles.

The shaders are written to be Stage-1 of the project — they prove the look. You'll add real sim textures (substrate, water density, chemistry tint) once `sim-rust/` is wired in via GDExtension.
