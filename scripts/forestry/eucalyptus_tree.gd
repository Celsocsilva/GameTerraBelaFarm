extends Node3D
class_name EucalyptusTree
## Um eucalipto plantado (FV-WOOD-001/002). Ciclo:
##   GROWN (arte da estação)
##   -> CHOPPING (golpes do machado: entalhe, corte fundo, inclinada; cut_stage 1..3)
##   -> FALLEN (árvore caída ao lado do toco)
##   -> STUMP (toco com as toras) -> GONE (some) -> GROWN (rebrota).
## A arte é um Sprite3D sempre virado para a câmera, com a base no chão, igual
## às árvores decorativas do CozyEnvironment. Sem colisão: as fileiras ficam nas
## bordas dos canteiros e do rio e não podem fechar a passagem do fazendeiro.
## Os estágios da queda (assets/props/trees/eucalyptus/fall/) foram recortados
## com o mesmo quadro: trocar de estágio não desloca a árvore.
## Os tempos vêm do WoodConfig; o EucalyptusGrove comanda o corte e chama tick(delta).

signal state_changed(tree: EucalyptusTree, state: StringName)

const GROWN := &"grown"
const CHOPPING := &"chopping"
const FALLEN := &"fallen"
const STUMP := &"stump"
const GONE := &"gone"

const SEASON_TEXTURES := {
    &"spring": preload("res://assets/props/trees/eucalyptus/eucalyptus_spring.png"),
    &"summer": preload("res://assets/props/trees/eucalyptus/eucalyptus_summer.png"),
    &"autumn": preload("res://assets/props/trees/eucalyptus/eucalyptus_autumn.png"),
    &"winter": preload("res://assets/props/trees/eucalyptus/eucalyptus_winter.png"),
}
## Estágios da queda, na ordem: inteira, entalhe, corte fundo, inclinada, caída, toco com toras.
const FALL_TEXTURES: Array[Texture2D] = [
    preload("res://assets/props/trees/eucalyptus/fall/eucalyptus_fall_01_whole.png"),
    preload("res://assets/props/trees/eucalyptus/fall/eucalyptus_fall_02_notch.png"),
    preload("res://assets/props/trees/eucalyptus/fall/eucalyptus_fall_03_deep_cut.png"),
    preload("res://assets/props/trees/eucalyptus/fall/eucalyptus_fall_04_leaning.png"),
    preload("res://assets/props/trees/eucalyptus/fall/eucalyptus_fall_05_fallen.png"),
    preload("res://assets/props/trees/eucalyptus/fall/eucalyptus_fall_06_stump_logs.png"),
]
const FALLEN_INDEX := 4
const STUMP_INDEX := 5
const STUMP_TEXTURE: Texture2D = FALL_TEXTURES[STUMP_INDEX]
## O quadro dos estágios tem margem: a árvore inteira ocupa 536 px de altura e
## está centrada em x = 244 px. Escala para a árvore inteira ter a mesma altura
## da arte da estação (que é recortada justa).
const FALL_TREE_HEIGHT_PX := 536.0
const FALL_ANCHOR_X_PX := 244.0

## Largura da árvore em metros (arte da estação e quadro dos estágios da queda).
@export_range(1.0, 5.0, 0.05) var tree_width: float = 2.5

var state: StringName = GROWN
var season: StringName = &"summer"
## Golpes recebidos no corte atual (0 = nenhum; CHOP_HITS = inclinada).
var cut_stage := 0
## Segundos restantes no estado atual (toco ou rebrota).
var time_left := 0.0
var sprite: Sprite3D
var _shake: Tween

func _ready() -> void:
    sprite = Sprite3D.new()
    sprite.name = "Art"
    sprite.centered = false
    sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    sprite.shaded = false
    sprite.double_sided = true
    sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
    sprite.alpha_scissor_threshold = 0.25
    sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(sprite)
    _apply_art()

