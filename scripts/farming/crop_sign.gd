extends Node3D
class_name CropSign
## Placa de madeira fincada na frente de um terreno de plantio (FV-PROPS-001).
## A arte e o nome escolhem-se pelo tipo de cultura (crop_id): tomate, milho ou
## abóbora. O nome vai na faixa em branco da placa num Label3D com a fonte do
## projeto (UiStyle.font) e é traduzido (CROP_*: pt_BR/es/en).
##
## A placa é um quadro de pé (plano XY, de frente para a câmera em +Z) com a
## altura compensada pela inclinação da câmera de 45°, como as caixas do balcão:
## na tela aparece na proporção exata do PNG. Sem colisão: não bloqueia o
## fazendeiro nem os clientes.

## Arte, chave de tradução e faixa em branco (fração da altura do PNG, de cima
## para baixo; largura útil como fração da largura) de cada cultura.
const CROPS := {
    &"tomato": {
        "texture": preload("res://assets/props/signs/sign_crop_tomato.png"),
        "key": "CROP_TOMATO",
        "band_center": 0.505,
        "band_width": 0.70,
    },
    &"corn": {
        "texture": preload("res://assets/props/signs/sign_crop_corn.png"),
        "key": "CROP_CORN",
        "band_center": 0.585,
        "band_width": 0.62,
    },
    &"pumpkin": {
        "texture": preload("res://assets/props/signs/sign_crop_pumpkin.png"),
        "key": "CROP_PUMPKIN",
        "band_center": 0.535,
        "band_width": 0.72,
    },
}
## Inclinação da câmera do jogo (FarmWorld: camera_height == camera_distance).
const VIEW_PITCH_DEGREES := 45.0
const TEXT_COLOR := Color(0.36, 0.20, 0.08)
const OUTLINE_COLOR := Color(1.0, 0.95, 0.82)
const FONT_SIZE := 96
const OUTLINE_SIZE := 18

## Largura da placa (m).
@export_range(0.5, 4.0, 0.05) var sign_width: float = 2.3
@export var crop_id: StringName = &"tomato"

var _board: MeshInstance3D
var _label: Label3D

static func get_supported_crops() -> Array:
    return CROPS.keys()

static func has_crop(id: StringName) -> bool:
    return CROPS.has(id)

## Compensação de altura: um quadro de pé visto a 45° encurta por cos(45°).
static func screen_stretch() -> float:
    return 1.0 / cos(deg_to_rad(VIEW_PITCH_DEGREES))

func _ready() -> void:
    _board = MeshInstance3D.new()
    _board.name = "SignBoard"
    _board.mesh = QuadMesh.new()
    _board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(_board)
    _label = Label3D.new()
    _label.name = "CropName"
    _label.font = UiStyle.font()
    _label.font_size = FONT_SIZE
    _label.modulate = TEXT_COLOR
    _label.outline_modulate = OUTLINE_COLOR
    _label.outline_size = OUTLINE_SIZE
    _label.shaded = false
    _label.double_sided = true
    _label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
    _label.render_priority = 2
    _label.outline_render_priority = 1
    _label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
    add_child(_label)
    set_crop(crop_id)

## Troca a cultura da placa (arte + nome). Culturas desconhecidas mantêm a atual.
func set_crop(id: StringName) -> void:
    if not CROPS.has(id):
        push_warning("CropSign: cultura sem placa: %s" % id)
        return
    crop_id = id
    if not is_node_ready():
        return
    var entry: Dictionary = CROPS[id]
    var texture: Texture2D = entry["texture"]
    var stretch := screen_stretch()
    var height := sign_width * float(texture.get_height()) / float(texture.get_width())
    var quad := _board.mesh as QuadMesh
    quad.size = Vector2(sign_width, height)
    # O pé da estaca (borda de baixo do PNG) fica no chão.
    _board.scale = Vector3(1.0, stretch, 1.0)
    _board.position = Vector3(0.0, height * 0.5 * stretch, 0.0)
    _board.material_override = _material(texture)
    var band_from_bottom := 1.0 - float(entry["band_center"])
    _label.scale = Vector3(1.0, stretch, 1.0)
    _label.position = Vector3(0.0, height * band_from_bottom * stretch, 0.02)
    _refresh_text()

func get_crop_id() -> StringName:
    return crop_id

func get_text() -> String:
    return _label.text if _label else ""

func get_texture() -> Texture2D:
    return (_board.material_override as StandardMaterial3D).albedo_texture if _board else null

func get_board() -> MeshInstance3D:
    return _board

func get_label() -> Label3D:
    return _label

## Largura do texto na tela (m), para conferir se cabe na faixa em branco.
func get_text_width() -> float:
    if _label == null:
        return 0.0
    return _label.font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _label.font_size).x * _label.pixel_size

func get_band_width() -> float:
    return sign_width * float(CROPS[crop_id]["band_width"])

func _refresh_text() -> void:
    var entry: Dictionary = CROPS[crop_id]
    _label.text = tr(String(entry["key"]))
    # Ajusta o tamanho para o nome mais longo caber na faixa (ex.: "Calabaza").
    var text_px := _label.font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
    var max_pixel := sign_width * 0.0016
    var fit := get_band_width() * 0.92 / maxf(text_px + OUTLINE_SIZE, 1.0)
    _label.pixel_size = minf(max_pixel, fit)

func _material(texture: Texture2D) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_texture = texture
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
    material.alpha_scissor_threshold = 0.5
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    return material

func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
        _refresh_text.call_deferred()
