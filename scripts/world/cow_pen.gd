extends Node3D
class_name CowPen
## FARM-003: curral de vacas (topo esquerdo do mapa, ao norte do rio).
## - Frente (sul, +Z) e fundo (norte): a cerca de madeira do projeto (FenceRun,
##   coop_fence_02) de frente para a câmera; o portão (fence_gate_01) fica na
##   frente, perto do canto leste (lado da fazenda).
## - Laterais (leste/oeste), que correm no eixo Z: postes (fence_post) em pé de
##   frente para a câmera e duas travessas de madeira em 3D entre eles (a arte
##   de frente veria a lateral "de quina").
## - Colisão: 4 caixas em volta (o portão fica fechado; ninguém entra/sai).
## - Vacas: FarmCow, uma por cor de COLORS (7), andando e pastando lá dentro.

const COLORS := [
    "cow_black_white", "cow_dark_brown_white", "cow_light_brown_white",
    "cow_red_white", "cow_grey_white", "cow_golden_white", "cow_jersey",
]
const MILK_HOUSE_TEXTURE := preload("res://assets/buildings/dairy/milking_house_cozy.png")
const POST_TEXTURE := preload("res://assets/fences/fence_post.png")
const GATE_TEXTURE := preload("res://assets/fences/fence_gate_01.png")
## Travessa lateral: recorte da travessa da coop_fence_02 girado (tools/art).
const RAIL_TEXTURE := preload("res://assets/fences/fence_rail_side.png")
const VIEW_PITCH_DEGREES := 45.0
## Altura dos postes laterais e do portão (m, antes da compensação da câmera).
## FENCE-002: postes, portão e travessas 20% maiores (FenceRun.SIZE_SCALE).
const POST_HEIGHT := 1.05 * FenceRun.SIZE_SCALE
const SIDE_POST_SPACING := 1.6 * FenceRun.SIZE_SCALE
const GATE_WIDTH := 2.0 * FenceRun.SIZE_SCALE
const RAIL_HEIGHTS := [0.42 * FenceRun.SIZE_SCALE, 0.78 * FenceRun.SIZE_SCALE]
const RAIL_WIDTH := 0.16 * FenceRun.SIZE_SCALE
## FENCE-002: postes laterais com desvio e inclinação leves (feitos à mão).
const POST_JITTER := Vector2(0.08, 0.18)
const POST_TILT_DEGREES := 3.0
## Comprimento (m) de uma repetição da textura da travessa.
const RAIL_TILE := 1.6
const COLLISION_HEIGHT := 1.2
const COLLISION_THICKNESS := 0.35
## Folga entre a cerca e a área onde as vacas andam (a arte da vaca é larga).
const INNER_MARGIN := Vector2(1.3, 1.0)
## PEN-002 (09/11): pedido do Celso — alguns arbustos e pinheiros perto do
## curral. Posições fixas em relação ao retângulo do curral (frações de
## largura/profundidade + metros), fora da cerca: pinheiros atrás (norte) e a
## leste, arbustos na frente e nos cantos, nada na frente do portão.
const PINE_TEXTURE := preload("res://assets/decor/trees/tree_pine.png")
const BUSH_TEXTURES := [
    preload("res://assets/decor/vegetation/bush_white_flowers.png"),
    preload("res://assets/decor/vegetation/bush_red_berries.png"),
    preload("res://assets/decor/vegetation/bush_purple_flowers.png"),
]
## [fração x, fração z, desvio x (m), desvio z (m), largura (m)]
const PINE_SPOTS := [
    [0.18, 0.0, 0.0, -2.1, 3.0], [0.55, 0.0, 0.4, -2.3, 3.2], [0.86, 0.0, -0.2, -2.0, 2.8],
    # DAIRY-002: pinheiros do leste mais perto da cerca (o curral cresceu para
    # leste e a faixa de vegetação não pode engolir a fileira de pinheiros do norte).
    [1.0, 0.12, 1.0, 0.0, 3.1], [1.0, 0.5, 1.2, 0.0, 2.9], [1.0, 0.92, 0.9, 0.0, 3.0],
    [0.0, 1.0, 0.6, 2.5, 2.7],
]
const BUSH_SPOTS := [
    [0.12, 1.0, 0.0, 1.1, 1.3], [0.33, 1.0, 0.3, 1.2, 1.15], [0.52, 1.0, -0.2, 1.05, 1.4],
    [1.0, 1.0, 1.0, 1.0, 1.25], [1.0, 0.3, 0.8, 0.0, 1.2], [1.0, 0.72, 0.9, 0.3, 1.35],
    [0.35, 0.0, 0.0, -1.0, 1.1], [0.72, 0.0, 0.2, -1.1, 1.2],
]
## Até onde a vegetação vai além da cerca (FarmWorld bloqueia essa faixa para
## árvores/props aleatórios): esquerda, cima, direita, baixo.
const SURROUNDINGS_MARGIN := [1.2, 3.8, 1.9, 3.4]

