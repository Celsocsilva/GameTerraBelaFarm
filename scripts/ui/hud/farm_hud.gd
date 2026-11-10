extends CanvasLayer
class_name FarmHUD
## HUD da fazenda (UI-004). Só exibe estados que já existem no jogo:
## - dinheiro: Wallet (saldo recolhido das pilhas da base de dinheiro);
## - tomates e caixas: HarvestInventory (mochila);
## - vendas: SalesController.sale_completed (aviso de venda);
## - nível e missão: PlayerLevel e MissionTracker.
## Todo número é um Label; os PNGs de assets/ui são só fundos e ícones.
## Os componentes são desenhados no tamanho dos PNGs e reduzidos por `scale`.
## O layout é refeito a cada mudança de tamanho (paisagem e retrato).
## FV-HUD-002: o topo direito virou um bloco preto translúcido (HudWalletBar)
## só com dinheiro e moedas de ouro; tomates/caixas saíram do topo (os nós
## continuam, ocultos, para a API e os testes). A engrenagem de configurações
## fica acima da Loja. Loja e configurações abrem numa camada própria
## (ModalLayer, layer = MODAL_LAYER) acima de TODA a UI, inclusive do joystick.

signal store_pressed()
signal settings_pressed()

const SALE_POPUP_SCENE := preload("res://scenes/ui/hud/components/SalePopup.tscn")
const SHOP_MODAL_SCENE := preload("res://scenes/ui/shop/FarmShopModal.tscn")
## Camada das modais (loja, configurações): acima do HUD (layer 1) e de tudo
## que é filho dele (joystick).
const MODAL_LAYER := 50
const WALLET_SCALE := 0.5
const SETTINGS_SCALE := 0.5
const MARGIN := 16.0
## Tamanho do SalePopup.tscn (field_input_wide.png v5).
const SALE_POPUP_SCENE_SIZE := Vector2(559, 139)
const GAP := 10.0
const LEVEL_SCALE := 0.42
const MISSION_SCALE := 0.46
const COUNTER_SCALE := 0.72
const BANNER_SCALE := 0.42
const STORE_SCALE := 0.42
const SALE_POPUP_SCALE := 0.5
## Em retrato (tela mais alta que larga) os componentes crescem para continuarem
## legíveis no celular em pé; os contadores encolhem se não couberem.
const PORTRAIT_BOOST := 1.35
## Chave do aviso de mochila cheia (localization/ui.csv).
const FULL_BACKPACK_MESSAGE := "BACKPACK_FULL"

@onready var root_control: Control = $Root
@onready var level_panel: PlayerLevelPanel = $Root/PlayerLevelPanel
@onready var mission_panel: MissionPanel = $Root/MissionPanel
@onready var tomato_counter: HudCounter = $Root/Counters/TomatoCounter
@onready var crate_counter: HudCounter = $Root/Counters/CrateCounter
@onready var counters: Control = $Root/Counters
@onready var info_banner: InfoBanner = $Root/InfoBanner
@onready var store_button: StoreButton = $Root/StoreButton
@onready var sale_popups: Control = $Root/SalePopups
@onready var reward_popup: RewardPopup = $Root/RewardPopup
## Modal grande para avisos e explicações (UI-MESSAGE-001); o RewardPopup fica só para recompensas.
@onready var message_popup: MessagePopup = $Root/MessagePopup

var wallet: Wallet
var inventory: HarvestInventory
var player_level: PlayerLevel
var missions: MissionTracker
var _banner_timer: SceneTreeTimer
var _ui_scale := 1.0
var shop_modal: FarmShopModal
var settings_modal: FarmSettingsModal
var settings_button: SettingsButton
var wallet_bar: HudWalletBar
var modal_layer: CanvasLayer
## FARM-003: chave + argumentos do aviso atual da faixa, para retraduzir na hora
## em que o idioma muda nas Configurações.
var _banner_key := ""
var _banner_args: Array = []

