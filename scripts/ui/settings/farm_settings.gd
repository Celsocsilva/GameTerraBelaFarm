extends RefCounted
class_name FarmSettings
## Preferências do jogador (FV-HUD-002): idioma e som, salvos em
## user://settings.cfg. Sem arquivo, o jogo segue o idioma do aparelho
## (comportamento anterior) e o som fica ligado.

const PATH := "user://settings.cfg"
const LOCALES := ["pt_BR", "es", "en"]
const MASTER_BUS := "Master"

static func load_and_apply() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(PATH) != OK:
        return
    var locale := String(cfg.get_value("general", "locale", ""))
    if locale in LOCALES:
        TranslationServer.set_locale(locale)
    apply_sound(bool(cfg.get_value("audio", "enabled", true)), float(cfg.get_value("audio", "volume", 1.0)))

static func set_locale(locale: String) -> void:
    if not (locale in LOCALES):
        return
    TranslationServer.set_locale(locale)
    _save("general", "locale", locale)

## Idioma atual reduzido a um dos 3 suportados (pt_BR, es, en).
static func current_locale() -> String:
    var locale := TranslationServer.get_locale()
    if locale.begins_with("es"):
        return "es"
    if locale.begins_with("en"):
        return "en"
    return "pt_BR"

static func set_sound_enabled(enabled: bool) -> void:
    apply_sound(enabled, get_volume())
    _save("audio", "enabled", enabled)

static func set_volume(volume: float) -> void:
    volume = clampf(volume, 0.0, 1.0)
    apply_sound(is_sound_enabled(), volume)
    _save("audio", "volume", volume)

static func is_sound_enabled() -> bool:
    var bus := AudioServer.get_bus_index(MASTER_BUS)
    return bus < 0 or not AudioServer.is_bus_mute(bus)

static func get_volume() -> float:
    var bus := AudioServer.get_bus_index(MASTER_BUS)
    if bus < 0:
        return 1.0
    return clampf(db_to_linear(AudioServer.get_bus_volume_db(bus)), 0.0, 1.0)

static func apply_sound(enabled: bool, volume: float) -> void:
    var bus := AudioServer.get_bus_index(MASTER_BUS)
    if bus < 0:
        return
    AudioServer.set_bus_mute(bus, not enabled)
    AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(clampf(volume, 0.0, 1.0), 0.0001)))

static func _save(section: String, key: String, value: Variant) -> void:
    var cfg := ConfigFile.new()
    cfg.load(PATH)
    cfg.set_value(section, key, value)
    cfg.save(PATH)
