@tool
extends EditorScenePostImport
## Pós-importação dos personagens rigados (RIG_STANDARD.md).
## Use com `nodes/use_name_suffixes=false` no .import: o Godot mantém os nomes exatos das animações
## (ex.: "Walk_Loop") e este script marca como LOOP_LINEAR toda animação terminada em "_Loop".


func _post_import(scene: Node) -> Object:
    _apply(scene)
    return scene


func _apply(node: Node) -> void:
    if node is AnimationPlayer:
        var ap := node as AnimationPlayer
        for lib_name in ap.get_animation_library_list():
            var lib := ap.get_animation_library(lib_name)
            for anim_name in lib.get_animation_list():
                if String(anim_name).ends_with("_Loop"):
                    lib.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
    for c in node.get_children():
        _apply(c)