func _ready() -> void:
    root_control.resized.connect(layout)
    FarmSettings.load_and_apply()
    store_button.pressed.connect(_on_store_pressed)
    wallet_bar = HudWalletBar.new()
    wallet_bar.name = "WalletBar"
    counters.add_child(wallet_bar)
    # Tomates e caixas saem do topo direito (a mochila aparece nas costas do
    # fazendeiro e o aviso de mochila cheia continua na faixa).
    tomato_counter.visible = false
    crate_counter.visible = false
    settings_button = SettingsButton.new()
    settings_button.name = "SettingsButton"
    root_control.add_child(settings_button)
    settings_button.pressed.connect(_on_settings_pressed)
    modal_layer = CanvasLayer.new()
    modal_layer.name = "ModalLayer"
    modal_layer.layer = MODAL_LAYER
    add_child(modal_layer)
    var modal_root := Control.new()
    modal_root.name = "ModalRoot"
    modal_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    modal_layer.add_child(modal_root)
    modal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shop_modal = SHOP_MODAL_SCENE.instantiate() as FarmShopModal
    modal_root.add_child(shop_modal)
    settings_modal = FarmSettingsModal.new()
    settings_modal.name = "FarmSettingsModal"
    modal_root.add_child(settings_modal)
    reward_popup.collected.connect(_on_reward_collected)
    layout()

func setup(p_wallet: Wallet, p_inventory: HarvestInventory, sales: SalesController, level: PlayerLevel, tracker: MissionTracker) -> void:
    wallet = p_wallet
    inventory = p_inventory
    player_level = level
    missions = tracker
    wallet.balance_changed.connect(_on_balance_changed)
    wallet.gold_changed.connect(_on_gold_changed)
    inventory.amount_changed.connect(_on_inventory_changed)
    sales.sale_completed.connect(_on_sale_completed)
    level.changed.connect(_on_level_changed)
    tracker.mission_changed.connect(_on_mission_changed)
    tracker.progress_changed.connect(_on_mission_progress)
    tracker.mission_completed.connect(_on_mission_completed)
    refresh()

## Relê todos os estados (início de jogo ou depois de carregar um save).
func refresh() -> void:
    if wallet:
        wallet_bar.set_money(wallet.get_balance(), false)
        wallet_bar.set_gold(wallet.get_gold(), false)
    if inventory:
        _update_inventory(false)
    if player_level:
        level_panel.set_level(player_level.level, player_level.xp, player_level.xp_to_next())
    if missions:
        _on_mission_changed(missions.get_current())
        mission_panel.set_progress(missions.progress, missions.get_target())

## API direta (prompt UI v5). No jogo os valores chegam pelos sinais de Wallet
## e HarvestInventory; estes métodos servem para preview e testes.
func set_money(value: int) -> void:
    wallet_bar.set_money(value)

func set_gold(value: int) -> void:
    wallet_bar.set_gold(value)

func set_tomatoes(current: int, maximum: int) -> void:
    tomato_counter.set_ratio(current, maximum)

func set_crates(current: int, maximum: int) -> void:
    crate_counter.set_ratio(current, maximum)

func set_mission(title: String, current: int, target: int) -> void:
    mission_panel.set_mission_progress(title, current, target)

func get_money_text() -> String:
    return wallet_bar.get_money_text()

func get_gold_text() -> String:
    return wallet_bar.get_gold_text()

func get_tomato_text() -> String:
    return tomato_counter.get_value_text()

func get_crate_text() -> String:
    return crate_counter.get_value_text()

func get_banner_message() -> String:
    return info_banner.get_message()

func get_active_sale_popups() -> Array[SalePopup]:
    var popups: Array[SalePopup] = []
    for child in sale_popups.get_children():
        if child is SalePopup and not child.is_queued_for_deletion():
            popups.append(child)
    return popups