var rect := Rect2()
## DAIRY-001: retângulos XZ (mundo) onde não entra arbusto/pinheiro em volta do
## curral (área do leite e plataforma de compra de vacas). Defina antes de setup.
var keep_clear: Array[Rect2] = []
## DAIRY-002: quantas vacas o curral cria no setup (as outras são compradas).
var initial_cows := COLORS.size()
## DAIRY-002/003: casinha de ordenha incorporada ao curral (pegada XZ, mundo),
## no canto nordeste. Rect2() = sem casinha.
var house_rect := Rect2()
## DAIRY-002: cocho de milho dentro do curral (as vacas não pisam nele).
var feeder_rect := Rect2()
var milk_house: MeshInstance3D
var gate_x := 0.0
var cows: Array[FarmCow] = []
var gate: MeshInstance3D

func setup(area: Rect2, gate_center_x: float) -> void:
    rect = area
    gate_x = gate_center_x
    _build_fences()
    _build_collision()
    _build_cows()
    _build_surroundings()

func get_inner_rect() -> Rect2:
    return rect.grow_individual(-INNER_MARGIN.x, -INNER_MARGIN.y - 0.4, -INNER_MARGIN.x, -INNER_MARGIN.y)

## Onde as vacas andam: o miolo do curral. DAIRY-003: a casinha (canto
## nordeste) e o cocho ficam de fora pelos retângulos de get_cow_avoid_rects().
func get_cow_rect() -> Rect2:
    return get_inner_rect()

## Retângulos (XZ) onde as vacas não escolhem destino nem nascem.
func get_cow_avoid_rects() -> Array[Rect2]:
    var avoid: Array[Rect2] = []
    if house_rect.has_area():
        # A vaca é larga (2,6 m): folga maior dos lados.
        avoid.append(house_rect.grow_individual(1.5, 1.0, 1.5, 1.2))
    if feeder_rect.has_area():
        avoid.append(feeder_rect.grow_individual(1.2, 1.0, 1.2, 1.0))
    return avoid

## Ponto livre (fora da casinha/cocho) mais perto de `p`, dentro da área das vacas.
func free_cow_point(p: Vector3) -> Vector3:
    var area := get_cow_rect()
    var point := Vector3(clampf(p.x, area.position.x, area.end.x), 0.0, clampf(p.z, area.position.y, area.end.y))
    for blocked in get_cow_avoid_rects():
        if blocked.has_point(Vector2(point.x, point.z)):
            # Empurra para oeste da área bloqueada (o lado sempre livre do curral).
            point.x = maxf(area.position.x, blocked.position.x - 0.3)
    return point

static func screen_stretch() -> float:
    return 1.0 / cos(deg_to_rad(VIEW_PITCH_DEGREES))

func _build_fences() -> void:
    # Fundo (norte).
    _add_run("FenceNorth", rect.position.x, rect.end.x, rect.position.y)
    # Frente (sul) com o vão do portão.
    var gate_left := gate_x - GATE_WIDTH * 0.5
    var gate_right := gate_x + GATE_WIDTH * 0.5
    _add_run("FenceSouthWest", rect.position.x, gate_left, rect.end.y)
    _add_run("FenceSouthEast", gate_right, rect.end.x, rect.end.y)
    if house_rect.has_area():
        _build_milk_house()
    gate = _upright_quad("Gate", GATE_TEXTURE, GATE_WIDTH, Vector3(gate_x, 0.0, rect.end.y + 0.01))
    add_child(gate)
    _add_side("FenceWest", rect.position.x)
    _add_side("FenceEast", rect.end.x)

func _add_run(label: String, from_x: float, to_x: float, z: float) -> void:
    if to_x - from_x < 0.5:
        return
    var run := FenceRun.new()
    run.name = label
    run.length = to_x - from_x
    run.position = Vector3((from_x + to_x) * 0.5, 0.0, z)
    add_child(run)

## DAIRY-003: casinha de ordenha (arte enviada pelo Celso), em pé de frente
## para a câmera, no canto superior direito (nordeste) do curral; a base fica
## na frente da pegada (house_rect.end.y) e o telhado sobe sobre a cerca de trás.
func _build_milk_house() -> void:
    milk_house = _upright_quad("MilkHouse", MILK_HOUSE_TEXTURE, house_rect.size.x, Vector3(house_rect.get_center().x, 0.0, house_rect.end.y))
    add_child(milk_house)

