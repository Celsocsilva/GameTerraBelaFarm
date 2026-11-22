extends SceneTree
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
    var args := OS.get_cmdline_user_args(); var out := args[0] if not args.is_empty() else "res://docs/evidence/store-v2-001"
    DirAccess.make_dir_recursive_absolute(out)
    var world := (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world); await create_timer(.7).timeout
    world.hud.shop_modal.open_store(); await create_timer(.3).timeout
    for locale in ["pt_BR", "en_US", "es_ES"]:
        TranslationServer.set_locale(locale); world.hud.shop_modal.refresh_language(); await create_timer(.15).timeout; _shot(out, "store-v2-%s.png" % locale)
    TranslationServer.set_locale("pt_BR"); world.hud.shop_modal.next(); world.hud.shop_modal.next(); await create_timer(.2).timeout; _shot(out, "store-v2-carousel-page-3.png")
    quit()
func _shot(out: String, name: String) -> void:
    for i in 4: await process_frame
    root.get_texture().get_image().save_png(out.path_join(name))
