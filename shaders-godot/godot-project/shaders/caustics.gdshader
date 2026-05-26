shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

uniform float caustic_intensity : hint_range(0.0, 1.0) = 1.0;
uniform float caustic_speed = 0.8;
uniform float caustic_scale = 1.2;
uniform vec4 light_color : source_color = vec4(1.0, 0.9, 0.8, 1.0);

void fragment() {
    // Get world-space coordinates of the pixel
    vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    
    // Project caustics onto XZ plane
    vec2 uv = world_pos.xz * caustic_scale;
    float t = TIME * caustic_speed;
    
    // Smooth sine-wave interference pattern (simulating wave crests crossing)
    float w1 = sin(uv.x * 1.2 + t * 0.7) * cos(uv.y * 0.8 - t * 0.5);
    float w2 = sin(uv.y * 1.4 + t * 0.9) * cos(uv.x * 1.1 + t * 0.6);
    float w3 = sin((uv.x + uv.y) * 0.6 - t * 0.3);
    
    // Combine waves and normalize to [0, 1] range
    float wave = (w1 + w2 + w3 + 1.5) / 3.0;
    
    // Use a soft smoothstep to get broad, flowing ripple bands instead of sharp dots.
    // Keeps the color transition gentle so the palette quantizer/dither behaves smoothly.
    float caustics = smoothstep(0.2, 0.8, wave) * 0.40;
    
    // Fade out caustics near the edges of the tank to match the natural light pool falloff
    // (Tank boundary is approx X: [-8.0, 8.0], Z: [-4.0, 4.0])
    float edge_fade_x = clamp(1.0 - abs(world_pos.x) / 7.5, 0.0, 1.0);
    float edge_fade_z = clamp(1.0 - abs(world_pos.z) / 3.5, 0.0, 1.0);
    float light_fade = edge_fade_x * edge_fade_z;
    
    // Fade out caustics on vertical/underneath walls (only project on top-facing surfaces)
    vec3 world_normal = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
    float up_fade = clamp(world_normal.y, 0.0, 1.0);
    
    float final_intensity = caustics * caustic_intensity * up_fade * light_fade;
    
    ALBEDO = light_color.rgb * final_intensity;
    ALPHA = final_intensity;
}