## Lateral no eixo Z: postes de frente para a câmera + 2 travessas (faixas
## deitadas com a madeira da cerca, vistas de cima pela câmera a 45°).
func _add_side(label: String, x: float) -> void:
    var side := Node3D.new()
    side.name = label
    add_child(side)
    var length := rect.size.y
    var count := maxi(2, int(round(length / SIDE_POST_SPACING)) + 1)
    var post_width := POST_HEIGHT * float(POST_TEXTURE.get_width()) / float(POST_TEXTURE.get_height())
    for index in count:
        var z := rect.position.y + length * float(index) / float(count - 1)
        # Os cantos já têm o poste da cerca de frente/fundo.
        if index == 0 or index == count - 1:
            continue
        var h1 := FenceRun._hash(x, z, index, 5.0) * 2.0 - 1.0
        var h2 := FenceRun._hash(x, z, index, 6.0) * 2.0 - 1.0
        var post := _upright_quad("Post_%02d" % index, POST_TEXTURE, post_width * (1.0 + h2 * 0.06), Vector3(x + h1 * POST_JITTER.x, 0.0, z + h2 * POST_JITTER.y))
        post.rotation.z = deg_to_rad(h1 * POST_TILT_DEGREES)
        side.add_child(post)
    var material := StandardMaterial3D.new()
    material.albedo_texture = RAIL_TEXTURE
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
    material.alpha_scissor_threshold = 0.4
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.texture_repeat = true
    material.uv1_scale = Vector3(1.0, length / RAIL_TILE, 1.0)
    for h in RAIL_HEIGHTS:
        var rail := MeshInstance3D.new()
        rail.name = "Rail_%d" % int(h * 100)
        var quad := QuadMesh.new()
        quad.size = Vector2(RAIL_WIDTH, length)
        rail.mesh = quad
        rail.material_override = material
        rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        rail.rotation_degrees.x = -90.0
        rail.position = Vector3(x, float(h) * screen_stretch() * 0.92, rect.get_center().y)
        side.add_child(rail)

## Quad em pé, de frente para a câmera (+Z), base no chão, altura compensada
## pela inclinação de 45° (como FenceRun, placas e caixas).
func _upright_quad(label: String, texture: Texture2D, width: float, at: Vector3) -> MeshInstance3D:
    var mesh := MeshInstance3D.new()
    mesh.name = label
    var quad := QuadMesh.new()
    var height := width * float(texture.get_height()) / float(texture.get_width())
    quad.size = Vector2(width, height)
    mesh.mesh = quad
    var material := StandardMaterial3D.new()
    material.albedo_texture = texture
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
    material.alpha_scissor_threshold = 0.5
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    mesh.material_override = material
    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var stretch := screen_stretch()
    mesh.scale = Vector3(1.0, stretch, 1.0)
    mesh.position = at + Vector3(0.0, height * 0.5 * stretch * 0.92, 0.0)
    return mesh

## Retângulo XZ do curral + vegetação em volta (PEN-002).
static func get_surroundings_rect(area: Rect2) -> Rect2:
    var m: Array = SURROUNDINGS_MARGIN
    return area.grow_individual(m[0], m[1], m[2], m[3])

## Pontos XZ (mundo) de pinheiros e arbustos em volta do curral, com largura.
func get_surroundings_points(kind: String) -> Array[Vector3]:
    var spots: Array = PINE_SPOTS if kind == "pine" else BUSH_SPOTS
    var result: Array[Vector3] = []
    for spot in spots:
        var x: float = rect.position.x + rect.size.x * float(spot[0]) + float(spot[2])
        var z: float = rect.position.y + rect.size.y * float(spot[1]) + float(spot[3])
        # Nada na frente do portão (vão de 1,5 m para cada lado).
        if kind == "bush" and absf(x - gate_x) < GATE_WIDTH * 0.5 + 1.5 and z > rect.end.y:
            continue
        var blocked := false
        for clear in keep_clear:
            if clear.grow(float(spot[4]) * 0.5).has_point(Vector2(x, z)):
                blocked = true
                break
        if blocked:
            continue
        result.append(Vector3(x, 0.0, z) + Vector3(0.0, float(spot[4]), 0.0))
    return result

