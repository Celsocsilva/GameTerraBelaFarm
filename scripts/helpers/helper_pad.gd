extends Node3D
class_name HelperPad
## Plataforma de contratação do ajudante (FV-HELPER-001), NO CHÃO, logo antes
## da parcela de 10%. É um quadrado de cantos arredondados (quadrado na tela:
## o lado Z é alongado por 1/sin 45°, como a parcela) no estilo UI v5: creme,
## borda marrom, título, "Grau n/5", 5 marcadores de graduação e quanto falta.
##
## Com o fazendeiro em cima, o saldo dele sai um dinheiro por vez: cada maço
## voa das mãos dele até a plataforma, a Wallet desconta 1 e o preenchimento
## verde sobe. Ao completar o preço (100 para contratar) o ajudante é
## contratado; a plataforma passa a cobrar a próxima graduação.
## Sair da plataforma PAUSA: o que já foi pago fica guardado (HelperHiring.paid)
## e a cobrança continua de onde parou. Nada é devolvido nem cobrado a mais.

signal purchased(grade: int)
## Fazendeiro em cima, sem saldo para continuar.
signal out_of_money(missing: int)

const MONEY_TEXTURE := preload("res://assets/sales/money_bundle.png")
const VIEW_PITCH_DEGREES := 45.0
const SCREEN_STRETCH := 1.0 / sin(deg_to_rad(VIEW_PITCH_DEGREES))
## Lado (X) da plataforma; o lado Z é SIDE * SCREEN_STRETCH.
const SIDE := 3.4
## Espera antes do primeiro dinheiro (evita cobrar ao passar raspando).
const START_DELAY := 0.35
## Intervalo entre dois dinheiros: 100 dinheiros em ~3 s.
const PAY_INTERVAL := 0.03
const FLIGHT_TIME := 0.45
const FLIGHT_HEIGHT := 1.9
const BUNDLE_WIDTH := 0.8
const HANDS_HEIGHT := 1.1

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
uniform vec4 fill_color : source_color = vec4(1.0, 0.953, 0.839, 1.0);
uniform vec4 border_color : source_color = vec4(0.42, 0.247, 0.133, 1.0);
uniform vec4 header_color : source_color = vec4(0.949, 0.71, 0.267, 1.0);
uniform vec4 progress_color : source_color = vec4(0.427, 0.733, 0.235, 1.0);
uniform vec4 pip_on : source_color = vec4(0.427, 0.733, 0.235, 1.0);
uniform vec4 pip_off : source_color = vec4(0.902, 0.824, 0.678, 1.0);
uniform vec4 pip_border : source_color = vec4(0.42, 0.247, 0.133, 1.0);
uniform float radius = 0.17;
uniform float border = 0.05;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform int grade = 0;
uniform int max_grade = 5;
uniform float pulse = 0.0;

