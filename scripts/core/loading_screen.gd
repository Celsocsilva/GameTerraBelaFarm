extends Control
class_name LoadingScreen
## LOAD-001: tela de carregamento com a arte do jogo e barra de progresso.
## É a cena principal: a mesma arte aparece no boot splash do Godot, então a
## troca splash -> esta tela é contínua. Carrega a fazenda em thread, cria o
## mundo por baixo desta tela (o _ready do mundo é a parte mais pesada) e só
## então some com um fade.

const TARGET_SCENE := "res://scenes/world/farm_world.tscn"
const ART := preload("res://assets/ui/loading/loading_screen.png")
## Tempo mínimo na tela, para a barra não piscar em aparelhos rápidos.
const MIN_SECONDS := 1.4
const FADE_SECONDS := 0.35
## Parte da barra reservada para o carregamento dos arquivos; o resto é a
## montagem do mundo.
const LOAD_SHARE := 0.85
const BAR_WIDTH_FRACTION := 0.46
const BAR_HEIGHT := 26.0

var progress_bar: ProgressBar
var percent_label: Label
var _layer: CanvasLayer
var _displayed := 0.0
var _target := 0.0
var _elapsed := 0.0
var _state := 0 # 0 carregando, 1 montando o mundo, 2 saindo
var _world: Node

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    # Fica numa camada acima do HUD enquanto o mundo é montado por baixo.
    _layer = CanvasLayer.new()
    _layer.name = "LoadingLayer"
    _layer.layer = 100
    add_child(_layer)
    var root := Control.new()
    root.name = "Root"
    root.mouse_filter = Control.MOUSE_FILTER_STOP
    _layer.add_child(root)
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var background := ColorRect.new()
    background.color = Color(0.96, 0.72, 0.42)
    root.add_child(background)
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var art := TextureRect.new()
    art.name = "Art"
    art.texture = ART
    art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    root.add_child(art)
    art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    progress_bar = ProgressBar.new()
    progress_bar.name = "ProgressBar"
    progress_bar.min_value = 0.0
    progress_bar.max_value = 1.0
    progress_bar.step = 0.0
    progress_bar.show_percentage = false
    progress_bar.add_theme_stylebox_override("background", _box(Color(0.24, 0.13, 0.05, 0.78), Color(1.0, 0.93, 0.75), 3))
    progress_bar.add_theme_stylebox_override("fill", _box(Color(0.42, 0.74, 0.22), Color(0.0, 0.0, 0.0, 0.0), 0))
    root.add_child(progress_bar)
    progress_bar.anchor_left = 0.5 - BAR_WIDTH_FRACTION * 0.5
    progress_bar.anchor_right = 0.5 + BAR_WIDTH_FRACTION * 0.5
    progress_bar.anchor_top = 0.9
    progress_bar.anchor_bottom = 0.9
    progress_bar.offset_top = -BAR_HEIGHT * 0.5
    progress_bar.offset_bottom = BAR_HEIGHT * 0.5

    percent_label = Label.new()
    percent_label.name = "Percent"
    percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    percent_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    percent_label.add_theme_color_override("font_color", Color(1.0, 0.98, 0.9))
    percent_label.add_theme_color_override("font_outline_color", Color(0.24, 0.13, 0.05))
    percent_label.add_theme_constant_override("outline_size", 6)
    percent_label.add_theme_font_size_override("font_size", 18)
    progress_bar.add_child(percent_label)
    percent_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _set_bar(0.0)

    ResourceLoader.load_threaded_request(TARGET_SCENE, "PackedScene", true)

func _box(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = fill
    box.border_color = border
    box.set_border_width_all(border_width)
    box.set_corner_radius_all(int(BAR_HEIGHT * 0.5))
    box.anti_aliasing = true
    return box

func _set_bar(value: float) -> void:
    progress_bar.value = value
    percent_label.text = "%d%%" % int(round(value * 100.0))

func _process(delta: float) -> void:
    _elapsed += delta
    match _state:
        0:
            var progress := []
            var status := ResourceLoader.load_threaded_get_status(TARGET_SCENE, progress)
            if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
                _target = float(progress[0]) * LOAD_SHARE if progress.size() > 0 else _target
            elif status == ResourceLoader.THREAD_LOAD_LOADED:
                _target = LOAD_SHARE
                if _displayed >= LOAD_SHARE - 0.01:
                    _build_world()
            else:
                push_error("LoadingScreen: falha ao carregar %s" % TARGET_SCENE)
                set_process(false)
                return
        1:
            _target = 1.0
            if _displayed >= 0.995 and _elapsed >= MIN_SECONDS:
                _finish()
    # Barra suave: anda rápido, mas nunca salta.
    _displayed = move_toward(_displayed, _target, delta * 1.6)
    _set_bar(_displayed)

func _build_world() -> void:
    _state = 1
    var packed := ResourceLoader.load_threaded_get(TARGET_SCENE) as PackedScene
    _world = packed.instantiate()
    # Irmão desta tela, para continuar existindo quando ela for liberada.
    get_tree().root.add_child.call_deferred(_world)

func _finish() -> void:
    _state = 2
    set_process(false)
    get_tree().current_scene = _world
    var tween := create_tween()
    tween.tween_property(_layer.get_node("Root"), "modulate:a", 0.0, FADE_SECONDS)
    tween.tween_callback(queue_free)