func _build_surroundings() -> void:
    var group := Node3D.new()
    group.name = "Surroundings"
    add_child(group)
    var index := 0
    for point in get_surroundings_points("pine"):
        group.add_child(_billboard("Pine_%02d" % index, PINE_TEXTURE, point.y, Vector3(point.x, 0.0, point.z), true))
        index += 1
    index = 0
    for point in get_surroundings_points("bush"):
        var texture: Texture2D = BUSH_TEXTURES[index % BUSH_TEXTURES.size()]
        group.add_child(_billboard("Bush_%02d" % index, texture, point.y, Vector3(point.x, 0.0, point.z), false))
        index += 1

## Arte em pé virada para a câmera (como a decoração do CozyEnvironment).
## Pinheiros têm um tronco sólido; arbustos são só visuais.
func _billboard(label: String, texture: Texture2D, width: float, at: Vector3, solid: bool) -> Node3D:
    var root := StaticBody3D.new() if solid else Node3D.new()
    root.name = label
    root.position = at
    var sprite := Sprite3D.new()
    sprite.name = "Art"
    sprite.texture = texture
    sprite.pixel_size = width / float(texture.get_width())
    sprite.centered = false
    sprite.offset = Vector2(-texture.get_width() * 0.5, 0.0)
    sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    sprite.shaded = false
    sprite.double_sided = true
    sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
    sprite.alpha_scissor_threshold = 0.2
    sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(sprite)
    if solid:
        var collision := CollisionShape3D.new()
        var shape := CylinderShape3D.new()
        shape.radius = width * 0.2
        shape.height = 1.8
        collision.shape = shape
        collision.position.y = 0.9
        root.add_child(collision)
    return root

func _build_collision() -> void:
    var body := StaticBody3D.new()
    body.name = "PenCollision"
    add_child(body)
    var c := rect.get_center()
    var t := COLLISION_THICKNESS
    var boxes := [
        [Vector3(c.x, 0.0, rect.position.y), Vector3(rect.size.x + t, COLLISION_HEIGHT, t)],
        [Vector3(c.x, 0.0, rect.end.y), Vector3(rect.size.x + t, COLLISION_HEIGHT, t)],
        [Vector3(rect.position.x, 0.0, c.y), Vector3(t, COLLISION_HEIGHT, rect.size.y + t)],
        [Vector3(rect.end.x, 0.0, c.y), Vector3(t, COLLISION_HEIGHT, rect.size.y + t)],
    ]
    for index in boxes.size():
        var shape := BoxShape3D.new()
        shape.size = boxes[index][1]
        var collision := CollisionShape3D.new()
        collision.name = "Side_%d" % index
        collision.shape = shape
        collision.position = boxes[index][0] + Vector3(0.0, COLLISION_HEIGHT * 0.5, 0.0)
        body.add_child(collision)

func _build_cows() -> void:
    var inner := get_cow_rect()
    var columns := 4
    for index in mini(initial_cows, COLORS.size()):
        var cow := FarmCow.new()
        cow.name = "Cow_%s" % COLORS[index]
        cow.setup(COLORS[index], inner, 7001 + index * 131)
        # Começam espalhadas numa grade 4 x 2 (com desvio), sem sobreposição.
        var col := index % columns
        var row := int(index / columns)
        var fx := (float(col) + 0.5 + (0.5 if row == 1 else 0.0)) / float(columns + (1 if row == 1 else 0))
        cow.avoid = get_cow_avoid_rects()
        cow.position = free_cow_point(Vector3(lerpf(inner.position.x, inner.end.x, fx), 0.0, lerpf(inner.position.y, inner.end.y, 0.25 + 0.5 * row)))
        add_child(cow)
        cows.append(cow)
    for cow in cows:
        cow.herd = cows

## DAIRY-001: vaca comprada. Entra pelo portão (nasce logo dentro dele) e sai
## andando, cada uma com uma cor de COLORS. Retorna a vaca nova (null no teto).
func add_cow() -> FarmCow:
    # Teto de vacas do curral (DairyConfig.MAX_COWS = 7, uma de cada cor).
    if cows.size() >= DairyConfig.MAX_COWS:
        return null
    var inner := get_cow_rect()
    var index := cows.size()
    var color: String = COLORS[index % COLORS.size()]
    var cow := FarmCow.new()
    cow.name = "Cow_%s_%02d" % [color, index + 1]
    cow.setup(color, inner, 7001 + index * 131)
    cow.avoid = get_cow_avoid_rects()
    cow.position = free_cow_point(Vector3(gate_x, 0.0, inner.end.y - 0.2))
    add_child(cow)
    cows.append(cow)
    for other in cows:
        other.herd = cows
    cow.celebrate()
    return cow

func get_cow_count() -> int:
    return cows.size()
