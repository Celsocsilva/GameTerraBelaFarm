extends Node3D
class_name BorderForest
## MAP-003 (10/11): floresta das faixas novas do mapa (esquerda, direita e
## topo, ~15% cada). Duas artes do Celso: árvore de copa redonda
## (tree_round_leafy) e pinheiro alto (tree_pine_tall).
##
## Disposição orgânica, sempre igual a cada carga (sorteio por hash da posição):
## - grade com passo STEP e desvio de até JITTER em cada eixo;
## - manchas: uma "nuvem" de baixa frequência decide clareiras (sem árvores),
##   bosques fechados e a espécie dominante de cada mancha (pinheiros juntos,
##   copas redondas juntas, misturadas nas bordas);
## - tamanho variando ±18% e espelhamento aleatório;
## - nada na água do rio, nas margens/pontes, nos retângulos bloqueados nem a
##   menos de MIN_SPACING de outra árvore.
## Cada árvore tem um tronco sólido (cilindro); a copa é só visual.

const ROUND_TEXTURE := preload("res://assets/decor/trees/tree_round_leafy.png")
const PINE_TEXTURE := preload("res://assets/decor/trees/tree_pine_tall.png")
## FOREST-002 (10/11): mais densa (passo 3,1 -> 2,5) e árvores 20% maiores.
const STEP := 2.5
const JITTER := 1.0
const MIN_SPACING := 1.9
## Largura na tela (m) de cada espécie antes da variação de tamanho.
const SIZE_SCALE := 1.2
const ROUND_WIDTH := 3.6 * SIZE_SCALE
const PINE_WIDTH := 2.4 * SIZE_SCALE
const SIZE_JITTER := 0.18
## Folga da borda do mapa (as copas não saem do terreno).
const EDGE_MARGIN := 0.9
## Folga da faixa antiga (as árvores não invadem o mapa de antes).
const OLD_MAP_MARGIN := 0.6
const CLEARING_THRESHOLD := 0.22
## Faixa junto à borda externa do mapa sem clareiras (a borda fica fechada).
const EDGE_BAND := 5.0
const TRUNK_RADIUS := 0.35

## Pontos plantados: x, z = posição; y = largura (m).
var points: Array[Vector3] = []
## Espécie de cada ponto (&"round" ou &"pine"), mesma ordem de points.
var kinds: Array[StringName] = []
var trees: Array[Node3D] = []

static func _hash(x: float, z: float, salt: float) -> float:
    return fposmod(sin(x * 12.9898 + z * 78.233 + salt * 37.719) * 43758.5453, 1.0)

## Ruído suave de baixa frequência (manchas de ~12 m) por interpolação de hash.
static func _cloud(x: float, z: float, salt: float) -> float:
    var cell := 12.0
    var gx := floorf(x / cell)
    var gz := floorf(z / cell)
    var fx := smoothstep(0.0, 1.0, x / cell - gx)
    var fz := smoothstep(0.0, 1.0, z / cell - gz)
    var a := _hash(gx, gz, salt)
    var b := _hash(gx + 1.0, gz, salt)
    var c := _hash(gx, gz + 1.0, salt)
    var d := _hash(gx + 1.0, gz + 1.0, salt)
    return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)

func setup(map_rect: Rect2, old_map: Rect2, river: RiverSystem, blocked: Array[Rect2]) -> void:
    var area := map_rect.grow(-EDGE_MARGIN)
    var inner := old_map.grow(OLD_MAP_MARGIN)
    var z := area.position.y
    var row := 0
    while z <= area.end.y:
        var x := area.position.x + (STEP * 0.5 if row % 2 == 1 else 0.0)
        while x <= area.end.x:
            _try_point(x, z, area, inner, river, blocked)
            x += STEP
        z += STEP * 0.9
        row += 1
    _build_trees()

func _try_point(gx: float, gz: float, area: Rect2, inner: Rect2, river: RiverSystem, blocked: Array[Rect2]) -> void:
    var p := Vector2(gx, gz) + Vector2(_hash(gx, gz, 1.0) * 2.0 - 1.0, _hash(gx, gz, 2.0) * 2.0 - 1.0) * JITTER
    if not area.has_point(p) or inner.has_point(p):
        return
    var density := _cloud(p.x, p.y, 3.0)
    # Clareiras: manchas de baixa densidade ficam vazias; nas médias, falhas.
    # Na faixa da borda externa não há clareira, para fechar a borda.
    var near_edge := not area.grow(-EDGE_BAND).has_point(p)
    if not near_edge and (density < CLEARING_THRESHOLD or _hash(gx, gz, 4.0) > density + 0.35):
        return
    if river != null and (river.is_point_in_water(Vector3(p.x, 0.0, p.y), 1.6) or river.blocks_decoration(Vector3(p.x, 0.0, p.y), 0.8)):
        return
    for rect in blocked:
        if rect.has_point(p):
            return
    for other in points:
        if Vector2(other.x, other.z).distance_to(p) < MIN_SPACING:
            return
    var species := _cloud(p.x, p.y, 5.0) + (_hash(gx, gz, 6.0) - 0.5) * 0.35
    var kind: StringName = &"pine" if species > 0.5 else &"round"
    var base := PINE_WIDTH if kind == &"pine" else ROUND_WIDTH
    var width := base * (1.0 + (_hash(gx, gz, 7.0) * 2.0 - 1.0) * SIZE_JITTER)
    points.append(Vector3(p.x, width, p.y))
    kinds.append(kind)

func _build_trees() -> void:
    for index in points.size():
        var point := points[index]
        var texture: Texture2D = PINE_TEXTURE if kinds[index] == &"pine" else ROUND_TEXTURE
        var root := StaticBody3D.new()
        root.name = "%s_%03d" % ["Pine" if kinds[index] == &"pine" else "Round", index]
        root.position = Vector3(point.x, 0.0, point.z)
        var sprite := Sprite3D.new()
        sprite.name = "Art"
        sprite.texture = texture
        sprite.pixel_size = point.y / float(texture.get_width())
        sprite.centered = false
        sprite.offset = Vector2(-texture.get_width() * 0.5, 0.0)
        sprite.flip_h = _hash(point.x, point.z, 8.0) < 0.5
        sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        sprite.shaded = false
        sprite.double_sided = true
        sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
        sprite.alpha_scissor_threshold = 0.2
        sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
        sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        root.add_child(sprite)
        var collision := CollisionShape3D.new()
        var shape := CylinderShape3D.new()
        shape.radius = TRUNK_RADIUS
        shape.height = 1.8
        collision.shape = shape
        collision.position.y = 0.9
        root.add_child(collision)
        add_child(root)
        trees.append(root)

func get_count(kind: StringName) -> int:
    return kinds.count(kind)
