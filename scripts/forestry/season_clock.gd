extends RefCounted
class_name SeasonClock
## Estação do ano local (FV-WOOD-001), usada pela arte dos eucaliptos.
##
## A estação vem da data do aparelho e do hemisfério. O hemisfério é
## configurável (Projeto > Configurações, chaves abaixo, ou por código):
##   terrabela/seasons/hemisphere   = "auto" | "north" | "south"   (padrão "auto")
##   terrabela/seasons/force_season = "" | "spring" | "summer" | "autumn" | "winter"
## Em "auto" o país do idioma do aparelho (OS.get_locale(), ex.: pt_BR -> BR)
## decide; países fora da lista do sul contam como norte.
## Estações meteorológicas (meses inteiros): no sul, dez-fev verão, mar-mai
## outono, jun-ago inverno, set-nov primavera; no norte, o inverso.

const SPRING := &"spring"
const SUMMER := &"summer"
const AUTUMN := &"autumn"
const WINTER := &"winter"
const ALL: Array[StringName] = [SPRING, SUMMER, AUTUMN, WINTER]

const SETTING_HEMISPHERE := "terrabela/seasons/hemisphere"
const SETTING_FORCE := "terrabela/seasons/force_season"

## Países (ISO 3166) inteiramente ou quase inteiramente no hemisfério sul.
const SOUTHERN_COUNTRIES := [
    "BR", "AR", "CL", "UY", "PY", "BO", "PE", "AU", "NZ", "ZA", "NA", "BW",
    "ZW", "MZ", "MG", "AO", "ZM", "MW", "LS", "SZ", "FJ", "PG", "MU", "RE",
]

## "north" ou "south" a partir de um locale como "pt_BR" ou "es-AR".
static func hemisphere_from_locale(locale: String) -> StringName:
    var parts := locale.replace("-", "_").split("_")
    for index in range(1, parts.size()):
        if String(parts[index]).to_upper() in SOUTHERN_COUNTRIES:
            return &"south"
    return &"north"

## Hemisfério efetivo: configuração do projeto, senão o locale do aparelho.
static func current_hemisphere(mode: String = "") -> StringName:
    if mode == "":
        mode = String(ProjectSettings.get_setting(SETTING_HEMISPHERE, "auto"))
    match mode:
        "north":
            return &"north"
        "south":
            return &"south"
        _:
            return hemisphere_from_locale(OS.get_locale())

static func season_for(month: int, hemisphere: StringName) -> StringName:
    var north: StringName
    match month:
        12, 1, 2:
            north = WINTER
        3, 4, 5:
            north = SPRING
        6, 7, 8:
            north = SUMMER
        _:
            north = AUTUMN
    if hemisphere != &"south":
        return north
    match north:
        WINTER:
            return SUMMER
        SUMMER:
            return WINTER
        SPRING:
            return AUTUMN
        _:
            return SPRING

## Estação de agora no aparelho (respeita force_season e hemisphere_mode).
static func current_season(hemisphere_mode: String = "", forced: String = "") -> StringName:
    if forced == "":
        forced = String(ProjectSettings.get_setting(SETTING_FORCE, ""))
    if StringName(forced) in ALL:
        return StringName(forced)
    var month := int(Time.get_date_dict_from_system()["month"])
    return season_for(month, current_hemisphere(hemisphere_mode))

## Chave de ui.csv com o nome da estação.
static func label_key(season: StringName) -> String:
    return "SEASON_%s" % String(season).to_upper()
