extends Node3D
class_name MilkStation
## DAIRY-001: área do leite em frente ao portão do curral.
##
## DAIRY-002: cada vaca do curral (CowPen.cows, inclusive as compradas) espera
## 20 s e depois, em intervalos aleatórios, come uma espiga do cocho (a espiga
## voa do cocho até ela) e dá uma garrafa por espiga: a garrafa voa da vaca,
## por cima da cerca, até a pilha de caixas de leite (TomatoPile com item &"milk", grade
## 3 x 3 por camada). A cada 8 garrafas forma-se uma caixa. O fazendeiro pisa
## na área e recolhe as caixas para a mochila (mesmo fluxo das parcelas dos
## ajudantes); depois é o de sempre: mochila -> balcão -> clientes.
## Com a pilha cheia as vacas param (nada se perde nem passa da capacidade).

signal bottle_produced(cow: FarmCow)
## Uma vaca quis comer e o cocho estava vazio.
signal hungry()

const CORN_COB := preload("res://assets/harvest/corn_cob.png")
const COB_HEIGHT := 0.6
const COB_FLIGHT_TIME := 0.55

const BOTTLE_FLIGHT_TIME := 0.7
const BOTTLE_FLIGHT_HEIGHT := 2.6
const BOTTLE_HEIGHT := 0.75
const COW_UDDER_HEIGHT := 0.9
const VIEW_PITCH_DEGREES := 45.0

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform vec4 fill_color : source_color = vec4(0.937, 0.894, 0.792, 1.0);
uniform vec4 plank_color : source_color = vec4(0.851, 0.761, 0.6, 1.0);
uniform vec4 border_color : source_color = vec4(0.42, 0.247, 0.133, 1.0);
uniform vec4 header_color : source_color = vec4(0.36, 0.62, 0.86, 1.0);
uniform float radius = 0.12;
uniform float border = 0.035;
uniform float header = 0.16;

