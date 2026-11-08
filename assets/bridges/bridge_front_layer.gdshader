shader_type spatial;
// ENV-002 — Camada frontal das pontes (corrimão, postes e lanternas da frente).
//
// Cada faixa é um quad perpendicular à visão da câmera, posicionado na
// profundidade da borda frontal do tabuleiro. Assim o fazendeiro que está
// SOBRE a ponte fica atrás do corrimão frontal, e quem está na margem à frente
// continua desenhado por cima da ponte. Só os pixels dentro de front_polygon
// (coordenadas UV do PNG inteiro) são desenhados; o resto é descartado.
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 uv_offset = vec2(0.0);
uniform vec2 uv_scale = vec2(1.0);
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
uniform int polygon_size = 0;
uniform vec2 front_polygon[32];

varying vec2 atlas_uv;

void vertex() {
    atlas_uv = UV * uv_scale + uv_offset;
}

bool inside_polygon(vec2 p) {
    bool inside = false;
    int count = min(polygon_size, 32);
    int j = count - 1;
    for (int i = 0; i < count; i++) {
        vec2 a = front_polygon[i];
        vec2 b = front_polygon[j];
        if (((a.y > p.y) != (b.y > p.y)) && (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x)) {
            inside = !inside;
        }
        j = i;
    }
    return inside;
}

void fragment() {
    vec4 c = texture(albedo_tex, atlas_uv);
    if (!inside_polygon(atlas_uv)) {
        c.a = 0.0;
    }
    ALBEDO = c.rgb;
    ALPHA = c.a;
    ALPHA_SCISSOR_THRESHOLD = alpha_cut;
}
