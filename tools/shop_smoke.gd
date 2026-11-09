extends SceneTree
## FV-SHOP-001: contrato do catálogo + abertura do HUD + segurança pré-IAP.
## Uso: godot --headless --path . -s tools/shop_smoke.gd

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("SHOP_SMOKE_FAIL " + message)
    print("SHOP_SMOKE_FAIL ", message)
    quit(1)

func _run() -> void:
    if ShopCatalog.PRODUCTS.size() != 15 or ShopCatalog.CATEGORIES.size() != 5:
        return _fail("catálogo deve conter 15 itens em 5 categorias")
    var ids := {}
    for product in ShopCatalog.PRODUCTS:
        var product_id := String(product["id"])
        if ids.has(product_id):
            return _fail("ID duplicado: " + product_id)
        ids[product_id] = true
        if bool(product["available"]):
            return _fail("produto habilitado sem integração: " + product_id)
        if not String(product["store_product_id_android"]).is_empty() or not String(product["store_product_id_ios"]).is_empty():
            return _fail("SKU não aprovado: " + product_id)
        if not ShopCatalog.ICONS.has(String(product["icon"])):
            return _fail("ícone inválido: " + product_id)

    var world := (load("res://scenes/world/farm_world.tscn") as PackedScene).instantiate() as FarmWorld
    root.add_child(world)
    await process_frame
    world.harvest_controller.enabled = false
    world.customer_queue.set_process(false)
    world.sales_controller.set_process(false)
    var shop := world.hud.shop_modal
    if shop == null or shop.is_shop_open():
        return _fail("modal inicial inexistente ou aberta")

    var before := world.wallet.get_balance()
    world.hud.store_button.pressed.emit()
    if not shop.is_shop_open() or shop.get_selected_product_id() != "speed_growth":
        return _fail("abertura pelo botão da loja")
    await process_frame
    await process_frame
    var area := Rect2(Vector2.ZERO, shop.size)
    if not area.encloses(shop._card.get_rect()):
        return _fail("cartão da loja sai da tela: %s em %s" % [shop._card.get_rect(), area])
    for category in ShopCatalog.CATEGORIES:
        var id := String(category["id"])
        shop._choose_category(id)
        var visible_products := ShopCatalog.products_for_category(id)
        if visible_products.size() != 3 or shop._product_grid.get_child_count() != 3:
            return _fail("categoria " + id)
        shop._select_product(String(visible_products[2]["id"]))
        if shop.get_selected_product_id() != String(visible_products[2]["id"]):
            return _fail("seleção em " + id)
        if not shop._purchase_button.disabled:
            return _fail("compra indevidamente habilitada em " + id)
    if world.wallet.get_balance() != before:
        return _fail("navegar no catálogo alterou o saldo")
    for locale in ["pt_BR", "es", "en"]:
        TranslationServer.set_locale(locale)
        await process_frame
        if shop._title.text == "SHOP_TITLE":
            return _fail("chave de tradução não importada: " + locale)
        if shop._purchase_button.disabled == false:
            return _fail("compras habilitadas em " + locale)
        print("SHOP_LOCALE ", locale, " title=", shop._title.text)
    TranslationServer.set_locale("pt_BR")

    var cancel := InputEventAction.new()
    cancel.action = "ui_cancel"
    cancel.pressed = true
    shop._unhandled_input(cancel)
    if shop.is_shop_open():
        return _fail("Escape não fecha a loja")
    print("SHOP_SMOKE_OK")
    quit(0)
