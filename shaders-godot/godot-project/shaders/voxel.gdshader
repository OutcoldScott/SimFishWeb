// Faceted voxel shading - no actual lights, just face-based brightness ramps.
//
// This is the classic "voxel game" look (Minecraft, Cube World): each face of a
// cube gets a different brightness multiplier based on its world-space normal.
// Top faces brightest, bottom faces dimmest, sides in between. The palette
// quantize shader at the end of the pipeline is what enforces the limited
// color set - this shader just gives us 3D-readable shading.
//
// Set `albedo` per-instance via ShaderMaterial.set_shader_parameter("albedo", color).

shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Per-instance tint multiplier. Plants + world set this on individual
// voxels via set_instance_shader_parameter() to signal CO₂ / iron /
// biofilm states without having to duplicate the underlying material.
//
// IMPORTANT: Godot 4 does NOT honor the declared default for `instance
// uniform` when the property has never been set on a given instance —
// it returns vec4(0,0,0,0). Multiplying that into ALBEDO blacks out
// every voxel that never explicitly opted into a tint, which is the
// vast majority. We treat alpha < 0.01 as the "unset" sentinel and
// fall back to identity. Callers send Color values, which default
// to alpha=1, so a real tint of any RGB always reads as "set."
instance uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    vec3 n = normalize(NORMAL);
    float f;
    if (n.y > 0.7) {
        f = 1.00;        // top
    } else if (n.y < -0.7) {
        f = 0.50;        // bottom
    } else if (abs(n.x) > 0.7) {
        f = 0.82;        // +X / -X sides
    } else {
        f = 0.68;        // +Z / -Z sides
    }
    vec3 effective_tint = (tint.a > 0.01) ? tint.rgb : vec3(1.0);
    ALBEDO = albedo.rgb * effective_tint * f;
}
