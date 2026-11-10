extends Node3D
class_name FenceRun
## Trecho reto de cerca de madeira com a arte do projeto (ENV-FENCE-001).
##
## Usa assets/fences/coop_fence_02.png, a única peça da pasta desenhada DE FRENTE
## (as outras são diagonais e não combinam com a câmera do jogo, que olha de +Z).
## Cada peça tem 3 postes e 2 vãos; peças vizinhas dividem o poste da junta, então
## o trecho sempre começa e termina num poste (postes nos cantos) e os vãos ficam
## todos iguais. A quantidade de peças é escolhida para o vão ficar perto de
## `target_segment_length`, sem esticar a arte além de ±25%.
##
## A cerca fica no eixo X local, centrada na origem, de -length/2 a +length/2,
## em pé de frente para a câmera e com a altura compensada pela inclinação de
## 45° (como placas e caixas). É só visual: quem precisa bloquear passagem soma
## a sua própria colisão (FarmWorld e SalesCounter mantêm as caixas de colisão).

const TEXTURE := preload("res://assets/fences/coop_fence_02.png")
## Centro do primeiro e do último poste no PNG (px) e linha do chão (base dos postes).
const FIRST_POST_PX := 62.0
const LAST_POST_PX := 500.0
const GROUND_PX := 168.0
const VIEW_PITCH_DEGREES := 45.0

## Comprimento (m) de poste a poste nas pontas.
@export_range(0.5, 80.0, 0.05) var length: float = 5.0:
    set(value):
        length = value
        if is_node_ready():
            rebuild()
## FENCE-002: cercas 20% maiores. A arte escala por igual com o comprimento
## da peça, então a peça alvo passou de 2,6 m para 2,6 x 1,2 = 3,12 m (postes
## 20% mais altos e vãos 20% mais largos).
const SIZE_SCALE := 1.2
const DEFAULT_SEGMENT_LENGTH := 2.6 * SIZE_SCALE
## FENCE-002: arranjo orgânico (feito à mão). Cada peça ganha, de forma fixa
## por posição (mesma cerca a cada carga): inclinação leve, um pequeno avanço
## ou recuo em Z, um afundamento no chão e variação de altura.
const ORGANIC_TILT_DEGREES := 1.8
const ORGANIC_Z_JITTER := 0.09
const ORGANIC_HEIGHT_JITTER := 0.05
const ORGANIC_SINK := 0.05

## Comprimento desejado de cada peça (2 vãos), em metros.
@export_range(1.0, 6.0, 0.05) var target_segment_length: float = DEFAULT_SEGMENT_LENGTH
## 0 desliga o arranjo orgânico (peças retas e alinhadas).
@export_range(0.0, 2.0, 0.05) var organic: float = 1.0

static var _shared_material: StandardMaterial3D

func _ready() -> void:
    rebuild()

static func screen_stretch() -> float:
    return 1.0 / cos(deg_to_rad(VIEW_PITCH_DEGREES))

## Número de peças para um comprimento (pelo menos 1).
static func segment_count_for(total: float, target: float = DEFAULT_SEGMENT_LENGTH) -> int:
    return maxi(1, int(round(total / target)))

func get_segment_count() -> int:
    return get_child_count()

func get_segment_length() -> float:
    return length / float(segment_count_for(length, target_segment_length))

## Altura visível dos postes (m, antes da compensação da câmera).
func get_post_height() -> float:
    return GROUND_PX * get_segment_length() / (LAST_POST_PX - FIRST_POST_PX)

func rebuild() -> void:
    for child in get_children():
        remove_child(child)
        child.queue_free()
    var count := segment_count_for(length, target_segment_length)
    var span := length / float(count)
    var k := span / (LAST_POST_PX - FIRST_POST_PX)
    var stretch := screen_stretch()
    var size := Vector2(TEXTURE.get_width(), TEXTURE.get_height()) * k
    for index in count:
        var piece := MeshInstance3D.new()
        piece.name = "FenceSegment_%02d" % (index + 1)
        var quad := QuadMesh.new()
        quad.size = size
        piece.mesh = quad
        piece.material_override = _material()
        piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        var left_post_x := -length * 0.5 + span * float(index)
        var seed_x := global_position.x if is_inside_tree() else position.x
        var seed_z := global_position.z if is_inside_tree() else position.z
        var h1 := _hash(seed_x, seed_z, index, 1.0) * 2.0 - 1.0
        var h2 := _hash(seed_x, seed_z, index, 2.0) * 2.0 - 1.0
        var h3 := _hash(seed_x, seed_z, index, 3.0) * 2.0 - 1.0
        var height_factor := 1.0 + h3 * ORGANIC_HEIGHT_JITTER * organic
        var ground := GROUND_PX * k
        piece.position = Vector3(
            left_post_x - FIRST_POST_PX * k + size.x * 0.5,
            (ground - size.y * 0.5) * stretch * height_factor - ORGANIC_SINK * organic * absf(h2),
            # Peças da direita um pouco à frente: o poste da junta não disputa
            # profundidade com o da peça anterior.
            0.004 * float(index) + h2 * ORGANIC_Z_JITTER * organic
        )
        piece.scale = Vector3(1.0, stretch * height_factor, 1.0)
        piece.rotation.z = deg_to_rad(h1 * ORGANIC_TILT_DEGREES * organic)
        add_child(piece)

static func _hash(x: float, z: float, index: int, salt: float) -> float:
    return fposmod(sin(x * 12.9898 + z * 78.233 + float(index) * 37.719 + salt * 4.581) * 43758.5453, 1.0)

static func _material() -> StandardMaterial3D:
    if _shared_material == null:
        var material := StandardMaterial3D.new()
        material.albedo_texture = TEXTURE
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
        material.alpha_scissor_threshold = 0.5
        material.cull_mode = BaseMaterial3D.CULL_DISABLED
        material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
        _shared_material = material
    return _shared_material