## Layout responsivo: nível e missão à esquerda, contadores à direita, loja no
## canto inferior direito; o joystick (adicionado pelo FarmWorld) fica embaixo
## à esquerda. Os contadores encolhem se a largura não couber.
func layout() -> void:
    if is_node_ready():
        layout_for(root_control.size)

## Posiciona os componentes para uma área lógica (também usado nos testes).
func layout_for(area: Vector2) -> void:
    _ui_scale = PORTRAIT_BOOST if area.y > area.x else 1.0
    var k := _ui_scale
    level_panel.scale = Vector2.ONE * LEVEL_SCALE * k
    level_panel.position = Vector2(MARGIN, MARGIN)
    var level_size := level_panel.size * LEVEL_SCALE * k
    mission_panel.scale = Vector2.ONE * MISSION_SCALE * k
    mission_panel.position = Vector2(MARGIN, MARGIN + level_size.y + GAP)

    # Topo direito: só o bloco translúcido de dinheiro + ouro. Encolhe se não
    # couber ao lado do painel de nível.
    var available := area.x - (MARGIN + level_size.x + GAP * 2.0) - MARGIN
    var wallet_scale := minf(WALLET_SCALE * k, available / HudWalletBar.DESIGN_SIZE.x)
    counters.position = Vector2.ZERO
    wallet_bar.scale = Vector2.ONE * wallet_scale
    var wallet_size := HudWalletBar.DESIGN_SIZE * wallet_scale
    wallet_bar.position = Vector2(area.x - MARGIN - wallet_size.x, MARGIN + maxf(0.0, (level_size.y - wallet_size.y) * 0.5))
    var counters_bottom := wallet_bar.position.y + wallet_size.y

    info_banner.scale = Vector2.ONE * BANNER_SCALE * k
    var banner_size := info_banner.size * BANNER_SCALE * k
    var banner_left := MARGIN + mission_panel.size.x * MISSION_SCALE * k + GAP
    if k > 1.0:
        # Retrato: faixa embaixo do painel de missão, à esquerda (há espaço vertical).
        info_banner.position = Vector2(MARGIN, mission_panel.position.y + mission_panel.size.y * MISSION_SCALE * k + GAP)
    else:
        var banner_x := clampf((area.x - banner_size.x) * 0.5, banner_left, maxf(banner_left, area.x - MARGIN - banner_size.x))
        info_banner.position = Vector2(banner_x, counters_bottom + GAP)

    store_button.scale = Vector2.ONE * STORE_SCALE * k
    var store_size := store_button.size * STORE_SCALE * k
    store_button.position = area - store_size - Vector2(MARGIN, MARGIN)
    # Engrenagem logo acima da Loja, centrada nela.
    settings_button.scale = Vector2.ONE * SETTINGS_SCALE * k
    var settings_size := SettingsButton.DESIGN_SIZE * SETTINGS_SCALE * k
    settings_button.position = Vector2(store_button.position.x + (store_size.x - settings_size.x) * 0.5, store_button.position.y - settings_size.y - GAP)

    # Avisos de venda alinhados à direita, embaixo dos contadores, fora da faixa.
    var popup_width := SALE_POPUP_SCENE_SIZE.x * SALE_POPUP_SCALE * k
    sale_popups.position = Vector2(area.x - MARGIN - popup_width, counters_bottom + GAP)

func _on_balance_changed(balance: int, _delta: int) -> void:
    wallet_bar.set_money(balance)

func _on_gold_changed(gold: int, _delta: int) -> void:
    wallet_bar.set_gold(gold)

func _on_inventory_changed(_item: StringName, _amount: int) -> void:
    _update_inventory(true)

func _update_inventory(animate: bool) -> void:
    # FV-WOOD-001: o contador de tomates conta só tomates (toras não entram).
    tomato_counter.set_ratio(inventory.get_amount(HarvestInventory.DEFAULT_ITEM), inventory.get_capacity(), animate)
    crate_counter.set_ratio(inventory.get_crate_count(), inventory.max_crates, animate)
    if inventory.is_full():
        _show_banner_key(FULL_BACKPACK_MESSAGE, [])
    elif _banner_key == FULL_BACKPACK_MESSAGE:
        _hide_banner()

