extends RefCounted
class_name StoreCatalog
## Fonte de dados da Store V2. Não contém SKU de produção ou lógica de cobrança.

const PRODUCT_IDS := [&"vip_7d", &"remove_ads", &"rural_pack", &"coins_mini", &"coins_medium", &"coins_large", &"helpers_6"]
const PRODUCTS: Array[Dictionary] = [
    {"id": &"vip_7d", "title_key": "STORE_V2_VIP_TITLE", "note_key": "STORE_V2_VIP_NOTE", "desc_key": "STORE_V2_VIP_DESC", "art": "res://assets/store/cards/vip_7d.png", "benefits": {"duration_hours": 168, "coins": 700, "cash": 2000, "coin_interval_hours": 8, "coin_interval_amount": 150, "ad_free": true}},
    {"id": &"remove_ads", "title_key": "STORE_V2_NO_ADS_TITLE", "note_key": "STORE_V2_NO_ADS_NOTE", "desc_key": "STORE_V2_NO_ADS_DESC", "art": "res://assets/store/cards/remove_ads.png", "subscription": true, "billing_period": "P1M", "benefits": {"ad_free": true, "subscription_months": 1, "coins": 300, "weekly_cash": 1000}},
    {"id": &"rural_pack", "title_key": "STORE_V2_RURAL_TITLE", "note_key": "STORE_V2_RURAL_NOTE", "desc_key": "STORE_V2_RURAL_DESC", "art": "res://assets/store/cards/rural_pack.png", "benefits": {"coins": 300, "bricks": 60, "wood": 200}},
    {"id": &"coins_mini", "title_key": "STORE_V2_COINS_MINI_TITLE", "desc_key": "STORE_V2_COINS_MINI_DESC", "art": "res://assets/store/cards/coins_mini.png", "benefits": {"coins": 120}},
    {"id": &"coins_medium", "title_key": "STORE_V2_COINS_MEDIUM_TITLE", "desc_key": "STORE_V2_COINS_MEDIUM_DESC", "art": "res://assets/store/cards/coins_medium.png", "benefits": {"coins": 600}},
    {"id": &"coins_large", "title_key": "STORE_V2_COINS_LARGE_TITLE", "desc_key": "STORE_V2_COINS_LARGE_DESC", "art": "res://assets/store/cards/coins_large.png", "benefits": {"coins": 1500}},
    {"id": &"helpers_6", "title_key": "STORE_V2_HELPERS_TITLE", "note_key": "STORE_V2_HELPERS_NOTE", "desc_key": "STORE_V2_HELPERS_DESC", "art": "res://assets/store/cards/helpers_6.png", "benefits": {"helper_count": 6, "duration_hours": 0, "activities": []}}
]
const DEMO_PRICES := {
    "BR": {&"vip_7d": "R$ 82,99", &"remove_ads": "R$ 29,99", &"rural_pack": "R$ 27,99", &"coins_mini": "R$ 9,90", &"coins_medium": "R$ 29,99", &"coins_large": "R$ 79,90", &"helpers_6": "R$ 79,99"},
    "US": {&"vip_7d": "US$ 16.99", &"remove_ads": "US$ 8.99", &"rural_pack": "US$ 5.49", &"coins_mini": "US$ 1.99", &"coins_medium": "US$ 7.99", &"coins_large": "US$ 15.99", &"helpers_6": "US$ 5.99"},
    "ES_DEMO": {&"vip_7d": "US$ 16.99", &"remove_ads": "US$ 8.99", &"rural_pack": "US$ 5.49", &"coins_mini": "US$ 1.99", &"coins_medium": "US$ 7.99", &"coins_large": "US$ 15.99", &"helpers_6": "US$ 5.99"}
}

static func all() -> Array[Dictionary]: return PRODUCTS.duplicate(true)
static func find(product_id: StringName) -> Dictionary:
    for product in PRODUCTS:
        if product["id"] == product_id: return product.duplicate(true)
    return {}
static func art_for(product: Dictionary) -> Texture2D:
    var path := String(product.get("art", product.get("art_fallback", "")))
    if path.is_empty(): path = String(product.get("art_fallback", ""))
    return load(path) as Texture2D if not path.is_empty() else null
static func demo_price(product_id: StringName, region: String) -> String:
    return String(DEMO_PRICES.get(region, {}).get(product_id, ""))
