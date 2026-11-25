extends SceneTree
## FARMER-RIG-001 — capturas do fazendeiro rigado renderizado pelo Godot (Forward+/Mobile do projeto).
## Rodar SEM --headless:
##   godot --path . --resolution 1280x720 -s tools/farmer_rig_capture.gd -- <pasta absoluta> [--scene=res://.../x_character.tscn]

var SCENE := "res://assets/animations/Farmer/farmer_character.tscn"
const SHOTS := [
    ["01-basicas", [["Idle_Loop", 0.4], ["Walk_Loop", 0.35], ["Jog_Fwd_Loop", 0.25], ["Sprint_Loop", 0.2], ["Carry_Walk_Loop", 0.35]]],
    ["02-fazenda", [["Carry_Idle_Loop", 0.5], ["Fixing_Kneeling", 2.2], ["PickUp_Table", 0.45], ["Interact", 0.9], ["Crouch_Fwd_Loop", 0.5]]],
]

var out_dir := ""


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var args := OS.get_cmdline_user_args()
    for a in args.duplicate():
        if a.begins_with("--scene="):
            SCENE = a.substr(8)
            args.erase(a)
    out_dir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://docs/evidence/farmer-rig-001")
    DirAccess.make_dir_recursive_absolute(out_dir)
    var stage := Node3D.new()
    root.add_child(stage)
    _build_stage(stage)
    var cam := Camera3D.new()
    stage.add_child(cam)
    cam.projection = Camera3D.PROJECTION_ORTHOGONAL
    cam.size = 1.9
    cam.current = true
    for shot in SHOTS:
        var holder := Node3D.new()
        stage.add_child(holder)
        var list: Array = shot[1]
        for i in list.size():
            var ch := (load(SCENE) as PackedScene).instantiate() as Node3D
            holder.add_child(ch)
            ch.position = Vector3((i - (list.size() - 1) / 2.0) * 0.62, 0, 0)
            var lbl := Label3D.new()
            lbl.text = list[i][0]
            lbl.font_size = 22
            lbl.pixel_size = 0.0022
            lbl.position = Vector3(0, 1.12, 0)
            lbl.modulate = Color(0.15, 0.2, 0.12)
            lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
            ch.add_child(lbl)
        await process_frame
        for i in list.size():
            var ch := holder.get_child(i) as Node3D
            var ap := ch.get_node("Model/AnimationPlayer") as AnimationPlayer
            ap.play(list[i][0])
            ap.seek(float(list[i][1]), true)
            ap.speed_scale = 0.0
        # frente: o personagem olha para -Z. camera-jogo: câmera elevada em +Z, como no FarmWorld
        for view in [["frente", Vector3(-0.9, 0.75, -3.0)], ["camera-jogo", Vector3(0.0, 2.6, 2.6)]]:
            cam.position = view[1]
            cam.look_at(Vector3(0, 0.45, 0))
            await create_timer(0.4).timeout
            var img := root.get_viewport().get_texture().get_image()
            var path := out_dir.path_join("%s-%s.png" % [shot[0], view[0]])
            img.save_png(path)
            print("CAPTURA ", path)
        holder.queue_free()
        await process_frame
    quit(0)


func _build_stage(stage: Node3D) -> void:
    var env := WorldEnvironment.new()
    var e := Environment.new()
    e.background_mode = Environment.BG_COLOR
    e.background_color = Color(0.80, 0.86, 0.76)
    e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    e.ambient_light_color = Color(0.85, 0.88, 0.95)
    e.ambient_light_energy = 0.55
    e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.environment = e
    stage.add_child(env)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-50, 30, 0)
    sun.light_energy = 1.25
    sun.shadow_enabled = true
    stage.add_child(sun)
    var ground := MeshInstance3D.new()
    var pm := PlaneMesh.new()
    pm.size = Vector2(8, 8)
    ground.mesh = pm
    var gm := StandardMaterial3D.new()
    gm.albedo_color = Color(0.56, 0.68, 0.40)
    ground.material_override = gm
    stage.add_child(ground)
