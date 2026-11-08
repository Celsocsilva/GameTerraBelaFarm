shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform sampler2D grass_base : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_flowers : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_pebbles : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_mixed : source_color, filter_linear_mipmap, repeat_enable;
uniform float tiles_per_meter = 0.38;

varying vec2 world_xz;

void vertex() {
    world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

float patch_weight(vec2 center, float radius, float fade) {
    return 1.0 - smoothstep(radius - fade, radius, distance(world_xz, center));
}

void fragment() {
    vec2 tiled_uv = world_xz * tiles_per_meter;
    vec3 color = texture(grass_base, tiled_uv).rgb;
    float flowers = max(patch_weight(vec2(-13.0, -5.0), 8.0, 3.0),
                        patch_weight(vec2(15.0, 12.0), 7.0, 3.0));
    float pebbles = max(patch_weight(vec2(12.0, -12.0), 7.0, 3.0),
                        patch_weight(vec2(-18.0, 16.0), 7.0, 3.0));
    float mixed = patch_weight(vec2(-17.0, 3.0), 6.0, 3.0);
    color = mix(color, texture(grass_flowers, tiled_uv).rgb, flowers * 0.60);
    color = mix(color, texture(grass_pebbles, tiled_uv).rgb, pebbles * 0.50);
    color = mix(color, texture(grass_mixed, tiled_uv).rgb, mixed * 0.35);
    color = mix(vec3(0.18, 0.43, 0.15), color, 0.58);
    ALBEDO = color;
    ROUGHNESS = 0.95;
}
