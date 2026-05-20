// Vivarium - palette quantize + Bayer dither
// Apply to a CanvasItem (TextureRect / ColorRect) that displays the
// SubViewport output. The shader snaps incoming color to nearest palette
// entry, with ordered dither between the two nearest entries so gradients
// don't band ugly.
//
// Set up:
//   - texture_filter = nearest
//   - palette_tex    = 48x1 RGBA PNG, sRGB, no mipmaps, nearest filter
//   - palette_size   = number of colors in the palette texture
//   - dither_strength = 0.0 (off) .. 1.0 (full)

shader_type canvas_item;
render_mode unshaded;

uniform sampler2D palette_tex : source_color, filter_nearest, repeat_disable;
uniform int palette_size = 48;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.85;
uniform vec2 internal_resolution = vec2(384.0, 216.0);

// Bayer 4x4 ordered dither matrix, values pre-normalized to [-0.5, 0.5)
// so the dither is symmetric around the threshold.
const float bayer4[16] = float[16](
     0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
    12.0/16.0,  4.0/16.0, 14.0/16.0,  6.0/16.0,
     3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
    15.0/16.0,  7.0/16.0, 13.0/16.0,  5.0/16.0
);

float bayer_at(vec2 pixel_xy) {
    ivec2 p = ivec2(mod(pixel_xy, 4.0));
    return bayer4[p.y * 4 + p.x] - 0.5;
}

// Look up palette color by integer index.
vec3 palette_color(int idx) {
    float u = (float(idx) + 0.5) / float(palette_size);
    return texture(palette_tex, vec2(u, 0.5)).rgb;
}

// Find the two nearest palette colors to `c` and a 0..1 blend t.
// Returns: ivec3(a_idx, b_idx, ignored), and outputs t via out_t.
void nearest_two(vec3 c, out int ai, out int bi, out float t) {
    float best  = 1e9;
    float best2 = 1e9;
    ai = 0; bi = 0;
    for (int i = 0; i < 64; i++) {              // hard upper bound for WebGL safety
        if (i >= palette_size) break;
        vec3 p = palette_color(i);
        float d = dot(c - p, c - p);
        if (d < best) {
            best2 = best; bi = ai;
            best  = d;    ai = i;
        } else if (d < best2) {
            best2 = d; bi = i;
        }
    }
    // distances are squared; t is how far c lies from a toward b along the
    // line between them.
    vec3 a = palette_color(ai);
    vec3 b = palette_color(bi);
    vec3 ab = b - a;
    float denom = max(dot(ab, ab), 1e-6);
    t = clamp(dot(c - a, ab) / denom, 0.0, 1.0);
}

void fragment() {
    vec3 src = texture(TEXTURE, UV).rgb;

    int ai; int bi; float t;
    nearest_two(src, ai, bi, t);

    // Bayer threshold biased by dither_strength.
    // Pixel coords in internal-resolution space so dither stays crisp at any
    // upscale factor.
    vec2 px = UV * internal_resolution;
    float threshold = 0.5 + bayer_at(px) * dither_strength;

    int chosen = (t > threshold) ? bi : ai;
    COLOR = vec4(palette_color(chosen), 1.0);
}
