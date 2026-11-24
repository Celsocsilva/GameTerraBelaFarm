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
## CHOP-002: golpe de machado com as duas mãos, gerado em código sobre a pose
## de Idle (a biblioteca não tem animação de cortar). Ciclo e impacto iguais aos
## do EucalyptusGrove (WoodConfig.CHOP_SWING_SECONDS / CHOP_IMPACT_SECONDS).
const ANIM_CHOP := &"Chop_Swing"
## Ossos da camada de corte: tronco e braços (pernas seguem a locomoção).
const CHOP_BONES := ["spine_02", "spine_03", "neck_01", "head", "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]

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
var chopping := false
var _chop_amount := 0.0
var _skeleton: Skeleton3D
## Machado 3D na mão direita (só aparece cortando).
var axe: Node3D
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

    # CHOP-002: camada de corte (tronco e braços), misturada por blend_amount.
    _build_chop_animation()
    var chop_blend := AnimationNodeBlend2.new()
    chop_blend.filter_enabled = true
    for bone in CHOP_BONES:
        chop_blend.set_filter_path(NodePath("%s:%s" % [SKELETON_PATH, bone]), true)
    var chop_anim := AnimationNodeAnimation.new()
    chop_anim.animation = ANIM_CHOP
    bt.add_node("chop_anim", chop_anim)
    bt.add_node("chop_seek", AnimationNodeTimeSeek.new())
    bt.connect_node("chop_seek", 0, "chop_anim")
    bt.add_node("chop", chop_blend)
    bt.connect_node("chop", 0, "full")
    bt.connect_node("chop", 1, "chop_seek")
    bt.connect_node("output", 0, "chop")

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
    tree.set("parameters/chop/blend_amount", 0.0)
    _build_axe()


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


## CHOP-002: começa a cortar (golpe em loop, sincronizado: o ciclo recomeça
## agora, então o impacto cai em CHOP_IMPACT_SECONDS, como no EucalyptusGrove).
func start_chop() -> void:
    if tree == null:
        return
    chopping = true
    tree.set("parameters/chop_seek/seek_request", 0.0)


## Para de cortar: braços e tronco voltam à locomoção com um fade curto.
func stop_chop() -> void:
    chopping = false


func get_chop_amount() -> float:
    return _chop_amount


func _process(delta: float) -> void:
    if tree == null:
        return
    var target := 1.0 if chopping else 0.0
    # Entra rápido (~0,15 s) e sai suave (~0,3 s): sem tranco de pose.
    _chop_amount = move_toward(_chop_amount, target, delta * (6.5 if chopping else 3.4))
    tree.set("parameters/chop/blend_amount", _chop_amount)
    if axe:
        axe.visible = _chop_amount > 0.02
        if axe.visible:
            _place_axe()


func _get_skeleton() -> Skeleton3D:
    if _skeleton == null and animation_player:
        var anim_root := animation_player.get_node_or_null(animation_player.root_node)
        if anim_root:
            _skeleton = anim_root.get_node_or_null(SKELETON_PATH) as Skeleton3D
    return _skeleton


## Pose-base de cada osso: o primeiro quadro do Idle (ou o rest), em rotação local.
func _base_local_rotation(skeleton: Skeleton3D, idle: Animation, bone: int) -> Quaternion:
    if idle:
        var track := idle.find_track(NodePath("%s:%s" % [SKELETON_PATH, skeleton.get_bone_name(bone)]), Animation.TYPE_ROTATION_3D)
        if track >= 0:
            return idle.rotation_track_interpolate(track, 0.0)
    return skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()


## Golpe com as duas mãos no espaço do esqueleto (frente +Z, cima +Y, direita
## do fazendeiro -X): ergue os braços acima da cabeça inclinando o tronco para
## trás, desce forte até a altura do tronco da árvore curvando o tronco para a
## frente (impacto), segue o movimento e volta à guarda.
func _build_chop_animation() -> void:
    var skeleton := _get_skeleton()
    if skeleton == null or animation_player.has_animation(ANIM_CHOP):
        return
    var idle: Animation = animation_player.get_animation(ANIM_IDLE) if animation_player.has_animation(ANIM_IDLE) else null
    var count := skeleton.get_bone_count()
    var base_local: Array[Quaternion] = []
    var base_global: Array[Quaternion] = []
    for bone in count:
        base_local.append(_base_local_rotation(skeleton, idle, bone))
        base_global.append(Quaternion.IDENTITY)
    for bone in count:
        var parent := skeleton.get_bone_parent(bone)
        base_global[bone] = (base_global[parent] if parent >= 0 else Quaternion.IDENTITY) * base_local[bone]
    var cycle := float(WoodConfig.CHOP_SWING_SECONDS)
    var impact := float(WoodConfig.CHOP_IMPACT_SECONDS)
    # [tempo, ergue o braço (graus, frente/cima), fecha as mãos ao centro,
    #  curva o tronco (+ frente), dobra o cotovelo]
    var keys := [
        [0.0, 50.0, 14.0, 4.0, 25.0],
        [impact * 0.42, 120.0, 16.0, -6.0, 55.0],
        [impact * 0.8, 168.0, 18.0, -14.0, 40.0],
        [impact, 78.0, 22.0, 24.0, 6.0],
        [impact + (cycle - impact) * 0.3, 62.0, 20.0, 20.0, 10.0],
        [cycle, 50.0, 14.0, 4.0, 25.0],
    ]
    var raise_axis := Vector3(-1.0, 0.0, 0.0)
    var bend_axis := Vector3(1.0, 0.0, 0.0)
    var anim := Animation.new()
    anim.length = cycle
    anim.loop_mode = Animation.LOOP_LINEAR
    for bone_name in CHOP_BONES:
        var bone := skeleton.find_bone(bone_name)
        if bone < 0:
            continue
        var track := anim.add_track(Animation.TYPE_ROTATION_3D)
        anim.track_set_path(track, NodePath("%s:%s" % [SKELETON_PATH, bone_name]))
        anim.track_set_interpolation_type(track, Animation.INTERPOLATION_CUBIC)
        var parent := skeleton.get_bone_parent(bone)
        var parent_global: Quaternion = base_global[parent] if parent >= 0 else Quaternion.IDENTITY
        var side := 1.0 if String(bone_name).ends_with("_r") else -1.0
        for key in keys:
            var extra := Quaternion.IDENTITY
            match bone_name:
                "spine_02":
                    extra = Quaternion(bend_axis, deg_to_rad(key[3] * 0.45))
                "spine_03":
                    extra = Quaternion(bend_axis, deg_to_rad(key[3] * 0.55))
                "neck_01", "head":
                    # A cabeça compensa: o olhar fica no tronco da árvore.
                    extra = Quaternion(bend_axis, deg_to_rad(-key[3] * 0.3))
                "upperarm_l", "upperarm_r":
                    extra = Quaternion(Vector3.UP, deg_to_rad(key[2] * side)) * Quaternion(raise_axis, deg_to_rad(key[1]))
                "lowerarm_l", "lowerarm_r":
                    extra = Quaternion(raise_axis, deg_to_rad(key[4]))
            var local: Quaternion = parent_global.inverse() * extra * parent_global * base_local[bone]
            anim.rotation_track_insert_key(track, key[0], local.normalized())
    var library := animation_player.get_animation_library(&"")
    if library == null:
        library = AnimationLibrary.new()
        animation_player.add_animation_library(&"", library)
    library.add_animation(ANIM_CHOP, anim)


## Machado cozy (CHOP-003, pedido do Celso): cabo grosso de madeira clara com
## pomo arredondado, cinta vermelha e lâmina larga e brilhante, para ler bem
## na tela do celular. Eixo Y = cabo; +Z = fio da lâmina (lado do golpe).
func _build_axe() -> void:
    var host := get_parent() as Node3D
    if host == null:
        return
    axe = Node3D.new()
    axe.name = "ChopAxe"
    axe.top_level = true
    axe.visible = false
    host.add_child.call_deferred(axe)
    var wood := StandardMaterial3D.new()
    wood.albedo_color = Color(0.78, 0.5, 0.26)
    wood.roughness = 0.75
    var wood_dark := StandardMaterial3D.new()
    wood_dark.albedo_color = Color(0.5, 0.29, 0.13)
    wood_dark.roughness = 0.8
    var metal := StandardMaterial3D.new()
    metal.albedo_color = Color(0.82, 0.86, 0.92)
    metal.metallic = 0.35
    metal.roughness = 0.3
    var band := StandardMaterial3D.new()
    band.albedo_color = Color(0.86, 0.2, 0.14)
    band.roughness = 0.6
    _axe_part(CylinderMesh.new(), wood, Vector3(0.0, 0.3, 0.0), func(m: CylinderMesh) -> void:
        m.top_radius = 0.05
        m.bottom_radius = 0.06
        m.height = 0.95
        m.radial_segments = 12)
    _axe_part(SphereMesh.new(), wood_dark, Vector3(0.0, -0.18, 0.0), func(m: SphereMesh) -> void:
        m.radius = 0.08
        m.height = 0.14)
    _axe_part(CylinderMesh.new(), band, Vector3(0.0, 0.7, 0.0), func(m: CylinderMesh) -> void:
        m.top_radius = 0.075
        m.bottom_radius = 0.075
        m.height = 0.2
        m.radial_segments = 12)
    # Lâmina larga e arredondada: corpo de metal + disco no fio (curva cozy).
    _axe_part(BoxMesh.new(), metal, Vector3(0.0, 0.72, 0.12), func(m: BoxMesh) -> void:
        m.size = Vector3(0.07, 0.24, 0.22))
    var edge := _axe_part(CylinderMesh.new(), metal, Vector3(0.0, 0.72, 0.2), func(m: CylinderMesh) -> void:
        m.top_radius = 0.21
        m.bottom_radius = 0.21
        m.height = 0.075
        m.radial_segments = 24)
    edge.rotation = Vector3(0.0, 0.0, PI * 0.5)
    # Talão de metal atrás do cabo (equilibra a silhueta).
    _axe_part(BoxMesh.new(), metal, Vector3(0.0, 0.72, -0.1), func(m: BoxMesh) -> void:
        m.size = Vector3(0.1, 0.2, 0.12))

func _axe_part(mesh: PrimitiveMesh, material: Material, position: Vector3, setup: Callable) -> MeshInstance3D:
    setup.call(mesh)
    var part := MeshInstance3D.new()
    part.mesh = mesh
    part.material_override = material
    part.position = position
    axe.add_child(part)
    return part


## Cabo na mão direita, continuando a linha do antebraço; a lâmina fica do lado
## do golpe (perpendicular ao braço, no plano do movimento).
func _place_axe() -> void:
    var skeleton := _get_skeleton()
    if skeleton == null or not skeleton.is_inside_tree() or not axe.is_inside_tree():
        return
    var hand := skeleton.find_bone("hand_r")
    var elbow := skeleton.find_bone("lowerarm_r")
    if hand < 0 or elbow < 0:
        return
    var hand_pos := skeleton.global_transform * skeleton.get_bone_global_pose(hand).origin
    var elbow_pos := skeleton.global_transform * skeleton.get_bone_global_pose(elbow).origin
    var along := hand_pos - elbow_pos
    if along.length() < 0.0001:
        return
    along = along.normalized()
    var lateral := skeleton.global_basis.x.normalized()
    var blade := lateral.cross(along)
    if blade.length() < 0.001:
        blade = skeleton.global_basis.z.normalized()
    blade = blade.normalized()
    lateral = along.cross(blade).normalized()
    var size := skeleton.global_basis.get_scale().y
    axe.global_transform = Transform3D(Basis(lateral, along, blade).scaled(Vector3.ONE * size * 0.55), hand_pos)


func _on_tree_animation_finished(anim_name: StringName) -> void:
    if not String(anim_name).ends_with("_Loop"):
        action_finished.emit(anim_name)
