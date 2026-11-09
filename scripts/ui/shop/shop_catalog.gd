extends RefCounted
class_name ShopCatalog
## Catálogo conceitual de IAP. Nenhum item habilitado, sem SKU ou preço real.
## Comprar/creditar requer validação de compra pela plataforma e backend.

const CATEGORIES := [
    {"id": "boosters", "title_key": "SHOP_TAB_BOOSTERS"},
    {"id": "resources", "title_key": "SHOP_TAB_RESOURCES"},
    {"id": "helpers", "title_key": "SHOP_TAB_HELPERS"},
    {"id": "equipment", "title_key": "SHOP_TAB_EQUIPMENT"},
    {"id": "bundles", "title_key": "SHOP_TAB_BUNDLES"}
]

const ICONS := {
    "boost": preload("res://assets/ui/icons/icon_water_drop.png"),
    "seeds": preload("res://assets/ui/icons/icon_seed_bag.png"),
    "wood": preload("res://assets/ui/icon_log.png"),
    "materials": preload("res://assets/ui/icons/icon_crate_full.png"),
    "helper": preload("res://assets/ui/icons/icon_player_portrait.png"),
    "equipment": preload("res://assets/ui/icons/icon_crate_empty.png"),
    "bundle": preload("res://assets/ui/icons/icon_gift.png")
}

## Identificadores internos estáveis, NÃO são SKUs de Google Play/App Store.
## Os campos store_product_id devem continuar vazios até definição comercial.
const PRODUCTS := [
    {"id": "speed_growth", "category": "boosters", "title_key": "SHOP_ITEM_GROWTH", "description_key": "SHOP_DESC_BOOST", "icon": "boost", "store_product_id_android": "", "store_product_id_ios": "", "available": false},
    {"id": "speed_harvest", "category": "boosters", "title_key": "SHOP_ITEM_HARVEST", "description_key": "SHOP_DESC_BOOST", "icon": "boost", "store_product_id_android": "", "store_product_id_ios": "", "available": false},
    {"id": "speed_production", "category": "boosters", "title_key": "SHOP_ITEM_PRODUCTION", "description_key": "SHOP_DESC_BOOST", "icon": "boost", "store_product_id_android": "", "store_product_id_ios": "", "available": false},
    {"id": "pack_seeds", "category": "resources", "title_key": "SHOP_ITEM_SEEDS", "description_key": "SHOP_DESC_RESOURCES", "icon": "seeds", "store_product_id_android": "", "store_product_id_ios": "", "available": false},
    {"id": "pack_wood", "category": "resources", "title_key": "SHOP_ITEM_WOOD", "description_key": "SHOP_DESC_RESOURCES", "icon": "wood", "store_product_id_android": "", "store_product_id_ios": "", "available": false},
    {"id": "pack_materials", "category": "resources", "title_key": "SHOP_ITEM_MATERIALS", "description_key": "SHOP_DESC_RESOURCES", "icon": "materials", "store_product_id_android": "", "store_product_id_ios": "", "available": false},
    {"id": "helper_extra", "category": "helpers", "title_key": "SHOP_ITEM_HELPER_EXTRA", "description_key": "SHOP_DESC_HELPERS", "icon": "helper", "store_product_id_android": "", "store_product_id_ios": "", "available": false},
    {"id": "helper_team", "category": "helpers", "title_key": "SHOP_ITEM_HELPER_TEAM", "description_key": "SHOP_DESC_HELPERS", "icon": "helper", "store_product_id_android": "", "store_product_id_ios": "", "available": false},
    {"id": "helper_upgrade", "category": "helpers", "title_key": "SHOP_ITEM_HELPER_UPGRADE", "description_key": "SHOP_DESC_HELPERS", "icon": "helper", "store_product_id_android": "", "store_product_id_ios": "", "available": false},
    {"id": "equipment_irrigator", "category": "equipment", "title_key": "SHOP_ITEM_IRRIGATOR", "description_key": "SHOP_DESC_EQUIPMENT", "icon": "equipment", "store_product_id_android": "", "store_product_id_ios": "", "available": false},
    {"id": "equipment_collector", "category": "equipment", "title_key": "SHOP_ITEM_COLLECTOR", "description_key": "SHOP_DESC_EQUIPMENT", "icon": "equipment", "store_product_id_android": "", "store_product_id_ios": "", "available": false},
    {"id": "equipment_cart", "category": "equipment", "title_key": "SHOP_ITEM_CART", "description_key": "SHOP_DESC_EQUIPMENT", "icon": "equipment", "store_product_id_android": "", "store_product_id_ios": "", "available": false},
    {"id": "bundle_starter", "category": "bundles", "title_key": "SHOP_ITEM_STARTER", "description_key": "SHOP_DESC_BUNDLES", "icon": "bundle", "store_product_id_android": "", "store_product_id_ios": "", "available": false},
    {"id": "bundle_farmer", "category": "bundles", "title_key": "SHOP_ITEM_FARMER", "description_key": "SHOP_DESC_BUNDLES", "icon": "bundle", "store_product_id_android": "", "store_product_id_ios": "", "available": false},
    {"id": "bundle_season", "category": "bundles", "title_key": "SHOP_ITEM_SEASON", "description_key": "SHOP_DESC_BUNDLES", "icon": "bundle", "store_product_id_android": "", "store_product_id_ios": "", "available": false}
]

static func products_for_category(category_id: String) -> Array[Dictionary]:
    var products: Array[Dictionary] = []
    for item in PRODUCTS:
        if String(item["category"]) == category_id:
            products.append(item)
    return products

static func find_product(product_id: String) -> Dictionary:
    for item in PRODUCTS:
        if String(item["id"]) == product_id:
            return item
    return {}
