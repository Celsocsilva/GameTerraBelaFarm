class_name FarmerAnimator
extends Node
## Animação do fazendeiro (Godot 4.x) — rig Rigify, esqueleto de jogo padrão (RIG_STANDARD.md).
## Já está ligado em farmer_character.tscn. Monta um AnimationTree em código com 3 camadas:
##   1. locomoção (Transition): parado / andar / correr, com mochila (mãos nas alças), agachado ou caixa na frente;
##      a velocidade de reprodução acompanha a velocidade real para os pés não patinarem;
##   2. ação de tronco (OneShot com filtro nos ossos do tronco/braços): semear, colher, entregar ANDANDO;
##   3. ação de corpo inteiro (OneShot): a mesma ação quando o fazendeiro está PARADO (ou ajoelhar para plantar).
##
## Uso (ver FarmerController e FarmWorld):
##   animator.update_locomotion(velocidade_horizontal)
##   animator.carrying_backpack = true      # mochila com caixas
##   animator.play_sow() / play_harvest() / play_deliver() / play_plant_kneel() / play_action(&"Interact")

signal action_finished(anim_name: StringName)

const ANIM_IDLE := &"Idle_Loop"
const ANIM_WALK := &"Walk_Loop"
const ANIM_RUN := &"Jog_Fwd_Loop"
const ANIM_BACKPACK_IDLE := &"Backpack_Idle_Loop"
const ANIM_BACKPACK_WALK := &"Backpack_Walk_Loop"
const ANIM_BACKPACK_RUN := &"Backpack_Jog_Loop"
const ANIM_CARRY_IDLE := &"Carry_Idle_Loop"
const ANIM_CARRY_WALK := &"Carry_Walk_Loop"
const ANIM_CROUCH_IDLE := &"Crouch_Idle_Loop"
const ANIM_CROUCH_WALK := &"Crouch_Fwd_Loop"
const ANIM_SOW := &"Interact"
const ANIM_HARVEST := &"PickUp_Table"
const ANIM_DELIVER := &"Interact"
const ANIM_PLANT_KNEEL := &"Fixing_Kneeling"

## Estados de locomoção (entradas do nó Transition).
const LOCO := {
    &"idle": ANIM_IDLE, &"walk": ANIM_WALK, &"run": ANIM_RUN,
    &"bp_idle": ANIM_BACKPACK_IDLE, &"bp_walk": ANIM_BACKPACK_WALK, &"bp_run": ANIM_BACKPACK_RUN,
    &"carry_idle": ANIM_CARRY_IDLE, &"carry_walk": ANIM_CARRY_WALK,
    &"crouch_idle": ANIM_CROUCH_IDLE, &"crouch_walk": ANIM_CROUCH_WALK,
}
## Ossos da camada de tronco (ações andando): quadril e pernas continuam na locomoção.
const UPPER_BONES := [
    "spine_02", "spine_03", "neck_01", "head",
    "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
    "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
]
const SKELETON_PATH := "Farmer_Armature/Skeleton3D"

@export var animation_player: AnimationPlayer
@export var blend_time := 0.18
## Escala do modelo na cena (o .glb tem 1,0 m). O jogo usa 1,8 (mesma altura da cápsula antiga).
@export var model_scale := 1.0

## Velocidade de chão de cada ciclo a 1x, medida com tools/measure_stride.py (m/s, modelo em escala 1).
@export var walk_ref_speed := 0.344
@export var run_ref_speed := 1.624
@export var crouch_ref_speed := 0.245
## Acima desta velocidade (m/s do modelo em escala 1) troca de andar para correr.
@export var run_threshold := 0.72
@export var idle_threshold := 0.03
## Velocidades de reprodução das ações (o jogo é rápido: a semeadura acontece a cada passo).
@export var sow_speed := 2.4
@export var harvest_speed := 1.6
@export var deliver_speed := 2.0

var carrying_backpack := false
var carrying_front := false
var crouching := false
var tree: AnimationTree
var loco_state: StringName = &"idle"
var last_action: StringName = &""

var _moving := false
var _upper_anim: AnimationNodeAnimation
var _full_anim: AnimationNodeAnimation


func _ready() -> void:
    if animation_player == null:
        push_error("FarmerAnimator: animation_player não definido")
        return
    for anim_name in animation_player.get_animation_list():
        if String(anim_name).ends_with("_Loop"):
            animation_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
    _build_tree()