float box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = box(p, vec2(0.5), radius);
	if (d > 0.0) { discard; }
	vec3 c = fill_color.rgb;
	// Faixa do título (amarela) no topo.
	if (UV.y < 0.25) { c = header_color.rgb; }
	// Preenchimento verde que sobe de baixo conforme o pagamento.
	if (UV.y > 1.0 - progress) { c = mix(c, progress_color.rgb, 0.55); }
	// Marcadores de graduação: quadradinhos arredondados.
	float pip_w = 0.11;
	float gap = 0.045;
	float row_w = float(max_grade) * pip_w + float(max_grade - 1) * gap;
	for (int i = 0; i < max_grade; i++) {
		vec2 center = vec2(0.5 - row_w * 0.5 + pip_w * 0.5 + float(i) * (pip_w + gap), 0.52);
		float pd = box(UV - center, vec2(pip_w * 0.5), 0.03);
		if (pd < 0.0) {
			c = (i < grade) ? pip_on.rgb : pip_off.rgb;
			if (pd > -0.014) { c = pip_border.rgb; }
		}
	}
	if (d > -border) { c = border_color.rgb; }
	ALBEDO = c * (1.0 + pulse * 0.25);
}
"""

var hiring: HelperHiring
var wallet: Wallet
## Pegada XZ da plataforma (mundo).
var rect := Rect2()
## Registro para testes: um item por dinheiro que voou {"from", "to"}.
var flight_log: Array[Dictionary] = []

var _material: ShaderMaterial
var _title: Label3D
var _grade_label: Label3D
var _cost_label: Label3D
var _cost_icon: Sprite3D
var _flyers: Array = []
var _on_pad_time := 0.0
var _pay_accumulator := 0.0
var _farmer_on_pad := false
var _warned_no_money := false
var _pulse_tween: Tween

static func get_size() -> Vector2:
    return Vector2(SIDE, SIDE * SCREEN_STRETCH)

func setup(center_xz: Vector2, p_hiring: HelperHiring, p_wallet: Wallet) -> void:
    hiring = p_hiring
    wallet = p_wallet
    var size := get_size()
    rect = Rect2(center_xz - size * 0.5, size)
    position = Vector3(center_xz.x, 0.035, center_xz.y)
    hiring.grade_changed.connect(func(_g: int) -> void: _refresh())
    hiring.paid_changed.connect(func(_p: int, _c: int) -> void: _refresh())
    _refresh()

func _ready() -> void:
    var size := get_size()
    var quad := MeshInstance3D.new()
    quad.name = "RoundedSquare"
    var mesh := QuadMesh.new()
    mesh.size = size
    quad.mesh = mesh
    var shader := Shader.new()
    shader.code = SHADER_CODE
    _material = ShaderMaterial.new()
    _material.shader = shader
    _material.render_priority = -1
    quad.material_override = _material
    quad.rotation_degrees.x = -90.0
    quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(quad)
    # Textos deitados no chão; Z alongado para lerem na proporção certa na tela.
    _title = _make_label("Title", 0.125, 96, UiStyle.TEXT_CREAM, UiStyle.OUTLINE_BROWN, 22)
    _grade_label = _make_label("GradeLabel", 0.37, 72, UiStyle.TEXT_BROWN, Color(0, 0, 0, 0), 0)
    _cost_label = _make_label("CostLabel", 0.78, 104, UiStyle.TEXT_BROWN, UiStyle.TEXT_CREAM, 14)
    _cost_label.position.x = size.x * 0.12
    _cost_icon = Sprite3D.new()
    _cost_icon.name = "CostIcon"
    _cost_icon.texture = MONEY_TEXTURE
    _cost_icon.pixel_size = 0.62 / float(MONEY_TEXTURE.get_width())
    _cost_icon.shaded = false
    _cost_icon.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
    _cost_icon.rotation_degrees.x = -90.0
    _cost_icon.scale = Vector3(1.0, SCREEN_STRETCH, 1.0)
    _cost_icon.position = Vector3(-size.x * 0.26, 0.02, _uv_to_z(0.78))
    _cost_icon.render_priority = 1
    add_child(_cost_icon)
    _refresh()

func _make_label(label_name: String, uv_y: float, font_size: int, color: Color, outline: Color, outline_size: int) -> Label3D:
    var label := Label3D.new()
    label.name = label_name
    label.font = UiStyle.font()
    label.font_size = font_size
    label.pixel_size = 0.0045
    label.modulate = color
    label.outline_modulate = outline
    label.outline_size = outline_size
    label.shaded = false
    label.double_sided = true
    label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
    label.render_priority = 2
    label.outline_render_priority = 1
    label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
    label.rotation_degrees.x = -90.0
    label.scale = Vector3(1.0, SCREEN_STRETCH, 1.0)
    label.position = Vector3(0.0, 0.02, _uv_to_z(uv_y))
    add_child(label)
    return label

## UV do quad (0 = borda de trás, -Z, topo da tela) para Z local.
func _uv_to_z(uv_y: float) -> float:
    return (uv_y - 0.5) * get_size().y

func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
        _refresh.call_deferred()

func contains_point(world_pos: Vector3) -> bool:
    return rect.grow(0.15).has_point(Vector2(world_pos.x, world_pos.z))

func is_farmer_on_pad() -> bool:
    return _farmer_on_pad

## Chame por frame com a posição do fazendeiro. Retorna quantos dinheiros
## foram pagos neste frame.
func process_farmer_position(world_pos: Vector3, delta: float) -> int:
    _farmer_on_pad = contains_point(world_pos)
    if not _farmer_on_pad or hiring == null or wallet == null or hiring.is_max():
        _on_pad_time = 0.0
        _pay_accumulator = 0.0
        _warned_no_money = false
        return 0
    _on_pad_time += delta
    if _on_pad_time < START_DELAY:
        return 0
    if wallet.get_balance() <= 0:
        if not _warned_no_money:
            _warned_no_money = true
            out_of_money.emit(hiring.get_remaining_cost())
        return 0
    _pay_accumulator += delta
    var paid_now := 0
    var hands := world_pos + Vector3(0.0, HANDS_HEIGHT, 0.0)
    while _pay_accumulator >= PAY_INTERVAL and not hiring.is_max():
        _pay_accumulator -= PAY_INTERVAL
        var grade_before := hiring.grade
        if hiring.pay(wallet, 1) <= 0:
            _pay_accumulator = 0.0
            break
        paid_now += 1
        _launch_bundle(hands)
        if hiring.grade > grade_before:
            _play_pulse()
            purchased.emit(hiring.grade)
            # A próxima graduação recomeça depois de uma nova pausa curta.
            _on_pad_time = 0.0
            _pay_accumulator = 0.0
            break
    return paid_now

func _refresh() -> void:
    if _material == null:
        return
    var grade := hiring.grade if hiring else 0
    var is_max := hiring != null and hiring.is_max()
    var cost := HelperConfig.next_cost(grade)
    var paid := hiring.paid if hiring else 0
    _material.set_shader_parameter("grade", grade)
    _material.set_shader_parameter("max_grade", HelperConfig.MAX_GRADE)
    _material.set_shader_parameter("progress", 1.0 if is_max else clampf(float(paid) / float(maxi(cost, 1)), 0.0, 1.0))
    _title.text = tr("HELPER_TITLE")
    _grade_label.text = tr("HELPER_GRADE") % [grade, HelperConfig.MAX_GRADE]
    _cost_icon.visible = not is_max
    _cost_label.text = tr("HELPER_MAX") if is_max else UiStyle.format_int(maxi(cost - paid, 0))
    _cost_label.position.x = 0.0 if is_max else get_size().x * 0.12

func _launch_bundle(from: Vector3) -> void:
    if not is_inside_tree():
        return
    # Pousa no ícone de dinheiro da plataforma (frente, lado da câmera), para
    # o maço não sumir atrás do fazendeiro parado no meio.
    var to := _cost_icon.global_position + Vector3(0.0, 0.1, 0.0)
    var flyer := Node3D.new()
    flyer.name = "PaidMoney_%d" % flight_log.size()
    flyer.top_level = true
    add_child(flyer)
    flyer.global_position = from
    var sprite := Sprite3D.new()
    sprite.name = "MoneySprite"
    sprite.texture = MONEY_TEXTURE
    sprite.pixel_size = BUNDLE_WIDTH / float(MONEY_TEXTURE.get_width())
    sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    sprite.shaded = false
    sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
    sprite.render_priority = 4
    flyer.add_child(sprite)
    _flyers.append(flyer)
    flight_log.append({"from": from, "to": to})
    var tween := create_tween()
    tween.tween_method(_move_flyer.bind(flyer, from, to), 0.0, 1.0, FLIGHT_TIME)
    tween.tween_callback(_land.bind(flyer))

func _move_flyer(t: float, flyer, from: Vector3, to: Vector3) -> void:
    if is_instance_valid(flyer):
        flyer.global_position = from.lerp(to, t) + Vector3(0.0, 4.0 * t * (1.0 - t) * FLIGHT_HEIGHT, 0.0)
        flyer.scale = Vector3.ONE * lerpf(1.0, 0.6, t)

func _land(flyer) -> void:
    _flyers.erase(flyer)
    if is_instance_valid(flyer):
        flyer.queue_free()

func get_flying_count() -> int:
    return _flyers.size()

## Termina os voos na hora (testes e capturas).
func finish_flights() -> void:
    for flyer in _flyers:
        if is_instance_valid(flyer):
            flyer.queue_free()
    _flyers.clear()

func _play_pulse() -> void:
    if not is_inside_tree():
        return
    if _pulse_tween and _pulse_tween.is_valid():
        _pulse_tween.kill()
    _pulse_tween = create_tween()
    _pulse_tween.tween_method(func(v: float) -> void: _material.set_shader_parameter("pulse", v), 1.0, 0.0, 0.6)

## Para testes: estado exibido.
func get_title_text() -> String:
    return _title.text

func get_grade_text() -> String:
    return _grade_label.text

func get_cost_text() -> String:
    return _cost_label.text

func get_progress() -> float:
    return float(_material.get_shader_parameter("progress"))

func get_grade_shown() -> int:
    return int(_material.get_shader_parameter("grade"))