func is_choppable() -> bool:
    return state == GROWN

func set_season(value: StringName) -> void:
    if not SEASON_TEXTURES.has(value):
        return
    season = value
    if state == GROWN:
        _apply_art()

func get_current_texture() -> Texture2D:
    return sprite.texture if sprite and sprite.visible else null

## Primeiro golpe: começa o corte.
func start_chop() -> void:
    if state != GROWN:
        return
    cut_stage = 0
    _set_state(CHOPPING)

## Um golpe do machado: avança um estágio (1 entalhe, 2 corte fundo, 3+ inclinada).
func hit() -> void:
    if state != CHOPPING:
        return
    cut_stage = mini(cut_stage + 1, 3)
    _apply_art()
    _tremble()

## O fazendeiro saiu antes da inclinação: a árvore volta inteira.
func cancel_chop() -> void:
    if state != CHOPPING:
        return
    cut_stage = 0
    _set_state(GROWN)
    _apply_art()

## A árvore inclinada cai no chão.
func fall() -> void:
    _set_state(FALLEN)
    _apply_art()
    _tremble()

## Fim da queda: toco com as toras por STUMP_SECONDS.
func fell() -> void:
    time_left = WoodConfig.STUMP_SECONDS
    _set_state(STUMP)
    _apply_art()
    _pop(0.25)

func tick(delta: float) -> void:
    if state != STUMP and state != GONE:
        return
    time_left -= delta
    if time_left > 0.0:
        return
    if state == STUMP:
        time_left = WoodConfig.REGROW_SECONDS
        _set_state(GONE)
        _apply_art()
    else:
        regrow()

## Rebrota na hora (fim do tempo, testes e capturas).
func regrow() -> void:
    time_left = 0.0
    cut_stage = 0
    _set_state(GROWN)
    _apply_art()
    _pop(0.45)

func _set_state(value: StringName) -> void:
    if state == value:
        return
    state = value
    state_changed.emit(self, value)

func _apply_art() -> void:
    if sprite == null:
        return
    sprite.visible = state != GONE
    var texture: Texture2D
    match state:
        CHOPPING:
            texture = FALL_TEXTURES[clampi(cut_stage, 0, 3)] if cut_stage > 0 else SEASON_TEXTURES.get(season, SEASON_TEXTURES[&"summer"])
        FALLEN:
            texture = FALL_TEXTURES[FALLEN_INDEX]
        STUMP, GONE:
            texture = FALL_TEXTURES[STUMP_INDEX]
        _:
            texture = SEASON_TEXTURES.get(season, SEASON_TEXTURES[&"summer"])
    sprite.texture = texture
    if FALL_TEXTURES.has(texture):
        var season_art: Texture2D = SEASON_TEXTURES[&"summer"]
        var season_height := tree_width * float(season_art.get_height()) / float(season_art.get_width())
        sprite.pixel_size = season_height / FALL_TREE_HEIGHT_PX
        sprite.offset = Vector2(-FALL_ANCHOR_X_PX, 0.0)
    else:
        sprite.pixel_size = tree_width / float(texture.get_width())
        sprite.offset = Vector2(-texture.get_width() * 0.5, 0.0)

## Tremor curto a cada golpe (billboard ignora rotação: é um tremor lateral).
func _tremble() -> void:
    if not is_inside_tree() or sprite == null:
        return
    if _shake and _shake.is_valid():
        _shake.kill()
    _shake = create_tween()
    _shake.tween_property(sprite, "position:x", 0.07, 0.04)
    _shake.tween_property(sprite, "position:x", -0.07, 0.07)
    _shake.tween_property(sprite, "position:x", 0.0, 0.04)

func _pop(duration: float) -> void:
    if not is_inside_tree() or sprite == null:
        return
    sprite.scale = Vector3.ONE * 0.6
    var tween := create_tween()
    tween.tween_property(sprite, "scale", Vector3.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
