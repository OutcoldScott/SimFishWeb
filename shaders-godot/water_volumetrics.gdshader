// Vivarium - water volume + light attenuation + caustics
// Apply to the water-column ColorRect inside the tank scene.
// Reads:
//   density_tex   : R8 grid (288x144) of water particle density per cell
//   chemistry_tex : RGBA grid; R=tannins, G=NH3, B=cloudiness, A=O2 saturation
//   surface_y     : current normalized water surface (0=top, 1=bottom)
// Writes a still-continuous color (no quantization here) - the palette_quantize
// pass on the final viewport snaps it to the palette later. Keep this layer in
// linear continuous color so the dither in the next stage works correctly.

shader_type canvas_item;
render_mode unshaded;

uniform sampler2D density_tex   : filter_linear,  repeat_disable;
uniform sampler2D chemistry_tex : filter_linear,  repeat_disable;
uniform float surface_y : hint_range(0.0, 1.0) = 0.15;
uniform float time_seconds = 0.0;

// Tunable water-color anchors (planted-biotope defaults).
uniform vec3 water_shallow = vec3(0.42, 0.62, 0.66);
uniform vec3 water_deep    = vec3(0.04, 0.10, 0.14);
uniform vec3 tannin_tint   = vec3(0.85, 0.55, 0.25);

// Beer-Lambert attenuation - light falls off with depth + turbidity.
float beer(float depth, float k) {
    return exp(-k * depth);
}

// Cheap 2D value noise for caustics. Not great noise, but it dithers nicely
// in the next stage and that hides the artifacts.
float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
    // 0 at surface, 1 at bottom of viewport; clamp so above-water rows are skipped.
    float depth = clamp((UV.y - surface_y) / max(1.0 - surface_y, 1e-3), 0.0, 1.0);

    // Sample chemistry/density at same UV.
    vec4 chem = texture(chemistry_tex, UV);
    float tannins    = chem.r;
    float ammonia    = chem.g;
    float cloudiness = chem.b;
    float o2_sat     = chem.a;

    // Higher turbidity = more attenuation.
    float k = 1.6 + cloudiness * 3.0 + tannins * 1.2;
    float light = beer(depth, k);

    // Base water color: shallow->deep ramp by attenuation.
    vec3 col = mix(water_deep, water_shallow, light);

    // Tannins multiply the water color toward warm brown.
    col = mix(col, col * tannin_tint, tannins);

    // Ammonia haze - subtle sickly green tint, only at high values.
    col = mix(col, col + vec3(0.02, 0.06, -0.02), clamp(ammonia * 0.5, 0.0, 0.3));

    // Caustics in the top quarter, modulated by surface flatness (cheap: just time).
    if (depth < 0.25) {
        vec2 cuv = UV * vec2(40.0, 60.0) + vec2(time_seconds * 0.4, time_seconds * 0.15);
        float c = vnoise(cuv);
        c = smoothstep(0.55, 0.85, c);
        float caustic_strength = (1.0 - depth / 0.25) * 0.25;
        col += vec3(c) * caustic_strength;
    }

    // Density field gives a slight "thickness" - empty cells fade toward
    // background. Useful at the surface where the water particle count drops.
    float density = texture(density_tex, UV).r;
    col *= mix(0.8, 1.0, density);

    COLOR = vec4(col, 1.0);
}
