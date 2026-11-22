extends SceneTree
## FARMER-RIG-001 — valida o fazendeiro rigado (Rigify -> esqueleto de jogo padrão) no Godot.
##   godot --headless --path . -s tools/farmer_rig_smoke.gd
## Sai com código 1 se algo falhar.

const SCENE := "res://assets/animations/Farmer/farmer_character.tscn"
const BONES := [
    "root", "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head",
    "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
    "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
    "thigh_l", "calf_l", "foot_l", "ball_l",
    "thigh_r", "calf_r", "foot_r", "ball_r",
]
const REQUIRED_ANIMS := [
    "Idle_Loop", "Walk_Loop", "Jog_Fwd_Loop", "Sprint_Loop", "Carry_Idle_Loop", "Carry_Walk_Loop",
    "Backpack_Idle_Loop", "Backpack_Walk_Loop", "Backpack_Jog_Loop",
    "Fixing_Kneeling", "PickUp_Table", "Interact", "Crouch_Idle_Loop", "Crouch_Fwd_Loop",
]
const MAX_TRIS := 6500
const MAX_TEXTURE := 512

var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
    print(("PASS  " if ok else "FAIL  ") + msg)
    if not ok:
        failures.append(msg)


func _find(node: Node, cls: String) -> Node:
    if node.is_class(cls):
        return node
    for c in node.get_children():
        var r := _find(c, cls)
        if r:
            return r
    return null


func _run() -> void:
    var packed := load(SCENE) as PackedScene
    _check(packed != null, "cena carrega: " + SCENE)
    if packed == null:
        quit(1)
        return
    var ch := packed.instantiate() as Node3D
    root.add_child(ch)
    await process_frame

    var skel := _find(ch, "Skeleton3D") as Skeleton3D
    _check(skel != null, "Skeleton3D presente")
    var names: Array[String] = []
    for i in skel.get_bone_count():
        names.append(skel.get_bone_name(i))
    _check(skel.get_bone_count() == BONES.size(), "ossos: %d (esperado %d)" % [skel.get_bone_count(), BONES.size()])
    var missing := BONES.filter(func(b): return not names.has(b))
    _check(missing.is_empty(), "nomes padronizados (faltando: %s)" % [missing])
    var bad_names := names.filter(func(n): return n != n.to_lower() or n.contains(" ") or n.contains("."))
    _check(bad_names.is_empty(), "todos snake_case minúsculo (fora do padrão: %s)" % [bad_names])
    _check(skel.get_bone_parent(skel.find_bone("pelvis")) == skel.find_bone("root"), "hierarquia root -> pelvis")

    var mi := _find(ch, "MeshInstance3D") as MeshInstance3D
    _check(mi != null and mi.mesh != null, "MeshInstance3D com malha")
    var mesh := mi.mesh as ArrayMesh
    _check(mesh.get_surface_count() == 1, "1 superfície / 1 material (draw call única): %d" % mesh.get_surface_count())
    var arr := mesh.surface_get_arrays(0)
    var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
    var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
    var tris := idx.size() / 3
    _check(tris <= MAX_TRIS, "triângulos: %d (máx %d)" % [tris, MAX_TRIS])
    var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
    _check(weights.size() == verts.size() * 4, "4 influências por vértice (pesos/vértice = %d)" % [weights.size() / maxi(verts.size(), 1)])
    var worst := 0.0
    for v in verts.size():
        var s := weights[v * 4] + weights[v * 4 + 1] + weights[v * 4 + 2] + weights[v * 4 + 3]
        worst = maxf(worst, absf(1.0 - s))
    _check(worst < 0.01, "pesos normalizados (desvio máx %.4f)" % worst)
    var aabb := mesh.get_aabb()
    _check(absf(aabb.position.y) < 0.02 and absf(aabb.size.y - 1.0) < 0.05, "altura 1,0 m com pés em y=0 (aabb y=%.3f h=%.3f)" % [aabb.position.y, aabb.size.y])

    var mat := mesh.surface_get_material(0) as BaseMaterial3D
    if mi.get_surface_override_material(0):
        mat = mi.get_surface_override_material(0) as BaseMaterial3D
    _check(mat != null and mat.metallic < 0.01, "material não-metálico")
    var tex := mat.albedo_texture if mat else null
    _check(tex != null and tex.get_width() <= MAX_TEXTURE, "textura base <= %d px (%s)" % [MAX_TEXTURE, str(tex.get_size()) if tex else "nenhuma"])

    var ap := _find(ch, "AnimationPlayer") as AnimationPlayer
    _check(ap != null, "AnimationPlayer presente")
    var anims := ap.get_animation_list()
    print("      animações (%d): %s" % [anims.size(), ", ".join(anims)])
    for a in REQUIRED_ANIMS:
        _check(ap.has_animation(a), "animação " + a)
    var loops_ok := true
    var tracks_ok := true
    for a in anims:
        var anim := ap.get_animation(a)
        if String(a).ends_with("_Loop") and anim.loop_mode != Animation.LOOP_LINEAR:
            loops_ok = false
        for t in anim.get_track_count():
            var path := String(anim.track_get_path(t))
            if path.contains(":"):
                var bone := path.get_slice(":", 1)
                if skel.find_bone(bone) < 0:
                    tracks_ok = false
    _check(loops_ok, "todas as *_Loop em LOOP_LINEAR")
    _check(tracks_ok, "trilhas apontam só para ossos existentes")

    # a animação realmente move o esqueleto
    var thigh := skel.find_bone("thigh_l")
    ap.play("Walk_Loop")
    ap.seek(0.0, true)
    var q0 := skel.get_bone_pose_rotation(thigh)
    ap.seek(0.6, true)
    var q1 := skel.get_bone_pose_rotation(thigh)
    _check(q0.angle_to(q1) > 0.1, "Walk_Loop move a coxa (%.1f graus)" % rad_to_deg(q0.angle_to(q1)))

    var animator := ch.get_node("FarmerAnimator") as FarmerAnimator
    _check(animator.tree != null and animator.tree.active, "FarmerAnimator monta o AnimationTree")
    animator.carrying_backpack = true
    animator.update_locomotion(0.3)
    _check(animator.loco_state == &"bp_walk", "mochila + andando = Backpack_Walk_Loop (%s)" % animator.loco_state)
    animator.carrying_backpack = false
    animator.update_locomotion(0.0)
    animator.play_harvest()
    _check(animator.last_action == &"PickUp_Table", "colher = PickUp_Table")
    print("\nFARMER RIG SMOKE: %s" % ("OK" if failures.is_empty() else "FALHOU (%d)" % failures.size()))
    quit(0 if failures.is_empty() else 1)
