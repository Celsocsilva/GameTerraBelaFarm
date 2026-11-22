extends Node3D
class_name FarmPaths
## FARM-005 (10/11): caminhos de terra do terreno, ligando balcão, canteiros,
## pontes, casa, curral/leite e construções.
##
## Cada caminho é uma lista de pontos XZ (mundo) suavizada (Catmull-Rom) e
## desenhada como uma fita no chão, com pontas arredondadas. A terra vem de
## assets/terrain/path/path_dirt_seamless.png (miolo de terra da arte
## assets/terrain/path_cross.png tornado contínuo por tools/art/gen_path_dirt.py).
## Duas passadas: a borda (mais escura e um pouco mais larga) e a terra por
## cima, assim os cruzamentos não mostram emenda. A borda de cada passada tem
## ruído, para o caminho não parecer régua.
## Os caminhos são só visuais (não bloqueiam ninguém); a decoração (árvores,
## props, construções) é que fica longe deles (is_near / get_block_rects).

const DIRT_TEXTURE := preload("res://assets/terrain/path/path_dirt_seamless.png")
const SUBDIVISIONS := 8
const SAMPLE_STEP := 0.5
const GROUND_Y := 0.014
## Largura da terra em relação à borda escura.
const DIRT_RATIO := 0.86

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform sampler2D dirt : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tile_m = 2.4;
uniform float edge_noise = 0.16;
uniform float salt = 0.0;
varying vec3 wpos;
varying vec4 info;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	info = COLOR;
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + salt) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	// info.r: distância à ponta (m / 8); info.g: meia largura (m / 4).
	float half_w = info.g * 4.0;
	float end_d = info.r * 8.0;
	float across = abs(UV.x - 0.5) * 2.0;
	if (end_d < half_w) {
		across = length(vec2(across, 1.0 - end_d / half_w));
	}
	float n = vnoise(wpos.xz * 1.3) * 0.65 + vnoise(wpos.xz * 3.7) * 0.35;
	float edge = 1.0 - edge_noise + (n - 0.5) * edge_noise * 1.6;
	float a = 1.0 - smoothstep(edge - 0.07, edge, across);
	// Z comprimido pela câmera a 45°: a textura não fica esticada na tela.
	vec3 c = texture(dirt, vec2(wpos.x, wpos.z * 0.7071) / tile_m).rgb * tint.rgb;
	float inner = smoothstep(edge - 0.32, edge - 0.04, across);
	c *= mix(1.0, 0.86, inner);
	ALBEDO = c;
	ALPHA = a * tint.a;
}
"""

## Caminhos: [{"name", "points": PackedVector2Array, "width"}].
var routes: Array[Dictionary] = []
## Pontos suavizados de cada caminho (mesma ordem de routes).
var samples: Array[PackedVector2Array] = []

static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
    var t2 := t * t
    var t3 := t2 * t
    return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

static func smooth(points: PackedVector2Array) -> PackedVector2Array:
    var dense := PackedVector2Array()
    if points.size() < 2:
        return points
    for i in points.size() - 1:
        var p0 := points[maxi(i - 1, 0)]
        var p1 := points[i]
        var p2 := points[i + 1]
        var p3 := points[mini(i + 2, points.size() - 1)]
        for s in SUBDIVISIONS:
            dense.append(_catmull(p0, p1, p2, p3, float(s) / float(SUBDIVISIONS)))
    dense.append(points[points.size() - 1])
    # Reamostra com passo fixo (fita com triângulos regulares).
    var out := PackedVector2Array([dense[0]])
    var carry := 0.0
    for i in range(1, dense.size()):
        var a := dense[i - 1]
        var b := dense[i]
        var seg := a.distance_to(b)
        var d := SAMPLE_STEP - carry
        while d <= seg:
            out.append(a.lerp(b, d / seg))
            d += SAMPLE_STEP
        carry = seg - (d - SAMPLE_STEP)
    if out[out.size() - 1].distance_to(dense[dense.size() - 1]) > 0.05:
        out.append(dense[dense.size() - 1])
    return out

func setup(route_list: Array) -> void:
    var rim_material := _material(Color(0.72, 0.5, 0.3, 0.95), 0.0, 0)
    var dirt_material := _material(Color(1.0, 0.93, 0.82, 1.0), 0.22, 1)
    for route in route_list:
        var points: PackedVector2Array = route["points"]
        var width := float(route.get("width", 2.0))
        var line := smooth(points)
        routes.append(route)
        samples.append(line)
        var root := Node3D.new()
        root.name = "Path_%s" % String(route.get("name", str(routes.size())))
        add_child(root)
        root.add_child(_ribbon("Rim", line, width * 0.5, rim_material, GROUND_Y))
        root.add_child(_ribbon("Dirt", line, width * 0.5 * DIRT_RATIO, dirt_material, GROUND_Y + 0.002))

func _material(tint: Color, salt: float, priority: int) -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = SHADER_CODE
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("dirt", DIRT_TEXTURE)
    material.set_shader_parameter("tint", tint)
    material.set_shader_parameter("salt", salt)
    material.render_priority = priority
    return material

func _ribbon(node_name: String, line: PackedVector2Array, half_w: float, material: Material, y: float) -> MeshInstance3D:
    # Estende as pontas meia largura para a ponta arredondada sair além do ponto final.
    var pts := PackedVector2Array(line)
    var n := pts.size()
    var head := (pts[0] - pts[1]).normalized()
    var tail := (pts[n - 1] - pts[n - 2]).normalized()
    pts.insert(0, pts[0] + head * half_w)
    pts.append(pts[pts.size() - 1] + tail * half_w)
    var lengths := PackedFloat32Array([0.0])
    for i in range(1, pts.size()):
        lengths.append(lengths[i - 1] + pts[i - 1].distance_to(pts[i]))
    var total := lengths[lengths.size() - 1]
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var left: Array[Vector3] = []
    var right: Array[Vector3] = []
    var info: Array[Color] = []
    for i in pts.size():
        var dir: Vector2
        if i == 0:
            dir = pts[1] - pts[0]
        elif i == pts.size() - 1:
            dir = pts[i] - pts[i - 1]
        else:
            dir = pts[i + 1] - pts[i - 1]
        dir = dir.normalized()
        var side := Vector2(-dir.y, dir.x) * half_w
        left.append(Vector3(pts[i].x + side.x, y, pts[i].y + side.y))
        right.append(Vector3(pts[i].x - side.x, y, pts[i].y - side.y))
        var end_d := minf(lengths[i], total - lengths[i])
        info.append(Color(clampf(end_d / 8.0, 0.0, 1.0), half_w / 4.0, 0.0, 1.0))
    for i in pts.size() - 1:
        var quad := [[left[i], 0.0, i], [right[i], 1.0, i], [left[i + 1], 0.0, i + 1], [right[i], 1.0, i], [right[i + 1], 1.0, i + 1], [left[i + 1], 0.0, i + 1]]
        for v in quad:
            st.set_color(info[v[2]])
            st.set_uv(Vector2(v[1], lengths[v[2]]))
            st.set_normal(Vector3.UP)
            st.add_vertex(v[0])
    var mesh := MeshInstance3D.new()
    mesh.name = node_name
    mesh.mesh = st.commit()
    mesh.material_override = material
    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return mesh

## Menor distância (m) de um ponto XZ ao eixo de algum caminho.
func distance_to(point: Vector2) -> float:
    var best := INF
    for line in samples:
        for i in range(1, line.size()):
            var closest := Geometry2D.get_closest_point_to_segment(point, line[i - 1], line[i])
            best = minf(best, closest.distance_to(point))
    return best

## O ponto está sobre um caminho ou a menos de `margin` da borda dele?
func is_near(point: Vector2, margin: float) -> bool:
    for index in samples.size():
        var half_w := float(routes[index].get("width", 2.0)) * 0.5
        var line := samples[index]
        for i in range(1, line.size()):
            if Geometry2D.get_closest_point_to_segment(point, line[i - 1], line[i]).distance_to(point) < half_w + margin:
                return true
    return false

## Retângulos XZ que cobrem os caminhos (com folga), para quem só sabe evitar retângulos.
func get_block_rects(margin: float) -> Array[Rect2]:
    var rects: Array[Rect2] = []
    for index in samples.size():
        var r := float(routes[index].get("width", 2.0)) * 0.5 + margin
        var line := samples[index]
        for i in range(0, line.size(), 2):
            rects.append(Rect2(line[i] - Vector2(r, r), Vector2(r, r) * 2.0))
    return rects
