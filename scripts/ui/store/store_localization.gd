extends RefCounted
class_name StoreLocalization
## Região comercial é independente do idioma exibido.
const DEMO_REGIONS := ["BR", "US", "ES_DEMO"]
static var _demo_region := "BR"
static func set_demo_region(region: String) -> void:
    if region in DEMO_REGIONS: _demo_region = region
static func get_demo_region() -> String: return _demo_region
static func price_for(product_id: StringName, platform_price: String = "") -> String:
    return platform_price if not platform_price.is_empty() else StoreCatalog.demo_price(product_id, _demo_region)
static func supported_locale(locale: String) -> String:
    if locale.begins_with("en"): return "en_US"
    if locale.begins_with("es"): return "es_ES"
    return "pt_BR"
