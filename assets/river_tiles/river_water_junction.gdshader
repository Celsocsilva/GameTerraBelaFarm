shader_type spatial;
// ENV-002 — Peça complementar de junção entre dois tiles do rio.
//
// Uma fatia do meio de um tile reto (margens contínuas + água) é desenhada
// sobre cada encontro de segmentos e esmaece nas duas pontas ao longo do
// fluxo. Cobre o recorte arredondado das margens e a linha clara da borda
// pintada de cada PNG, sem criar um novo degrau visível.
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

#include "res://assets/river_tiles/river_water_common.gdshaderinc"

// 0 = fluxo ao longo de V do quad (junção norte/sul), 1 = ao longo de U.
uniform int fade_axis = 0;
uniform float fade_fraction : hint_range(0.05, 0.5) = 0.32;

void fragment() {
    vec4 c = shade_water(UV);
    float a = fade_axis == 0 ? quad_uv.y : quad_uv.x;
    float fade = smoothstep(0.0, fade_fraction, a) * smoothstep(0.0, fade_fraction, 1.0 - a);
    ALBEDO = c.rgb;
    ALPHA = c.a * fade;
}