func _build_tree() -> void:
    var bt := AnimationNodeBlendTree.new()
    var trans := AnimationNodeTransition.new()
    trans.xfade_time = blend_time
    trans.input_count = LOCO.size()
    var i := 0
    for state in LOCO:
        trans.set_input_name(i, String(state))
        var node := AnimationNodeAnimation.new()
        node.animation = LOCO[state]
        bt.add_node("a_" + String(state), node)
        i += 1
    bt.add_node("loco", trans)
    i = 0
    for state in LOCO:
        bt.connect_node("loco", i, "a_" + String(state))
        i += 1
    bt.add_node("loco_speed", AnimationNodeTimeScale.new())
    bt.connect_node("loco_speed", 0, "loco")

    var upper := AnimationNodeOneShot.new()
    upper.fadein_time = 0.1
    upper.fadeout_time = 0.2
    upper.filter_enabled = true
    for bone in UPPER_BONES:
        upper.set_filter_path(NodePath("%s:%s" % [SKELETON_PATH, bone]), true)
    _upper_anim = AnimationNodeAnimation.new()
    _upper_anim.animation = ANIM_SOW
    bt.add_node("upper_anim", _upper_anim)
    bt.add_node("upper_speed", AnimationNodeTimeScale.new())
    bt.connect_node("upper_speed", 0, "upper_anim")
    bt.add_node("upper", upper)
    bt.connect_node("upper", 0, "loco_speed")
    bt.connect_node("upper", 1, "upper_speed")

    var full := AnimationNodeOneShot.new()
    full.fadein_time = 0.12
    full.fadeout_time = 0.25
    _full_anim = AnimationNodeAnimation.new()
    _full_anim.animation = ANIM_HARVEST
    bt.add_node("full_anim", _full_anim)
    bt.add_node("full_speed", AnimationNodeTimeScale.new())
    bt.connect_node("full_speed", 0, "full_anim")
    bt.add_node("full", full)
    bt.connect_node("full", 0, "upper")
    bt.connect_node("full", 1, "full_speed")
    bt.connect_node("output", 0, "full")

    tree = AnimationTree.new()
    tree.name = "AnimationTree"
    tree.tree_root = bt
    # Fica ao lado do AnimationPlayer (filho do modelo), então as trilhas "Farmer_Armature/Skeleton3D:osso" resolvem igual.
    animation_player.get_parent().add_child(tree)
    tree.root_node = NodePath("..")
    tree.anim_player = tree.get_path_to(animation_player)
    tree.animation_finished.connect(_on_tree_animation_finished)
    tree.active = true
    _set_loco(&"idle", 1.0)


## Chamar todo quadro com a velocidade horizontal (m/s do jogo).
func update_locomotion(speed: float) -> void:
    if tree == null:
        return
    var s := speed / maxf(model_scale, 0.001)
    _moving = s >= idle_threshold
    var state: StringName
    var ref := 1.0
    if crouching:
        state = &"crouch_walk" if _moving else &"crouch_idle"
        ref = crouch_ref_speed
    elif carrying_front:
        state = &"carry_walk" if _moving else &"carry_idle"
        ref = walk_ref_speed
    else:
        var prefix := "bp_" if carrying_backpack else ""
        if not _moving:
            state = StringName(prefix + "idle") if prefix != "" else &"idle"
        elif s < run_threshold:
            state = StringName(prefix + "walk")
            ref = walk_ref_speed
        else:
            state = StringName(prefix + "run")
            ref = run_ref_speed
    var scale := clampf(s / ref, 0.5, 2.1) if _moving else 1.0
    _set_loco(state, scale)


func _set_loco(state: StringName, scale: float) -> void:
    tree.set("parameters/loco_speed/scale", scale)
    if state != loco_state or tree.get("parameters/loco/current_state") != String(state):
        loco_state = state
        tree.set("parameters/loco/transition_request", String(state))


## Semear (gesto de lançar sementes). Andando: só tronco/braços.
func play_sow() -> void:
    _play(ANIM_SOW, sow_speed)


## Colher (abaixar e pegar).
func play_harvest() -> void:
    _play(ANIM_HARVEST, harvest_speed)


## Entregar (balcão, cocho, plataforma do ajudante).
func play_deliver() -> void:
    _play(ANIM_DELIVER, deliver_speed)


## Plantar ajoelhado (corpo inteiro, ~5 s). Para cenas/tutoriais com o fazendeiro parado.
func play_plant_kneel() -> void:
    _play(ANIM_PLANT_KNEEL, 1.0, true)


## Ação qualquer da biblioteca (sem _Loop), uma vez.
func play_action(anim_name: StringName, speed := 1.0) -> void:
    _play(anim_name, speed)


func is_busy() -> bool:
    return tree != null and (bool(tree.get("parameters/upper/active")) or bool(tree.get("parameters/full/active")))


func _play(anim_name: StringName, speed: float, force_full := false) -> void:
    if tree == null or not animation_player.has_animation(anim_name):
        push_warning("FarmerAnimator: animação inexistente %s" % anim_name)
        return
    if is_busy():
        return   # não reinicia o gesto a cada evento (semeadura e colheita disparam muitos por segundo)
    last_action = anim_name
    if _moving and not force_full:
        _upper_anim.animation = anim_name
        tree.set("parameters/upper_speed/scale", speed)
        tree.set("parameters/upper/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
    else:
        _full_anim.animation = anim_name
        tree.set("parameters/full_speed/scale", speed)
        tree.set("parameters/full/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _on_tree_animation_finished(anim_name: StringName) -> void:
    if not String(anim_name).ends_with("_Loop"):
        action_finished.emit(anim_name)
