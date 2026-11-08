// ENV-002 — Código comum da água animada (tiles, superfície e junções).
// Incluído por river_water.gdshader e river_water_junction.gdshader.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform bool surface_only = false;
uniform vec4 surface_color : source_color = vec4(0.23, 0.62, 0.90, 1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
uniform float water_threshold : hint_range(0.0, 0.5) = 0.06;
uniform float water_softness : hint_range(0.01, 0.5) = 0.14;
// Velocidade geral (1 = padrão). Movimento contínuo e discreto.
uniform float speed : hint_range(0.0, 3.0) = 1.0;
// Brilho das faixas de reflexo e variação lenta de luminosidade.
uniform float glint_strength : hint_range(0.0, 0.6) = 0.22;
uniform float brightness_variation : hint_range(0.0, 0.2) = 0.045;
// Deslocamento máximo da textura da água, em texels.
uniform float wobble_texels : hint_range(0.0, 4.0) = 1.4;
uniform vec2 texel_size = vec2(0.002, 0.002);
// Direção dominante (mundo XZ) do deslocamento das ondulações.
uniform vec2 flow_dir = vec2(0.35, 1.0);

// Recorte do PNG (peças retas encurtadas): UV final = UV * uv_scale + uv_offset.
uniform vec2 uv_offset = vec2(0.0);
uniform vec2 uv_scale = vec2(1.0);

varying vec3 world_pos;
// UV do quad antes do recorte (0..1), usado pelo esmaecimento das junções.
varying vec2 quad_uv;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    quad_uv = UV;
    UV = UV * uv_scale + uv_offset;
}

float water_mask(vec4 c) {
    return smoothstep(water_threshold, water_threshold + water_softness, c.b - c.r) * step(0.5, c.a);
}

// Soma de ondas suaves em -1..1, sem ruído de alta frequência (evita cintilação).
float ripples(vec2 p, float t) {
    vec2 f = normalize(flow_dir);
    float a = sin(dot(p, vec2(1.25, 0.65)) * 1.6 + dot(f, vec2(0.0, 1.0)) * t * 1.4);
    float b = sin(dot(p, vec2(-0.7, 1.4)) * 1.9 - t * 1.1);
    float c = sin(dot(p - f * t * 0.6, vec2(2.3, 1.7)) * 1.3);
    return a * 0.4 + b * 0.35 + c * 0.25;
}

// Reflexos em traços finos e ondulados de uma única família de ondas
// (sem malha cruzada), recortados por uma máscara lenta: aparecem e somem
// aos poucos em partes da água. Largura ~6 cm, sem pontos que piscam.
float glint_lines(vec2 p, float t) {
    vec2 q = p - normalize(flow_dir) * t * 0.3;
    float warp = sin(q.y * 1.1 + t * 0.3) * 1.5 + sin(q.x * 0.7 - t * 0.2) * 1.2;
    float c = sin(q.x * 1.3 + q.y * 2.0 + warp + t * 0.4);
    float lines = 1.0 - smoothstep(0.0, 0.16, abs(c));
    float patches = smoothstep(0.35, 0.95, 0.5 + 0.5 * sin(q.x * 0.45 + q.y * 0.6 + t * 0.2));
    // Quebra os traços em segmentos curtos (~0,5 m).
    float dashes = smoothstep(0.1, 0.8, 0.5 + 0.5 * sin(q.x * 3.1 - q.y * 1.9 + t * 0.5));
    return lines * patches * dashes;
}

vec4 shade_water(vec2 uv) {
    float t = TIME * speed;
    vec2 p = world_pos.xz;
    vec4 base;
    float water;
    if (surface_only) {
        base = surface_color;
        water = 1.0;
    } else {
        base = texture(albedo_tex, uv);
        water = water_mask(base);
        // Ondula a própria pintura da água, sem puxar pixels da margem.
        vec2 wobble = vec2(sin(p.y * 2.1 + t * 1.7), cos(p.x * 1.8 + t * 1.3)) * wobble_texels * texel_size;
        vec4 moved = texture(albedo_tex, uv + wobble);
        base.rgb = mix(base.rgb, moved.rgb, water * water_mask(moved));
    }
    float r = ripples(p, t);
    float glint = glint_lines(p, t) * glint_strength;
    float pulse = 1.0 + brightness_variation * sin(t * 0.8 + p.x * 0.23 - p.y * 0.17) + r * 0.03;
    vec3 water_rgb = base.rgb * pulse + vec3(0.88, 0.96, 1.0) * glint;
    return vec4(mix(base.rgb, water_rgb, water), base.a);
}
