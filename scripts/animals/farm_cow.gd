extends Node3D
class_name FarmCow
## FARM-003: vaca animada do curral (CowPen). Sprite em pé virado para a câmera
## (billboard, como os props) com os 8 frames da arte do projeto:
## 01 parada, 02 piscando, 03-06 andando, 07 pastando, 08 feliz.
## Estados: IDLE (parada, pisca de vez em quando), WALK (anda até um ponto
## sorteado dentro do curral), GRAZE (cabeça baixa pastando) e HAPPY (rápido).
## A arte olha para a esquerda (-X); andando para a direita o sprite espelha.
## Sorteios com semente própria: o mesmo curral se comporta igual a cada carga.

enum State { IDLE, WALK, GRAZE, HAPPY }

const FRAME_FILES := ["01_idle_01", "02_blink", "03_walk_01", "04_walk_02", "05_walk_03", "06_walk_04", "07_graze", "08_happy"]
const WALK_FRAMES := [2, 3, 4, 5]
const WALK_FPS := 7.0
## Largura da arte na tela (m). O fazendeiro é uma cápsula de 1,8 m.
const WIDTH := 2.6
const SPEED := 0.85

## Pasta com os frames limpos (assets/animals/cows/game/<cor>).
@export var color_id: String = "cow_black_white"
## Área (XZ do mundo) onde a vaca pode andar.
var bounds := Rect2(-2, -2, 4, 4)
var state: State = State.IDLE
var target := Vector3.ZERO
## Outras vacas do curral, para não escolher destino colado nelas.
var herd: Array[FarmCow] = []
var sprite: Sprite3D
var frames: Array[Texture2D] = []
var walked_distance := 0.0
var states_seen: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _anim_time := 0.0
var _blink_timer := 2.0
var _pixel_size := 0.004

static func frame_path(color: String, index: int) -> String:
    return "res://assets/animals/cows/game/%s/%s_%s.png" % [color, color, FRAME_FILES[index]]

func setup(color: String, area: Rect2, seed_value: int) -> void:
    color_id = color
    bounds = area
    _rng.seed = seed_value

func _ready() -> void:
    for index in FRAME_FILES.size():
        frames.append(load(frame_path(color_id, index)) as Texture2D)
    sprite = Sprite3D.new()
    sprite.name = "Art"
    sprite.centered = false
    sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    sprite.shaded = false
    sprite.double_sided = true
    sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
    sprite.alpha_scissor_threshold = 0.35
    sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _pixel_size = WIDTH / float(frames[0].get_width())
    sprite.pixel_size = _pixel_size
    add_child(sprite)
    _set_frame(0)
    _enter(State.GRAZE if _rng.randf() < 0.5 else State.IDLE)

func _set_frame(index: int) -> void:
    var texture := frames[index]
    sprite.texture = texture
    # Pés no chão: a base do PNG fica na origem (o PNG tem ~4% de margem).
    sprite.offset = Vector2(-texture.get_width() * 0.5, -texture.get_height() * 0.04)

func get_frame_index() -> int:
    return frames.find(sprite.texture)

func _enter(new_state: State) -> void:
    state = new_state
    states_seen[new_state] = true
    _anim_time = 0.0
    match new_state:
        State.IDLE:
            _timer = _rng.randf_range(1.5, 3.5)
            _set_frame(0)
        State.GRAZE:
            _timer = _rng.randf_range(3.0, 6.0)
            _set_frame(6)
        State.HAPPY:
            _timer = 0.9
            _set_frame(7)
        State.WALK:
            target = _pick_target()
            _timer = 12.0

func _pick_target() -> Vector3:
    var best := Vector3(bounds.get_center().x, 0.0, bounds.get_center().y)
    for attempt in 10:
        var p := Vector3(_rng.randf_range(bounds.position.x, bounds.end.x), 0.0, _rng.randf_range(bounds.position.y, bounds.end.y))
        if Vector2(p.x - position.x, p.z - position.z).length() < 1.5:
            continue
        var free := true
        for other in herd:
            if other != self and Vector2(other.position.x - p.x, other.position.z - p.z).length() < 2.0:
                free = false
                break
        best = p
        if free:
            break
    return best

func _process(delta: float) -> void:
    _anim_time += delta
    _timer -= delta
    match state:
        State.WALK:
            var to_target := Vector3(target.x - position.x, 0.0, target.z - position.z)
            var step := SPEED * delta
            if to_target.length() <= step or _timer <= 0.0:
                position = Vector3(target.x, position.y, target.z) if to_target.length() <= step else position
                var roll := _rng.randf()
                _enter(State.GRAZE if roll < 0.55 else (State.HAPPY if roll < 0.65 else State.IDLE))
                return
            var dir := to_target.normalized()
            position += dir * step
            walked_distance += step
            if absf(dir.x) > 0.15:
                sprite.flip_h = dir.x > 0.0
            _set_frame(WALK_FRAMES[int(_anim_time * WALK_FPS) % WALK_FRAMES.size()])
        State.IDLE:
            _blink_timer -= delta
            if _blink_timer <= 0.0:
                _set_frame(1)
                if _blink_timer <= -0.14:
                    _set_frame(0)
                    _blink_timer = _rng.randf_range(1.6, 3.4)
            if _timer <= 0.0:
                _enter(State.WALK)
        State.GRAZE:
            # Mastigando: sobe e desce de leve.
            sprite.position.y = absf(sin(_anim_time * 5.0)) * 0.03
            if _timer <= 0.0:
                sprite.position.y = 0.0
                _enter(State.WALK if _rng.randf() < 0.75 else State.IDLE)
        State.HAPPY:
            sprite.position.y = absf(sin(_anim_time * 7.0)) * 0.12
            if _timer <= 0.0:
                sprite.position.y = 0.0
                _enter(State.WALK)