## Aviso de venda abaixo do contador de dinheiro; vários avisos se empilham.
func _on_sale_completed(_customer: Customer, crates: int, _units: int, money: int) -> void:
    show_sale_popup(money, crates)

func show_sale_popup(money: int, crates: int) -> SalePopup:
    var popup := SALE_POPUP_SCENE.instantiate() as SalePopup
    sale_popups.add_child(popup)
    popup.setup(money, crates)
    var stacked := get_active_sale_popups().size() - 1
    var popup_scale := SALE_POPUP_SCALE * _ui_scale
    # play() escala em torno do centro: compensa para a borda visível começar em (0, y).
    popup.position = Vector2(0.0, stacked * popup.size.y * popup_scale * 1.05) - popup.size * (1.0 - popup_scale) * 0.5
    popup.play(popup_scale)
    return popup

func _on_level_changed(level: int, xp: int, xp_to_next: int) -> void:
    level_panel.set_level(level, xp, xp_to_next)
    UiStyle.pulse(level_panel.level_label, 0.25)

func _on_mission_changed(mission: Dictionary) -> void:
    mission_panel.set_mission(String(mission["title"]), mission["icon"], int(mission["target"]), int(mission["reward"]))

func _on_mission_progress(progress: int, target: int) -> void:
    mission_panel.set_progress(progress, target)

func _on_mission_completed(mission: Dictionary) -> void:
    reward_popup.show_reward(RewardPopup.DEFAULT_TITLE, RewardPopup.DEFAULT_MESSAGE, int(mission["reward"]))

func _on_reward_collected(_amount: int) -> void:
    if missions:
        missions.claim_reward()

func _on_settings_pressed() -> void:
    settings_pressed.emit()
    if shop_modal and shop_modal.is_shop_open():
        shop_modal.close_shop()
    if settings_modal:
        settings_modal.open_settings()

## Alguma modal (loja ou configurações) aberta por cima do jogo.
func is_modal_open() -> bool:
    return (shop_modal != null and shop_modal.is_shop_open()) or (settings_modal != null and settings_modal.is_open())

func _on_store_pressed() -> void:
    if settings_modal and settings_modal.is_open():
        settings_modal.close_settings()
    store_pressed.emit()
    if shop_modal:
        shop_modal.open_shop()

## Modal grande (moldura com laço vermelho). Textos curtos: título de 1 a 2
## palavras e 1 a 2 frases. Aceita chaves de localization/ui.csv.
func show_message(title: String, message: String, button_text: String = MessagePopup.DEFAULT_BUTTON) -> MessagePopup:
    message_popup.show_message(title, message, button_text)
    return message_popup

## Mensagem temporária na faixa floral. `text` é de preferência uma chave de
## localization/ui.csv e `args` os valores do %d/%s (Strings também são
## traduzidas; "@lower:CHAVE" em minúsculas): assim a faixa troca de idioma na
## hora. Texto já pronto também funciona (fica como está).
func show_banner(text: String, seconds: float, args: Array = []) -> void:
    _show_banner_key(text, args)
    _banner_timer = get_tree().create_timer(seconds)
    var timer := _banner_timer
    var key := text
    timer.timeout.connect(func() -> void:
        if _banner_timer == timer and _banner_key == key:
            _hide_banner()
            if inventory and inventory.is_full():
                _show_banner_key(FULL_BACKPACK_MESSAGE, []))

func _show_banner_key(key: String, args: Array) -> void:
    _banner_key = key
    _banner_args = args
    info_banner.show_message(UiStyle.tr_format(key, args))

func _hide_banner() -> void:
    _banner_key = ""
    _banner_args = []
    info_banner.hide_message()

func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and info_banner.visible and not _banner_key.is_empty():
        info_banner.show_message(UiStyle.tr_format(_banner_key, _banner_args))
