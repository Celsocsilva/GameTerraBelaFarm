extends SceneTree
## LOAD-001 / SCREEN-001 — tela de carregamento e tela cheia no celular.
## Uso: Godot --headless --path . -s tools/loading_screen_smoke.gd
## 1) Projeto: cena principal = tela de carregamento, paisagem forçada (sensor),
##    stretch "expand" (sem faixas pretas em telas 20:9) e boot splash com a arte.
## 2) A tela mostra a arte, a barra sobe sem voltar e entrega a fazenda como
##    cena atual, depois some.

var _failures := 0

func _initialize() -> void:
    call_deferred("_run")

func _check(ok: bool, message: String) -> void:
    if not ok:
        _failures += 1
        push_error("LOADING_SMOKE_FAIL: " + message)

func _run() -> void:
    _check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/core/loading_screen.tscn", "cena principal deve ser a tela de carregamento")
    _check(int(ProjectSettings.get_setting("display/window/handheld/orientation")) == DisplayServer.SCREEN_SENSOR_LANDSCAPE, "orientação deve ser paisagem (sensor)")
    _check(ProjectSettings.get_setting("display/window/stretch/aspect") == "expand", "stretch aspect deve ser expand (tela cheia)")
    _check(String(ProjectSettings.get_setting("application/boot_splash/image")) == "res://assets/ui/loading/loading_screen.png", "boot splash deve usar a arte")

    var screen := (load("res://scenes/core/loading_screen.tscn") as PackedScene).instantiate() as LoadingScreen
    root.add_child(screen)
    current_scene = screen
    await process_frame
    var art := screen.find_child("Art", true, false) as TextureRect
    _check(art != null and art.texture != null, "arte deve aparecer")
    _check(screen.progress_bar != null, "barra de carregamento deve existir")
    var last := -1.0
    var went_back := false
    var start := Time.get_ticks_msec()
    while is_instance_valid(screen) and Time.get_ticks_msec() - start < 60000:
        if screen.progress_bar.value < last - 0.0001:
            went_back = true
        last = screen.progress_bar.value
        await process_frame
    _check(not went_back, "barra nunca deve voltar")
    _check(not is_instance_valid(screen), "tela de carregamento deve sair")
    _check(current_scene is FarmWorld, "fazenda deve virar a cena atual")
    if current_scene:
        current_scene.queue_free()
    await process_frame
    if _failures > 0:
        print("LOADING_SMOKE_FAILED failures=", _failures)
        quit(1)
        return
    print("LOADING_SMOKE_OK")
    quit()