float box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = box(p, vec2(0.5), radius);
	if (d > 0.0) { discard; }
	// Piso de tábuas claras (faixas horizontais na tela).
	float plank = step(0.5, fract(UV.y * 6.0));
	vec3 c = mix(fill_color.rgb, plank_color.rgb, plank * 0.45);
	// Faixa azul do título na FRENTE (lado da câmera): as caixas sobem na
	// tela e cobririam uma faixa no fundo.
	if (UV.y > 1.0 - header) { c = header_color.rgb; }
	if (d > -border) { c = border_color.rgb; }
	ALBEDO = c;
}
"""

var pen: CowPen
var pile: TomatoPile
## DAIRY-002: cocho de milho de onde as vacas comem.
var trough: FeedTrough
## Registro para testes: {"cow", "corn"} por refeição.
var meal_log: Array[Dictionary] = []
var corn_eaten := 0
var _rng := RandomNumberGenerator.new()
var _reserved_bottles := 0
var _cob_flyers: Array = []
var rect := Rect2()
## Registro para testes: {"cow", "from", "to"} por garrafa lançada.
var bottle_log: Array[Dictionary] = []
var enabled := true
var _timers: Dictionary = {}
var _in_flight := 0
var _flyers: Array = []
var _title: Label3D
var _camera: Camera3D

static func screen_stretch() -> float:
    return 1.0 / sin(deg_to_rad(VIEW_PITCH_DEGREES))

func setup(area: Rect2, p_pen: CowPen, units_per_crate: int, p_trough: FeedTrough = null) -> void:
    rect = area
    pen = p_pen
    trough = p_trough
    _rng.seed = 20261110
    position = Vector3(rect.get_center().x, 0.0, rect.get_center().y)
    _build_floor()
    pile = TomatoPile.new()
    pile.name = "MilkPile"
    pile.item_id = DairyConfig.ITEM
    pile.centered = true
    pile.grid_layout = true
    pile.max_crates = DairyConfig.PILE_MAX_CRATES
    # TomatoPile se posiciona pelo retângulo em coordenadas do mundo.
    pile.top_level = true
    add_child(pile)
    var pile_rect := Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.84))
    pile.setup(pile_rect, units_per_crate)

func _build_floor() -> void:
    _title = MilkStation.build_floor(self, rect.size, Color(0.36, 0.62, 0.86))
    _refresh_title()

## Piso de tábuas com faixa colorida na frente e um título deitado nela
## (área do leite e cocho). Retorna o Label3D do título.
static func build_floor(parent: Node3D, size: Vector2, header: Color) -> Label3D:
    var quad := MeshInstance3D.new()
    quad.name = "Floor"
    var mesh := QuadMesh.new()
    mesh.size = size
    quad.mesh = mesh
    var shader := Shader.new()
    shader.code = SHADER_CODE
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("header_color", header)
    material.render_priority = -1
    quad.material_override = material
    quad.rotation_degrees.x = -90.0
    quad.position.y = 0.03
    quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(quad)
    var title := Label3D.new()
    title.name = "Title"
    title.font = UiStyle.font()
    title.font_size = 84
    title.pixel_size = 0.0045
    title.modulate = UiStyle.TEXT_CREAM
    title.outline_modulate = UiStyle.OUTLINE_BROWN
    title.outline_size = 18
    title.shaded = false
    title.double_sided = true
    title.alpha_cut = Label3D.ALPHA_CUT_DISCARD
    title.render_priority = 2
    title.outline_render_priority = 1
    title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
    title.rotation_degrees.x = -90.0
    title.scale = Vector3(1.0, screen_stretch(), 1.0)
    title.position = Vector3(0.0, 0.05, size.y * 0.5 - size.y * 0.08)
    parent.add_child(title)
    return title

func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and _title:
        _refresh_title.call_deferred()

func _refresh_title() -> void:
    _title.text = tr("MILK_AREA_TITLE")

func get_title_text() -> String:
    return _title.text if _title else ""

func contains_point(world_pos: Vector3) -> bool:
    return rect.grow(0.4).has_point(Vector2(world_pos.x, world_pos.z))

## Garrafas que ainda cabem na pilha, descontando as que estão voando e as
## das refeições em andamento (espiga ainda no ar).
func get_free_bottles() -> int:
    return maxi(0, pile.get_free_capacity() - _in_flight - _reserved_bottles) if pile else 0

func get_bottles_in_flight() -> int:
    return _in_flight

func _process(delta: float) -> void:
    tick(delta)

## Avança a produção (separado de _process para testes determinísticos).
## DAIRY-002: cada vaca espera DairyConfig.MILK_WARMUP desde que chegou; depois,
## em intervalos aleatórios, come milho do cocho e dá leite na proporção.
func tick(delta: float) -> void:
    if not enabled or pen == null or pile == null:
        return
    for cow in pen.cows:
        if not is_instance_valid(cow):
            continue
        if not _timers.has(cow):
            _timers[cow] = DairyConfig.MILK_WARMUP
        var left: float = _timers[cow] - delta
        if left <= 0.0:
            if try_feed(cow):
                left = _rng.randf_range(DairyConfig.EAT_INTERVAL_MIN, DairyConfig.EAT_INTERVAL_MAX)
            else:
                left = DairyConfig.HUNGRY_RETRY
        _timers[cow] = left

## Segundos até a próxima refeição da vaca (aquecimento incluso). -1 = sem registro.
func get_cow_timer(cow: FarmCow) -> float:
    return float(_timers.get(cow, -1.0))

## Uma refeição: tira milho do cocho (a espiga voa até a vaca) e a vaca dá
## o leite correspondente. Falha sem milho ou sem espaço para as garrafas.
func try_feed(cow: FarmCow) -> bool:
    var bottles := DairyConfig.CORN_PER_MEAL * DairyConfig.MILK_PER_CORN
    if trough == null or trough.get_stored_total() < DairyConfig.CORN_PER_MEAL or get_free_bottles() < bottles:
        if trough != null and trough.get_stored_total() < DairyConfig.CORN_PER_MEAL:
            hungry.emit()
        return false
    var eaten := trough.take_corn(DairyConfig.CORN_PER_MEAL)
    if eaten <= 0:
        return false
    corn_eaten += eaten
    meal_log.append({"cow": cow, "corn": eaten})
    _reserved_bottles += eaten * DairyConfig.MILK_PER_CORN
    var from := trough.get_corn_origin()
    if is_inside_tree() and cow and cow.is_inside_tree():
        _launch_cob(from, cow, eaten)
    else:
        _after_meal(cow, eaten)
    return true

func _after_meal(cow: FarmCow, eaten: int) -> void:
    _reserved_bottles = maxi(0, _reserved_bottles - eaten * DairyConfig.MILK_PER_CORN)
    for i in eaten * DairyConfig.MILK_PER_CORN:
        produce_from(cow)

func _launch_cob(from: Vector3, cow: FarmCow, eaten: int) -> void:
    var flyer := Sprite3D.new()
    flyer.name = "CornCob_%d" % meal_log.size()
    flyer.top_level = true
    flyer.texture = CORN_COB
    flyer.pixel_size = COB_HEIGHT / float(CORN_COB.get_height())
    flyer.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    flyer.shaded = false
    flyer.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
    flyer.render_priority = 6
    add_child(flyer)
    flyer.global_position = from
    flyer.set_meta("cow", cow)
    flyer.set_meta("eaten", eaten)
    _cob_flyers.append(flyer)
    var to := cow.global_position + Vector3(0.0, COW_UDDER_HEIGHT, 0.0)
    var tween := create_tween()
    tween.tween_method(_move_bottle.bind(flyer, from, to), 0.0, 1.0, COB_FLIGHT_TIME)
    tween.tween_callback(_land_cob.bind(flyer, cow, eaten))

func _land_cob(flyer, cow: FarmCow, eaten: int) -> void:
    # Já resolvida por finish_flights(): não conta duas vezes.
    if not _cob_flyers.has(flyer):
        return
    _cob_flyers.erase(flyer)
    if is_instance_valid(flyer):
        flyer.queue_free()
    if is_instance_valid(cow):
        _after_meal(cow, eaten)
    else:
        _reserved_bottles = maxi(0, _reserved_bottles - eaten * DairyConfig.MILK_PER_CORN)

## Uma garrafa da vaca `cow` para a pilha. Fora da árvore (testes) entra direto.
func produce_from(cow: FarmCow) -> bool:
    if pile == null or pile.get_free_capacity() - _in_flight <= 0:
        return false
    var from := cow.global_position + Vector3(0.0, COW_UDDER_HEIGHT, 0.0) if cow and cow.is_inside_tree() else global_position
    var to := pile.to_global(pile.get_slot_local(pile.get_crate_count())) + Vector3(0.0, 0.4, 0.0) if pile.is_inside_tree() else global_position
    bottle_log.append({"cow": cow, "from": from, "to": to})
    bottle_produced.emit(cow)
    if cow and is_instance_valid(cow):
        cow.celebrate()
    if not is_inside_tree():
        pile.add_units(1)
        return true
    _launch_bottle(from, to)
    return true

func _launch_bottle(from: Vector3, to: Vector3) -> void:
    var flyer := Sprite3D.new()
    flyer.name = "MilkBottle_%d" % bottle_log.size()
    flyer.top_level = true
    flyer.texture = ItemArt.MILK_BOTTLE
    flyer.pixel_size = BOTTLE_HEIGHT / float(ItemArt.MILK_BOTTLE.get_height())
    flyer.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    flyer.shaded = false
    flyer.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
    flyer.render_priority = 6
    add_child(flyer)
    flyer.global_position = from
    _flyers.append(flyer)
    _in_flight += 1
    var tween := create_tween()
    tween.tween_method(_move_bottle.bind(flyer, from, to), 0.0, 1.0, BOTTLE_FLIGHT_TIME)
    tween.tween_callback(_land_bottle.bind(flyer))

func _move_bottle(t: float, flyer, from: Vector3, to: Vector3) -> void:
    if is_instance_valid(flyer):
        flyer.global_position = from.lerp(to, t) + Vector3(0.0, 4.0 * t * (1.0 - t) * BOTTLE_FLIGHT_HEIGHT, 0.0)

func _land_bottle(flyer) -> void:
    if not _flyers.has(flyer):
        return
    _flyers.erase(flyer)
    if is_instance_valid(flyer):
        flyer.queue_free()
    _in_flight = maxi(0, _in_flight - 1)
    pile.add_units(1)

func get_flying_bottle_count() -> int:
    return _flyers.size()

## Pousa na hora todas as garrafas no ar (testes e capturas).
func finish_flights() -> void:
    # Espigas no ar: a refeição termina agora (as garrafas saem e pousam abaixo).
    var cobs := _cob_flyers.duplicate()
    _cob_flyers.clear()
    for flyer in cobs:
        if is_instance_valid(flyer):
            var cow = flyer.get_meta("cow")
            var eaten := int(flyer.get_meta("eaten"))
            flyer.queue_free()
            if is_instance_valid(cow):
                _after_meal(cow, eaten)
            else:
                _reserved_bottles = maxi(0, _reserved_bottles - eaten * DairyConfig.MILK_PER_CORN)
    var count := _flyers.size()
    for flyer in _flyers:
        if is_instance_valid(flyer):
            flyer.queue_free()
    _flyers.clear()
    _in_flight = 0
    if count > 0:
        pile.add_units(count)
