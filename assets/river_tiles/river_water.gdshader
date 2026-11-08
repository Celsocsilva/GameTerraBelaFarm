shader_type spatial;
// ENV-002 — Água animada leve para os tiles ilustrados do rio.
//
// Modo tile (surface_only = false): desenha o PNG do tile e anima apenas os
// pixels de água (azul - vermelho acima do limiar). Margens, pedras e flores
// ficam intactas. Modo superfície (surface_only = true): faixa contínua de
// água sob os tiles (WaterSurface), visível só onde houver fresta entre eles.
//
// O padrão das ondulações usa coordenadas de MUNDO, então é contínuo entre
// tiles vizinhos e não muda de direção nas junções. Custo: 2 leituras de
// textura e alguns senos por fragmento, sem luz (unshaded).
render_mode unshaded, cull_disabled, depth_draw_opaque;

#include "res://assets/river_tiles/river_water_common.gdshaderinc"

void fragment() {
    vec4 c = shade_water(UV);
    ALBEDO = c.rgb;
    ALPHA = c.a;
    ALPHA_SCISSOR_THRESHOLD = alpha_cut;
}
