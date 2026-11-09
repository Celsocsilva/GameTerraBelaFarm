extends Node3D
class_name FarmWorld

@export_category("World Scale")
@export var farm_size: float = 64.0
@export var camera_orthographic_size: float = 12.0
@export var camera_height: float = 14.0
@export var camera_distance: float = 14.0
@export var camera_follow_speed: float = 5.0
@export var camera_dead_zone: Vector2 = Vector2(3.5, 2.5)
@export var camera_limits: Vector2 = Vector2(26.0, 26.0)

const JOYSTICK_SCENE := preload("res://scenes/ui/virtual_joystick.tscn")
const SEED_THROW_SCENE := preload("res://scenes/vfx/SeedThrow.tscn")
const PLANTING_GRID_SCRIPT := preload("res://scripts/farming/planting_grid.gd")
const CROP_PLANT_SCRIPT := preload("res://scripts/farming/crop_plant.gd")
const SOIL_TEXTURE := preload("res://assets/textures/soil/plowed_soil_three_furrows.png")
const HARVEST_INVENTORY_SCRIPT := preload("res://scripts/farming/harvest_inventory.gd")
const HARVEST_CONTROLLER_SCRIPT := preload("res://scripts/farming/harvest_controller.gd")
const BACKPACK_CRATES_SCRIPT := preload("res://scripts/player/backpack_crates.gd")
const SALES_COUNTER_SCRIPT := preload("res://scripts/farming/sales_counter.gd")
const MONEY_STACK_SCRIPT := preload("res://scripts/economy/money_stack.gd")
const WALLET_SCRIPT := preload("res://scripts/economy/wallet.gd")
## Mãos do fazendeiro (frente é -Z local): de onde as caixas pulam para o balcão.
const HANDS_OFFSET := Vector3(0.0, 1.1, -0.55)
const SALES_CONTROLLER_SCRIPT := preload("res://scripts/commerce/sales_controller.gd")
const CUSTOMER_QUEUE_SCRIPT := preload("res://scripts/customers/customer_queue.gd")
const FARM_HUD_SCENE := preload("res://scenes/ui/hud/FarmHUD.tscn")
const PLAYER_LEVEL_SCRIPT := preload("res://scripts/progression/player_level.gd")
const MISSION_TRACKER_SCRIPT := preload("res://scripts/progression/mission_tracker.gd")
const COZY_ENVIRONMENT_SCRIPT := preload("res://scripts/world/cozy_environment.gd")
## ENV-002: rio modular com ponte de madeira e ponte de pedra (lado oeste).
const RIVER_SYSTEM_SCENE := preload("res://scenes/world/river/RiverSystem.tscn")
## FV-HELPER-001: ajudante contratável que colhe, empilha na parcela de 10% e replanta.
const HELPER_HIRING_SCRIPT := preload("res://scripts/helpers/helper_hiring.gd")
const FARM_HELPER_SCRIPT := preload("res://scripts/helpers/farm_helper.gd")
const TOMATO_PILE_SCRIPT := preload("res://scripts/farming/tomato_pile.gd")
const HELPER_PAD_SCRIPT := preload("res://scripts/helpers/helper_pad.gd")
## FV-PROPS-001: placa de madeira com o nome da cultura em cada terreno de plantio.
const CROP_SIGN_SCRIPT := preload("res://scripts/farming/crop_sign.gd")
## FV-WOOD-001: plantações de eucalipto (corte, toras e venda no balcão).
const EUCALYPTUS_GROVE_SCRIPT := preload("res://scripts/forestry/eucalyptus_grove.gd")
## Distância (m) entre as fileiras de eucalipto e a borda do terreno/rio.
const EUCALYPTUS_EDGE_GAP := 1.9
## Espaço entre duas árvores da mesma fileira (centro a centro).
const EUCALYPTUS_SPACING := 2.6
## Distância da fileira do rio à margem leste da água (margem ilustrada incluída).
const EUCALYPTUS_RIVER_GAP := 1.2
## FV-WOOD-002: floresta no canto sudoeste, ao sul da curva do rio, até a
## borda do mapa (inclusive além da cerca do balcão). Grade hexagonal.
const EUCALYPTUS_FOREST := Rect2(-30.5, 12.0, 18.0, 18.5)
const EUCALYPTUS_FOREST_STEP := Vector2(2.4, 2.1)
## Placa no canto da frente (+Z, lado do balcão) à esquerda do terreno, na
## grama, fora do solo: não cobre as plantas nem o caminho até o balcão.
const CROP_SIGN_OFFSET := Vector2(-0.9, 0.55)
## Plataforma de contratação: no chão, logo antes (lado do balcão, +Z) da parcela.
const HELPER_PAD_GAP := 0.9

## Mochila nas costas do fazendeiro (a frente do fazendeiro é -Z local).
const BACKPACK_OFFSET := Vector3(0.0, 1.1, 0.62)

const SEED_HAND_OFFSET := Vector3(0.45, 1.15, -0.25)

const PLANTING_PLOT_COUNT := 3
const PLANTING_COLUMNS := 3
const PLANTING_ROWS := 1
## Área de plantio 1,7x a anterior (largura 3,8 m por tira): cada lado cresce
## por sqrt(1,7), mantendo a proporção da arte das tiras.
const PLANTING_AREA_SCALE := 1.7
const PLANTING_LINEAR_SCALE := sqrt(PLANTING_AREA_SCALE)
const PLANTING_PLOT_WIDTH := 3.8 * PLANTING_LINEAR_SCALE
## Sobreposição entre tiras vizinhas para esconder a margem transparente do PNG.
const PLANTING_PLOT_OVERLAP := 0.35 * PLANTING_LINEAR_SCALE
# A câmera olha o chão a 45° (camera_height == camera_distance), o que encurta
# o eixo Z na tela por sin(45°). O comprimento é compensado por 1/sin(45°) para
# que a tira apareça na proporção da arte, sem aspecto "comprimido".
const PLANTING_VIEW_PITCH_DEGREES := 45.0
const PLANTING_LENGTH_STRETCH := 1.0 / sin(deg_to_rad(PLANTING_VIEW_PITCH_DEGREES))
# Borda do canteiro mais próxima da casa/fazendeiro; o canteiro cresce para +Z.
# FV-FARM-008: o terreno de tomate fica a 3x a distância anterior até o balcão.
# Distância = faixa de grama entre a borda do canteiro (lado do balcão) e a
# frente do balcão; antes eram 4,02 m (borda em z = 2,3). O canteiro recua para
# -Z mantendo tamanho, número de tiras e células.
const PREVIOUS_COUNTER_GAP := 4.0245
const COUNTER_GAP_MULTIPLIER := 3.0
const PLANTING_NEAR_EDGE_Z := 2.3 - PREVIOUS_COUNTER_GAP * (COUNTER_GAP_MULTIPLIER - 1.0)
## Fazendeiro nasce ao norte do canteiro (antes nascia em z = 0, hoje dentro dele).
const FARMER_SPAWN := Vector3(0.0, 1.0, PLANTING_NEAR_EDGE_Z - 2.0)
## Cerca e galpão provisórios recuados para fora do canteiro e longe do caminho
## da ponte de madeira (z = -9,6).
const FENCE_POSITION := Vector3(-5.0, 0.6, -12.5)
const FENCE_SIZE := Vector3(5.0, 1.2, 0.35)
const BUILDING_POSITION := Vector3(5.0, 1.1, -13.0)
const BUILDING_SIZE := Vector3(3.2, 2.2, 3.0)
## FV-FARM-008: parcela extra com a mesma textura de solo e 10% da área do
## terreno de tomate. É quadrada NA TELA: 2 tiras da mesma arte (sem distorcer
## o PNG) dão largura ~= altura vista pela câmera a 45°. Por ora é só visual
## (sem células de plantio); fica a leste do canteiro, longe do rio (oeste).
const EXTRA_PLOT_AREA_RATIO := 0.10
const EXTRA_PLOT_STRIPS := 2
const EXTRA_PLOT_GAP := 2.0
## CROP-AREAS-001: áreas próprias de outras culturas, bem afastadas umas das
## outras e do tomate. Cada uma tem o canteiro (tiras com a mesma arte do solo),
## a placa da cultura (CropSign, automática pelo meta "crop"), a parcela de
## estoque de 10% com a pilha da cultura (TomatoPile centrada) e a plataforma
## de contratar o ajudante no chão (HelperPad + HelperHiring próprios).
## `origin` é o canto de trás à esquerda (menor X e menor Z) do canteiro.
## CROP-CORN-001: culturas em PLANTABLE_CROPS (o milho) ganham PlantingGrid,
## HarvestController e ajudante próprios; as outras (abóbora) seguem sem
## plantio, com a plataforma bloqueada ("Em breve").
const CROP_AREAS := [
    {"crop": &"corn", "origin": Vector2(19.0, -8.0)},
    {"crop": &"pumpkin", "origin": Vector2(-4.0, -30.0)},
]
const CROP_AREA_STRIPS := 2
## CROP-CORN-001: áreas extras que já têm arte de crescimento e plantio.
const PLANTABLE_CROPS: Array[StringName] = [&"corn"]
## Fileiras por tira nas áreas extras (tiras 0,75x: ~1,4 m entre covas).
const CROP_AREA_ROWS := 6
## Escala linear das tiras das novas áreas em relação às tiras do tomate.
const CROP_AREA_SCALE := 0.75
# Os módulos são contíguos nos dois eixos: uma área de cultivo é um agrupamento sem vãos.
# Sobreposição controlada para ocultar qualquer margem transparente residual do PNG.
var planting_plot_size: Vector2
var planting_plot_spacing: Vector2
var planting_visible_width_ratio: float

@onready var farmer: FarmerController = $Farmer
var camera: Camera3D
var camera_focus: Vector3
var planting_grid: PlantingGrid
var harvest_inventory: HarvestInventory
var harvest_controller: HarvestController
var backpack: BackpackCrates
var sales_counter: SalesCounter
var money_stack: MoneyStack
## Saldo recolhido das pilhas de dinheiro (HUD); para compras futuras.
var wallet: Wallet
var sales_controller: SalesController
var customer_queue: CustomerQueue
## cell_id -> CropPlant, para a colheita localizar a planta de cada célula.
var crops: Dictionary = {}
## HUD UI-004 (contadores, nível, missão e avisos de venda).
var hud: FarmHUD
var player_level: PlayerLevel
var mission_tracker: MissionTracker
var cozy_environment: CozyEnvironment
var river_system: RiverSystem
## Parcela extra de solo (FV-FARM-008), apenas visual.
var extra_planting_area: Node3D
## Ajudante (FV-HELPER-001): graduação/contratação, o ajudante 3D e a pilha de
## caixas na parcela extra.
var helper_hiring: HelperHiring
var farm_helper: FarmHelper
var tomato_pile: TomatoPile
var helper_pad: HelperPad
## CROP-AREAS-001: um item por área extra de cultura:
## {"crop", "area" (Node3D), "field" (Rect2), "stock" (Rect2), "stock_area" (Node3D),
##  "pad_rect" (Rect2), "pile" (TomatoPile), "hiring" (HelperHiring), "pad" (HelperPad)}.
var crop_areas: Array[Dictionary] = []
## CROP-CORN-001: grade, colheita e ajudante de cada cultura extra plantável
## (crop -> PlantingGrid / HarvestController / FarmHelper).
var crop_grids: Dictionary = {}
var crop_harvesters: Dictionary = {}
var crop_helpers: Dictionary = {}
var _crop_busy_banner_shown := false
## Placas de cultura (FV-PROPS-001), uma por terreno de plantio.
var crop_signs: Array[CropSign] = []
## FV-WOOD-001: eucaliptos nas bordas dos canteiros e junto ao rio.
var eucalyptus_grove: EucalyptusGrove
var _wood_banner_shown := false
## Origem do punhado de sementes quando quem semeia é o ajudante.
var _seed_origin_override: Variant = null

func _ready() -> void:
    var texture_size := SOIL_TEXTURE.get_size()
    planting_plot_size = Vector2(PLANTING_PLOT_WIDTH, PLANTING_PLOT_WIDTH * texture_size.y / texture_size.x * PLANTING_LENGTH_STRETCH)
    planting_plot_spacing = Vector2(PLANTING_PLOT_WIDTH - PLANTING_PLOT_OVERLAP, planting_plot_size.y)
    planting_visible_width_ratio = clampf(float(SOIL_TEXTURE.get_image().get_used_rect().size.x) / texture_size.x, 0.5, 1.0)
    farmer.position = FARMER_SPAWN
    _build_environment()
    _build_ground()
    _build_planting_area()
    _build_extra_planting_area()
    _build_crop_areas()
    _build_planting_grid()
    _build_crop_signs()
    _build_obstacles()
    _build_river()
    _build_camera()
    _build_harvest()
    _build_sales_counter()
    _build_helper()
    _build_eucalyptus()
    _build_cozy_environment()
    _build_hud()
    _prewarm_seed_throw()
    camera_focus = farmer.global_position

func _process(delta: float) -> void:
    if camera and farmer:
        _update_camera_focus(delta)
    if planting_grid and farmer:
        planting_grid.process_farmer_position(farmer.global_position, delta)
        for grid in crop_grids.values():
            (grid as PlantingGrid).process_farmer_position(farmer.global_position, delta)
    if sales_counter and farmer:
        sales_counter.process_farmer_position(farmer.global_position, get_farmer_hands_position())
    if money_stack and farmer:
        money_stack.collect_at(farmer.global_position, wallet)
    if tomato_pile and farmer:
        tomato_pile.process_farmer_position(farmer.global_position, harvest_inventory, backpack.intake_marker)
    if helper_pad and farmer:
        helper_pad.process_farmer_position(farmer.global_position, delta)
    if farmer:
        for entry in crop_areas:
            if entry.has("pad"):
                (entry["pad"] as HelperPad).process_farmer_position(farmer.global_position, delta)
            if entry.has("pile"):
                (entry["pile"] as TomatoPile).process_farmer_position(farmer.global_position, harvest_inventory, backpack.intake_marker)
    if eucalyptus_grove and farmer:
        eucalyptus_grove.process_farmer_position(farmer.global_position, delta)
        _update_wood_hint()
    if farmer and harvest_inventory:
        _update_crop_busy_hint()

func get_farmer_hands_position() -> Vector3:
    return farmer.global_transform * HANDS_OFFSET

## Rio, pontes e bloqueio da água (ENV-002). Montado antes da decoração para
## que a máscara do rio mantenha flores, pedras e árvores fora da água,
## das margens ilustradas e do caminho das pontes.
func _build_river() -> void:
    river_system = RIVER_SYSTEM_SCENE.instantiate() as RiverSystem
    river_system.name = "RiverSystem"
    add_child(river_system)

func _build_cozy_environment() -> void:
    cozy_environment = COZY_ENVIRONMENT_SCRIPT.new() as CozyEnvironment
    cozy_environment.name = "CozyEnvironment"
    if river_system:
        cozy_environment.reserved_areas.append(river_system)
    for rect in get_obstacle_rects():
        cozy_environment.blocked_rects.append(rect)
    if eucalyptus_grove:
        for tree in eucalyptus_grove.trees:
            cozy_environment.blocked_rects.append(Rect2(Vector2(tree.position.x, tree.position.z) - Vector2(1.3, 1.0), Vector2(2.6, 2.0)))
    add_child(cozy_environment)
    cozy_environment.setup(
        $Ground/GrassSurface as MeshInstance3D,
        farm_size,
        get_planting_area_half_width(),
        PLANTING_NEAR_EDGE_Z,
        PLANTING_NEAR_EDGE_Z + planting_plot_size.y,
        sales_counter.position
    )

## Balcão de vendas no rodapé do mapa, fila de clientes atrás dele (+Z) e a
## base de dinheiro 3 x 5 ao lado, no lado do fazendeiro (-Z).
func _build_sales_counter() -> void:
    sales_counter = SALES_COUNTER_SCRIPT.new() as SalesCounter
    sales_counter.name = "SalesCounter"
    add_child(sales_counter)
    sales_counter.place_at_map_foot(farm_size)
    sales_counter.setup(harvest_inventory)
    customer_queue = CUSTOMER_QUEUE_SCRIPT.new() as CustomerQueue
    customer_queue.name = "CustomerQueue"
    add_child(customer_queue)
    customer_queue.setup(sales_counter, farm_size * 0.5)
    money_stack = MONEY_STACK_SCRIPT.new() as MoneyStack
    money_stack.name = "MoneyStack"
    add_child(money_stack)
    var counter_half := sales_counter.get_half_extents()
    var base_half := Vector2(MoneyStack.get_base_size().x, MoneyStack.get_base_size().z) * 0.5
    # Ao lado do balcão e fora da plantação (que ficou mais larga).
    var field_half_width := get_planting_area_half_width()
    var base_left := maxf(counter_half.x, field_half_width) + 0.35
    money_stack.position = sales_counter.position + Vector3(base_left + base_half.x, 0.0, -0.4 - base_half.y)
    sales_controller = SALES_CONTROLLER_SCRIPT.new() as SalesController
    sales_controller.name = "SalesController"
    add_child(sales_controller)
    sales_controller.setup(customer_queue, sales_counter, money_stack)
    wallet = WALLET_SCRIPT.new() as Wallet
    wallet.name = "Wallet"
    add_child(wallet)

## Meia largura (X) de todas as tiras juntas, centradas em x = 0.
func get_planting_area_half_width() -> float:
    return ((PLANTING_PLOT_COUNT - 1) * planting_plot_spacing.x + PLANTING_PLOT_WIDTH) * 0.5

## Pegada XZ do canteiro de tomate inteiro (todas as tiras).
func get_planting_area_rect() -> Rect2:
    var half_width := get_planting_area_half_width()
    return Rect2(-half_width, PLANTING_NEAR_EDGE_Z, half_width * 2.0, planting_plot_size.y)

## Fator linear das tiras da parcela extra em relação às tiras do canteiro,
## escolhido para que a pegada total seja EXTRA_PLOT_AREA_RATIO da área.
func get_extra_plot_strip_scale() -> float:
    var overlap_ratio := PLANTING_PLOT_OVERLAP / PLANTING_PLOT_WIDTH
    var unit_width := float(EXTRA_PLOT_STRIPS) - overlap_ratio * float(EXTRA_PLOT_STRIPS - 1)
    var unit_area := unit_width * PLANTING_PLOT_WIDTH * planting_plot_size.y
    return sqrt(EXTRA_PLOT_AREA_RATIO * get_planting_area_rect().get_area() / unit_area)

## Pegada XZ da parcela extra, à direita do canteiro e alinhada ao seu centro.
func get_extra_plot_rect() -> Rect2:
    var main := get_planting_area_rect()
    var s := get_extra_plot_strip_scale()
    var overlap_ratio := PLANTING_PLOT_OVERLAP / PLANTING_PLOT_WIDTH
    var size := Vector2(
        PLANTING_PLOT_WIDTH * s * (float(EXTRA_PLOT_STRIPS) - overlap_ratio * float(EXTRA_PLOT_STRIPS - 1)),
        planting_plot_size.y * s
    )
    var center := Vector2(main.end.x + EXTRA_PLOT_GAP + size.x * 0.5, main.get_center().y)
    return Rect2(center - size * 0.5, size)

## Retângulos XZ (com folga) onde a decoração não entra: cerca, galpão e parcela extra.
func get_obstacle_rects() -> Array[Rect2]:
    var rects: Array[Rect2] = []
    for entry in [[FENCE_POSITION, FENCE_SIZE, Vector2(1.3, 1.3)], [BUILDING_POSITION, BUILDING_SIZE, Vector2(1.4, 1.3)]]:
        var center: Vector3 = entry[0]
        var size: Vector3 = entry[1]
        var margin: Vector2 = entry[2]
        var half := Vector2(size.x, size.z) * 0.5 + margin
        rects.append(Rect2(Vector2(center.x, center.z) - half, half * 2.0))
    rects.append(get_extra_plot_rect().grow(1.0))
    rects.append(get_helper_pad_rect().grow(0.8))
    # ENV-FENCE-001: faixa das cercas do balcão (a arte sobe na tela; arbustos
    # logo atrás dela ficavam cobertos pela cerca).
    if sales_counter:
        rects.append(Rect2(-farm_size * 0.5, sales_counter.position.z - 1.8, farm_size, 2.4))
    for entry in crop_areas:
        rects.append((entry["field"] as Rect2).grow(1.0))
        rects.append((entry["stock"] as Rect2).grow(1.0))
        rects.append((entry["pad_rect"] as Rect2).grow(0.8))
    for sign in crop_signs:
        rects.append(Rect2(Vector2(sign.position.x, sign.position.z) - Vector2(1.3, 0.6), Vector2(2.6, 1.2)))
    return rects

## Parcela extra: 2 tiras com a mesma arte de solo (escala uniforme), 10% da
## área do canteiro. Sem Area3D: não entra no PlantingGrid.
func _build_extra_planting_area() -> void:
    extra_planting_area = Node3D.new()
    extra_planting_area.name = "ExtraPlantingArea"
    extra_planting_area.set_meta("area_ratio", EXTRA_PLOT_AREA_RATIO)
    extra_planting_area.set_meta("plantable", false)
    var rect := get_extra_plot_rect()
    extra_planting_area.position = Vector3(rect.get_center().x, 0.025, rect.get_center().y)
    add_child(extra_planting_area)
    var main_soil := ($PlantingArea.get_child(0) as Node3D).get_node("PlowedSoil") as MeshInstance3D
    var main_quad := main_soil.mesh as QuadMesh
    var s := get_extra_plot_strip_scale()
    for index in EXTRA_PLOT_STRIPS:
        var visual := MeshInstance3D.new()
        visual.name = "PlowedSoil_%02d" % (index + 1)
        var quad := QuadMesh.new()
        quad.size = main_quad.size * s
        visual.mesh = quad
        visual.material_override = main_soil.material_override
        visual.rotation_degrees.x = -90.0
        var centered_column := index - (EXTRA_PLOT_STRIPS - 1) * 0.5
        visual.position = Vector3(centered_column * planting_plot_spacing.x * s, 0.0, 0.0)
        extra_planting_area.add_child(visual)

## Escala linear (relativa às tiras do tomate) de uma parcela de
## EXTRA_PLOT_STRIPS tiras com a área pedida (m²).
func get_patch_strip_scale(target_area: float) -> float:
    var overlap_ratio := PLANTING_PLOT_OVERLAP / PLANTING_PLOT_WIDTH
    var unit_width := float(EXTRA_PLOT_STRIPS) - overlap_ratio * float(EXTRA_PLOT_STRIPS - 1)
    return sqrt(target_area / (unit_width * PLANTING_PLOT_WIDTH * planting_plot_size.y))

## Tamanho XZ de uma parcela de `strips` tiras na escala `s`.
func get_patch_size(strips: int, s: float) -> Vector2:
    var overlap_ratio := PLANTING_PLOT_OVERLAP / PLANTING_PLOT_WIDTH
    return Vector2(PLANTING_PLOT_WIDTH * s * (float(strips) - overlap_ratio * float(strips - 1)), planting_plot_size.y * s)

## Geometria de uma área de cultura extra (CROP-AREAS-001), em XZ do mundo:
## canteiro a partir de `origin`; estoque (10% da área) a leste, alinhado ao
## centro; plataforma do ajudante logo depois do estoque, no sentido do balcão.
func get_crop_area_layout(origin: Vector2) -> Dictionary:
    var field := Rect2(origin, get_patch_size(CROP_AREA_STRIPS, CROP_AREA_SCALE))
    var stock_size := get_patch_size(EXTRA_PLOT_STRIPS, get_patch_strip_scale(EXTRA_PLOT_AREA_RATIO * field.get_area()))
    var stock_center := Vector2(field.end.x + EXTRA_PLOT_GAP + stock_size.x * 0.5, field.get_center().y)
    var stock := Rect2(stock_center - stock_size * 0.5, stock_size)
    var pad_size := HelperPad.get_size()
    var pad_center := Vector2(stock_center.x, stock.end.y + HELPER_PAD_GAP + pad_size.y * 0.5)
    return {"field": field, "stock": stock, "pad_rect": Rect2(pad_center - pad_size * 0.5, pad_size)}

## Monta o solo das áreas extras: canteiro (Area3D por tira, com meta "crop"
## para a placa) e a parcela de estoque. Sem PlantingGrid por enquanto.
func _build_crop_areas() -> void:
    var main_soil := ($PlantingArea.get_child(0) as Node3D).get_node("PlowedSoil") as MeshInstance3D
    var main_quad := main_soil.mesh as QuadMesh
    for spec in CROP_AREAS:
        var crop: StringName = spec["crop"]
        var layout := get_crop_area_layout(spec["origin"])
        var field: Rect2 = layout["field"]
        var area := Node3D.new()
        area.name = "CropArea_%s" % String(crop).capitalize()
        area.set_meta("crop", String(crop))
        area.set_meta("is_crop_group", true)
        area.set_meta("plot_count", CROP_AREA_STRIPS)
        var plantable := PLANTABLE_CROPS.has(crop)
        area.set_meta("plantable", plantable)
        add_child(area)
        var s := CROP_AREA_SCALE
        for index in CROP_AREA_STRIPS:
            var plot := Area3D.new()
            # Nomes únicos por cultura: os ids das covas ("<tira>_rNN_cNN") não
            # podem colidir com os do tomate no mapa compartilhado `crops`.
            plot.name = ("%sPlot_%02d" % [String(crop).capitalize(), index + 1]) if plantable else ("PlantingPlot_%02d" % (index + 1))
            plot.monitoring = false
            plot.monitorable = false
            plot.set_meta("plot_index", index)
            plot.set_meta("crop", String(crop))
            var centered_column := index - (CROP_AREA_STRIPS - 1) * 0.5
            plot.position = Vector3(field.get_center().x + centered_column * planting_plot_spacing.x * s, 0.025, field.get_center().y)
            var visual := MeshInstance3D.new()
            visual.name = "PlowedSoil"
            var quad := QuadMesh.new()
            quad.size = main_quad.size * s
            visual.mesh = quad
            visual.material_override = main_soil.material_override
            visual.rotation_degrees.x = -90.0
            plot.add_child(visual)
            var collision := CollisionShape3D.new()
            collision.name = "CollisionShape3D"
            var shape := BoxShape3D.new()
            shape.size = Vector3(PLANTING_PLOT_WIDTH * s, 0.1, planting_plot_size.y * s)
            collision.shape = shape
            collision.position.y = -0.025
            collision.disabled = not plantable
            plot.add_child(collision)
            area.add_child(plot)
        var stock: Rect2 = layout["stock"]
        var stock_area := Node3D.new()
        stock_area.name = "StockArea_%s" % String(crop).capitalize()
        stock_area.set_meta("role", "%s_pile" % crop)
        stock_area.position = Vector3(stock.get_center().x, 0.025, stock.get_center().y)
        add_child(stock_area)
        var t := get_patch_strip_scale(EXTRA_PLOT_AREA_RATIO * field.get_area())
        for index in EXTRA_PLOT_STRIPS:
            var patch := MeshInstance3D.new()
            patch.name = "PlowedSoil_%02d" % (index + 1)
            var patch_quad := QuadMesh.new()
            patch_quad.size = main_quad.size * t
            patch.mesh = patch_quad
            patch.material_override = main_soil.material_override
            patch.rotation_degrees.x = -90.0
            var column := index - (EXTRA_PLOT_STRIPS - 1) * 0.5
            patch.position = Vector3(column * planting_plot_spacing.x * t, 0.0, 0.0)
            stock_area.add_child(patch)
        var entry := layout.duplicate()
        entry["crop"] = crop
        entry["area"] = area
        entry["stock_area"] = stock_area
        crop_areas.append(entry)

## Pilha de estoque e plataforma do ajudante de cada área extra (depois da
## Wallet). A plataforma fica bloqueada enquanto a cultura não tem plantio.
func _build_crop_area_services() -> void:
    for entry in crop_areas:
        var crop: StringName = entry["crop"]
        var label := String(crop).capitalize()
        var pile := TOMATO_PILE_SCRIPT.new() as TomatoPile
        pile.name = "CropPile_%s" % label
        pile.item_id = crop
        pile.centered = true
        add_child(pile)
        pile.setup(entry["stock"], harvest_inventory.units_per_crate)
        var hiring := HELPER_HIRING_SCRIPT.new() as HelperHiring
        hiring.name = "HelperHiring_%s" % label
        add_child(hiring)
        var pad := HELPER_PAD_SCRIPT.new() as HelperPad
        pad.name = "HelperPad_%s" % label
        add_child(pad)
        pad.setup((entry["pad_rect"] as Rect2).get_center(), hiring, wallet)
        pad.locked = not bool((entry["area"] as Node3D).get_meta("plantable", false))
        entry["pile"] = pile
        entry["hiring"] = hiring
        entry["pad"] = pad
        if crop_grids.has(crop):
            var helper := FARM_HELPER_SCRIPT.create() as FarmHelper
            helper.name = "FarmHelper_%s" % label
            add_child(helper)
            helper.setup(crop_grids[crop], crops, pile, hiring, self, harvest_inventory.units_per_crate)
            crop_helpers[crop] = helper
            entry["helper"] = helper

## FV-WOOD-001: fileiras de eucalipto nas bordas de trás (norte) e oeste do
## canteiro de tomate e das áreas de milho e abóbora, e uma fileira ao longo da
## margem leste do rio (lado da fazenda). Nada na frente dos canteiros (lado do
## balcão), no corredor central de acesso, nas pontes, perto do balcão ou fora
## do terreno.
func get_eucalyptus_points() -> Array[Vector3]:
    var candidates: Array[Vector2] = []
    var fields: Array[Rect2] = [get_planting_area_rect()]
    for entry in crop_areas:
        fields.append(entry["field"] as Rect2)
    for field in fields:
        _append_row(candidates, Vector2(field.position.x, field.position.y - EUCALYPTUS_EDGE_GAP), Vector2(field.end.x, field.position.y - EUCALYPTUS_EDGE_GAP))
        _append_row(candidates, Vector2(field.position.x - EUCALYPTUS_EDGE_GAP, field.position.y), Vector2(field.position.x - EUCALYPTUS_EDGE_GAP, field.end.y - 1.0))
    if river_system:
        var z := -farm_size * 0.5 + 2.0
        while z < farm_size * 0.5 - 2.0:
            var bank := _river_east_bank(z)
            if bank > -INF:
                # Se a margem estiver ocupada (cabeceira de ponte), tenta 1 m mais para dentro.
                candidates.append(Vector2(bank + EUCALYPTUS_RIVER_GAP, z))
                candidates.append(Vector2(bank + EUCALYPTUS_RIVER_GAP + 1.0, z))
            z += EUCALYPTUS_SPACING
    var row := 0
    var fz := EUCALYPTUS_FOREST.position.y
    while fz <= EUCALYPTUS_FOREST.end.y:
        var fx := EUCALYPTUS_FOREST.position.x + (EUCALYPTUS_FOREST_STEP.x * 0.5 if row % 2 == 1 else 0.0)
        while fx <= EUCALYPTUS_FOREST.end.x:
            # Desvio fixo (determinístico) para a floresta não parecer um tabuleiro.
            var jitter := Vector2(sin(fx * 12.9898 + fz * 78.233), sin(fx * 39.346 + fz * 11.135)) * 0.3
            candidates.append(Vector2(fx, fz) + jitter)
            fx += EUCALYPTUS_FOREST_STEP.x
        fz += EUCALYPTUS_FOREST_STEP.y
        row += 1
    var points: Array[Vector3] = []
    for candidate in candidates:
        if not _eucalyptus_allowed(candidate):
            continue
        var crowded := false
        for other in points:
            if Vector2(other.x, other.z).distance_to(candidate) < 1.8:
                crowded = true
                break
        if not crowded:
            points.append(Vector3(candidate.x, 0.0, candidate.y))
    return points

func _append_row(out: Array[Vector2], from: Vector2, to: Vector2) -> void:
    var length := from.distance_to(to)
    var count := maxi(1, int(floor(length / EUCALYPTUS_SPACING)) + 1)
    # Zigue-zague leve (perpendicular à fileira): as copas não se empilham numa
    # torre só e a fileira parece plantada à mão.
    var side := (to - from).normalized().orthogonal() if length > 0.01 else Vector2.ZERO
    for index in count:
        var t := 0.0 if count == 1 else float(index) / float(count - 1)
        out.append(from.lerp(to, t) + side * (0.45 if index % 2 == 0 else -0.45))

## X da borda leste do rio (tiles com a margem ilustrada, sem as pontes) na
## linha z, só na metade oeste do mapa; -INF se a linha não cruza o rio.
func _river_east_bank(z: float) -> float:
    var bank := -INF
    for segment in river_system.segments:
        var rect := river_system.get_segment_rect(segment)
        if z >= rect.position.y and z <= rect.end.y and rect.end.x < 0.0:
            bank = maxf(bank, rect.end.x)
    return bank

func _eucalyptus_allowed(point: Vector2) -> bool:
    var edge := farm_size * 0.5 - 1.5
    if absf(point.x) > edge or absf(point.y) > edge:
        return false
    var main := get_planting_area_rect()
    # Corredor central de acesso ao canteiro (o mesmo do CozyEnvironment).
    if absf(point.x) < 3.4 and point.y > main.position.y - 10.3 and point.y < main.end.y:
        return false
    if Vector2(farmer.position.x, farmer.position.z).distance_to(point) < 2.0:
        return false
    if sales_counter:
        var counter := Vector2(sales_counter.position.x, sales_counter.position.z)
        if point.distance_to(counter) < 7.0 or (point.y > counter.y - 6.0 and absf(point.x) < 12.0):
            return false
    # Árvore provisória (primitiva) a sudoeste do canteiro.
    if point.distance_to(Vector2(-10.0, 10.0)) < 2.6:
        return false
    for rect in get_obstacle_rects():
        if rect.has_point(point):
            return false
    if river_system and river_system.blocks_decoration(Vector3(point.x, 0.0, point.y), 0.6):
        return false
    return true

func _build_eucalyptus() -> void:
    eucalyptus_grove = EUCALYPTUS_GROVE_SCRIPT.new() as EucalyptusGrove
    eucalyptus_grove.name = "EucalyptusGrove"
    add_child(eucalyptus_grove)
    eucalyptus_grove.setup(get_eucalyptus_points(), harvest_inventory, backpack.intake_marker)

## Avisos da madeira: corte bloqueado (mochila com tomates ou cheia) e, com
## toras na mochila, lembrete de vender no balcão ao entrar num canteiro.
func _on_chop_blocked(reason: StringName) -> void:
    if hud:
        hud.show_banner(tr("WOOD_BACKPACK_BUSY") if reason == &"other_item" else tr("WOOD_BACKPACK_FULL"), 2.0)

func _update_wood_hint() -> void:
    var carrying_wood := harvest_inventory.get_amount(WoodConfig.ITEM) > 0
    var in_field := get_planting_area_rect().has_point(Vector2(farmer.global_position.x, farmer.global_position.z))
    if carrying_wood and in_field:
        if not _wood_banner_shown and hud:
            _wood_banner_shown = true
            hud.show_banner(tr("WOOD_SELL_FIRST"), 2.0)
    else:
        _wood_banner_shown = false

## CROP-CORN-001: dentro de um canteiro com a mochila ocupada por OUTRO
## produto (ex.: tomates no milharal), avisa uma vez que é preciso vender no
## balcão antes de colher. Madeira no canteiro de tomate já tem aviso próprio.
func _update_crop_busy_hint() -> void:
    var here := Vector2(farmer.global_position.x, farmer.global_position.z)
    var field_crop: StringName = &""
    if get_planting_area_rect().has_point(here):
        field_crop = &"tomato"
    else:
        for entry in crop_areas:
            if crop_grids.has(entry["crop"]) and (entry["field"] as Rect2).has_point(here):
                field_crop = entry["crop"]
    var busy := field_crop != &"" and not harvest_inventory.can_accept(field_crop)
    if busy and harvest_inventory.get_amount(WoodConfig.ITEM) > 0 and field_crop == &"tomato":
        busy = false
    if busy:
        if not _crop_busy_banner_shown and hud:
            _crop_busy_banner_shown = true
            hud.show_banner(tr("HARVEST_SELL_FIRST") % tr(String(CropSign.CROPS[field_crop]["key"])).to_lower(), 2.0)
    else:
        _crop_busy_banner_shown = false

## Área extra de uma cultura (vazio se não houver).
func get_crop_area(crop: StringName) -> Dictionary:
    for entry in crop_areas:
        if entry["crop"] == crop:
            return entry
    return {}

## Uma placa por terreno de plantio (agrupamento com meta is_crop_group). A
## cultura vem do meta "crop" do terreno: trocar para "corn" ou "pumpkin"
## escolhe a placa de milho ou de abóbora sem outra mudança.
func _build_crop_signs() -> void:
    for area in get_children():
        if not (area is Node3D and area.get_meta("is_crop_group", false)):
            continue
        var crop := StringName(area.get_meta("crop", "tomato"))
        if not CropSign.has_crop(crop):
            continue
        var rect := get_crop_group_rect(area)
        if rect.has_area() == false:
            continue
        var sign := CROP_SIGN_SCRIPT.new() as CropSign
        sign.name = "CropSign_%s" % area.name
        sign.crop_id = crop
        sign.position = Vector3(rect.position.x + CROP_SIGN_OFFSET.x, 0.0, rect.end.y + CROP_SIGN_OFFSET.y)
        sign.set_meta("crop_area", area.name)
        add_child(sign)
        crop_signs.append(sign)

## Pegada XZ de um terreno de plantio: união das tiras (Area3D) do agrupamento.
func get_crop_group_rect(area: Node3D) -> Rect2:
    var rect := Rect2()
    var first := true
    for plot in area.get_children():
        if not plot is Area3D or not plot.has_node("CollisionShape3D"):
            continue
        var box := (plot.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
        var center := (plot as Node3D).global_position if is_inside_tree() else (plot as Node3D).position
        var plot_rect := Rect2(Vector2(center.x - box.size.x * 0.5, center.z - box.size.z * 0.5), Vector2(box.size.x, box.size.z))
        rect = plot_rect if first else rect.merge(plot_rect)
        first = false
    return rect

## Placa do terreno de uma cultura (null se não houver).
func get_crop_sign(crop: StringName) -> CropSign:
    for sign in crop_signs:
        if sign.get_crop_id() == crop:
            return sign
    return null

func _build_planting_grid() -> void:
    planting_grid = PLANTING_GRID_SCRIPT.new()
    planting_grid.name = "PlantingGrid"
    add_child(planting_grid)
    var modules: Array[Area3D] = []
    for child in $PlantingArea.get_children():
        if child is Area3D:
            modules.append(child)
    planting_grid.configure(modules)
    planting_grid.cell_planted.connect(_on_grid_cell_planted)
    for entry in crop_areas:
        var area := entry["area"] as Node3D
        if not bool(area.get_meta("plantable", false)):
            continue
        var crop: StringName = entry["crop"]
        var grid := PLANTING_GRID_SCRIPT.new() as PlantingGrid
        grid.name = "PlantingGrid_%s" % String(crop).capitalize()
        grid.crop_id = String(crop)
        grid.rows_per_module = CROP_AREA_ROWS
        add_child(grid)
        var crop_modules: Array[Area3D] = []
        for child in area.get_children():
            if child is Area3D:
                crop_modules.append(child)
        grid.configure(crop_modules)
        grid.cell_planted.connect(_on_grid_cell_planted)
        crop_grids[crop] = grid
        entry["grid"] = grid

## Grade (tomate ou cultura extra) dona da cova `cell_id`.
func get_grid_for_cell(cell_id: String) -> PlantingGrid:
    if planting_grid and planting_grid.cells.has(cell_id):
        return planting_grid
    for grid in crop_grids.values():
        if (grid as PlantingGrid).cells.has(cell_id):
            return grid
    return planting_grid

## Grade de uma cultura (tomate = planting_grid; null se não for plantável).
func get_crop_grid(crop: StringName) -> PlantingGrid:
    return planting_grid if crop == &"tomato" else crop_grids.get(crop) as PlantingGrid

func _on_grid_cell_planted(cell_id: String) -> void:
    var cell: Dictionary = get_grid_for_cell(cell_id).cells[cell_id]
    var seed_throw := SEED_THROW_SCENE.instantiate() as SeedThrow
    add_child(seed_throw)
    # O broto nasce quando o punhado toca o sulco, não no momento do arremesso.
    seed_throw.landed.connect(_spawn_crop.bind(cell_id), CONNECT_ONE_SHOT)
    var origin: Vector3 = _seed_origin_override if _seed_origin_override is Vector3 else farmer.global_position + SEED_HAND_OFFSET
    seed_throw.launch(origin, cell["position"] + Vector3(0.0, 0.2, 0.0))

## Semeia uma cova a partir de outro ponto (mãos do ajudante). Mesmo fluxo da
## semeadura do fazendeiro: PlantingGrid.plant_cell -> punhado -> broto.
func plant_cell_from(cell_id: String, origin: Vector3) -> bool:
    _seed_origin_override = origin
    var ok := get_grid_for_cell(cell_id).plant_cell(cell_id)
    _seed_origin_override = null
    return ok

## Contratação, pilha na parcela extra e o ajudante. A parcela extra continua
## sem células de plantio: é o ponto de pilha das caixas do ajudante.
func _build_helper() -> void:
    helper_hiring = HELPER_HIRING_SCRIPT.new() as HelperHiring
    helper_hiring.name = "HelperHiring"
    add_child(helper_hiring)
    tomato_pile = TOMATO_PILE_SCRIPT.new() as TomatoPile
    tomato_pile.name = "TomatoPile"
    add_child(tomato_pile)
    tomato_pile.setup(get_extra_plot_rect(), harvest_inventory.units_per_crate)
    extra_planting_area.set_meta("role", "tomato_pile")
    farm_helper = FARM_HELPER_SCRIPT.create() as FarmHelper
    add_child(farm_helper)
    farm_helper.setup(planting_grid, crops, tomato_pile, helper_hiring, self, harvest_inventory.units_per_crate)
    helper_pad = HELPER_PAD_SCRIPT.new() as HelperPad
    helper_pad.name = "HelperPad"
    add_child(helper_pad)
    helper_pad.setup(get_helper_pad_rect().get_center(), helper_hiring, wallet)
    _build_crop_area_services()

## Pegada XZ da plataforma do ajudante: centrada na parcela extra (X), logo
## depois dela no sentido do balcão (+Z), por onde o fazendeiro passa.
func get_helper_pad_rect() -> Rect2:
    var plot := get_extra_plot_rect()
    var size := HelperPad.get_size()
    var center := Vector2(plot.get_center().x, plot.end.y + HELPER_PAD_GAP + size.y * 0.5)
    return Rect2(center - size * 0.5, size)

## Dispara um punhado invisível sob o terreno para compilar os shaders das
## partículas na carga da cena; sem isso o primeiro arremesso real engasga.
func _prewarm_seed_throw() -> void:
    var warmup := SEED_THROW_SCENE.instantiate() as SeedThrow
    warmup.name = "SeedThrowWarmup"
    warmup.ground_grain_count = 1
    add_child(warmup)
    warmup.launch(Vector3(0.0, -40.0, 0.0), Vector3(0.5, -40.0, 0.5))

func _spawn_crop(_landing: Vector3, cell_id: String) -> CropPlant:
    var cell: Dictionary = get_grid_for_cell(cell_id).cells[cell_id]
    var crop := CROP_PLANT_SCRIPT.new() as CropPlant
    crop.name = "Crop_" + cell_id
    crop.crop_id = StringName(cell.get("crop_id", "tomato"))
    if crop.crop_id != &"tomato":
        crop.stage_heights = CropCatalog.stage_heights(crop.crop_id)
    crop.position = cell["position"]
    crop.cell_width = cell["cell_width"]
    add_child(crop)
    crops[cell_id] = crop
    crop.ready_for_harvest.connect(_on_crop_ready)
    crop.initialize(cell_id, cell["planted_at"])
    return crop

## Planta já num estágio (ferramentas de teste/captura). Estágio final => RIPE.
func spawn_crop_at_stage(cell_id: String, stage: int) -> CropPlant:
    var grid := get_grid_for_cell(cell_id)
    if grid.cells[cell_id]["state"] == "EMPTY":
        grid.cells[cell_id]["state"] = "SEEDED"
    var crop := _spawn_crop(Vector3.ZERO, cell_id)
    # planted_at = 0 congela o crescimento no estágio pedido.
    crop.planted_at = 0.0
    crop._update_stage(stage)
    return crop

func _on_crop_ready(cell_id: String) -> void:
    var grid := get_grid_for_cell(cell_id)
    var controller: HarvestController = harvest_controller if grid == planting_grid else crop_harvesters.get(StringName(grid.crop_id), harvest_controller)
    grid.mark_ripe(cell_id, controller.yield_per_crop)

func _build_harvest() -> void:
    harvest_inventory = HARVEST_INVENTORY_SCRIPT.new() as HarvestInventory
    harvest_inventory.name = "HarvestInventory"
    add_child(harvest_inventory)
    backpack = BACKPACK_CRATES_SCRIPT.new() as BackpackCrates
    backpack.name = "BackpackCrates"
    backpack.max_crates = harvest_inventory.max_crates
    backpack.units_per_crate = harvest_inventory.units_per_crate
    backpack.position = BACKPACK_OFFSET
    farmer.add_child(backpack)
    harvest_inventory.amount_changed.connect(backpack.set_amount)
    harvest_controller = HARVEST_CONTROLLER_SCRIPT.new() as HarvestController
    harvest_controller.name = "HarvestController"
    add_child(harvest_controller)
    harvest_controller.setup(planting_grid, harvest_inventory, farmer, backpack.intake_marker, crops, self)
    planting_grid.cell_state_changed.connect(_on_cell_state_changed)
    # CROP-CORN-001: uma colheita por cultura extra, na mesma mochila (que
    # aceita um produto por vez: HarvestInventory.can_accept).
    for crop in crop_grids:
        var controller := HARVEST_CONTROLLER_SCRIPT.new() as HarvestController
        controller.name = "HarvestController_%s" % String(crop).capitalize()
        controller.item_id = crop
        controller.yield_per_crop = CropCatalog.yield_per_crop(crop)
        controller.min_visual_tomatoes = 2
        controller.max_visual_tomatoes = 3
        add_child(controller)
        controller.setup(crop_grids[crop], harvest_inventory, farmer, backpack.intake_marker, crops, self)
        (crop_grids[crop] as PlantingGrid).cell_state_changed.connect(_on_cell_state_changed)
        crop_harvesters[crop] = controller

func _on_cell_state_changed(cell_id: String, state: String) -> void:
    if state == PlantingGrid.STATE_HARVESTED and crops.has(cell_id):
        (crops[cell_id] as CropPlant).queue_free()
        crops.erase(cell_id)
        get_grid_for_cell(cell_id).reset_if_fully_harvested()

func _build_environment() -> void:
    var environment := WorldEnvironment.new()
    var resource := Environment.new()
    resource.background_mode = Environment.BG_COLOR
    resource.background_color = Color(0.52, 0.73, 0.92)
    resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    resource.ambient_light_color = Color(0.72, 0.82, 1.0)
    resource.ambient_light_energy = 0.7
    environment.environment = resource
    add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
    sun.light_energy = 1.2
    sun.shadow_enabled = true
    add_child(sun)

func _build_ground() -> void:
    var body := StaticBody3D.new()
    body.name = "Ground"
    var mesh := MeshInstance3D.new()
    mesh.name = "GrassSurface"
    var plane := BoxMesh.new()
    plane.size = Vector3(farm_size, 0.4, farm_size)
    mesh.mesh = plane
    mesh.material_override = _material(Color(0.20, 0.52, 0.18))
    mesh.position.y = -0.2
    body.add_child(mesh)
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(farm_size, 0.4, farm_size)
    collision.shape = shape
    collision.position.y = -0.2
    body.add_child(collision)
    add_child(body)
    _add_boundary(Vector3(farm_size, 2.0, 0.4), Vector3(0, 1, -farm_size * 0.5))
    _add_boundary(Vector3(farm_size, 2.0, 0.4), Vector3(0, 1, farm_size * 0.5))
    _add_boundary(Vector3(0.4, 2.0, farm_size), Vector3(-farm_size * 0.5, 1, 0))
    _add_boundary(Vector3(0.4, 2.0, farm_size), Vector3(farm_size * 0.5, 1, 0))

func _build_planting_area() -> void:
    var planting_area := Node3D.new()
    planting_area.name = "PlantingArea"
    planting_area.set_meta("crop", "tomato")
    planting_area.set_meta("is_crop_group", true)
    planting_area.set_meta("plot_count", PLANTING_PLOT_COUNT)
    add_child(planting_area)

    var soil_material := StandardMaterial3D.new()
    soil_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    soil_material.albedo_texture = SOIL_TEXTURE
    soil_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    soil_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    soil_material.render_priority = -1

    for index in PLANTING_PLOT_COUNT:
        var plot := Area3D.new()
        plot.name = "PlantingPlot_%02d" % (index + 1)
        var column := index % PLANTING_COLUMNS
        var row := int(index / PLANTING_COLUMNS)
        var centered_column := column - (PLANTING_COLUMNS - 1) * 0.5
        var centered_row := row - (PLANTING_ROWS - 1) * 0.5
        plot.position = Vector3(
            centered_column * planting_plot_spacing.x,
            0.025,
            PLANTING_NEAR_EDGE_Z + planting_plot_size.y * 0.5 + centered_row * planting_plot_spacing.y
        )
        plot.set_meta("plot_index", index)
        plot.set_meta("crop", "tomato")
        plot.add_to_group("planting_plot")

        var visual := MeshInstance3D.new()
        visual.name = "PlowedSoil"
        var quad := QuadMesh.new()
        # O quad mostra o PNG inteiro com a proporção da arte compensada pela
        # câmera (1/sin 45°) e o comprimento da tira. Antes a largura era
        # alargada pela margem transparente sem alongar o comprimento, e o solo
        # aparecia 4,9% achatado na tela (auditoria FV-SALES-003).
        var soil_aspect := float(SOIL_TEXTURE.get_height()) / float(SOIL_TEXTURE.get_width())
        quad.size = Vector2(
            planting_plot_size.y / (soil_aspect * PLANTING_LENGTH_STRETCH),
            planting_plot_size.y
        )
        visual.mesh = quad
        visual.material_override = soil_material
        visual.rotation_degrees.x = -90.0
        plot.add_child(visual)

        var collision := CollisionShape3D.new()
        collision.name = "CollisionShape3D"
        var shape := BoxShape3D.new()
        shape.size = Vector3(planting_plot_size.x, 0.1, planting_plot_size.y)
        collision.shape = shape
        collision.position.y = -0.025
        plot.add_child(collision)
        planting_area.add_child(plot)

func _build_obstacles() -> void:
    _add_fence("Fence", FENCE_POSITION, FENCE_SIZE)
    _add_box_obstacle("Building", BUILDING_SIZE, BUILDING_POSITION, Color(0.72, 0.30, 0.18))
    # A árvore fica fora do agrupamento contínuo de cultivo de tomate.
    _add_tree(Vector3(-10, 0, 10))

func _add_tree(position: Vector3) -> void:
    var body := StaticBody3D.new()
    body.name = "Tree"
    var trunk := MeshInstance3D.new()
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = 0.28
    cylinder.bottom_radius = 0.38
    cylinder.height = 1.8
    trunk.mesh = cylinder
    trunk.material_override = _material(Color(0.32, 0.16, 0.07))
    trunk.position = position + Vector3(0, 0.9, 0)
    body.add_child(trunk)
    var crown := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 1.2
    sphere.height = 2.4
    crown.mesh = sphere
    crown.material_override = _material(Color(0.08, 0.38, 0.12))
    crown.position = position + Vector3(0, 2.3, 0)
    body.add_child(crown)
    var collision := CollisionShape3D.new()
    var shape := CapsuleShape3D.new()
    shape.radius = 0.65
    shape.height = 2.0
    collision.shape = shape
    collision.position = position + Vector3(0, 1.0, 0)
    body.add_child(collision)
    add_child(body)

## ENV-FENCE-001: cerca de madeira com a arte do projeto (FenceRun) no lugar da
## caixa marrom provisória. A colisão continua a mesma caixa (FENCE_SIZE).
func _add_fence(label: String, position: Vector3, size: Vector3) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = label
    body.position = position
    var fence := FenceRun.new()
    fence.name = "FenceRun"
    fence.length = size.x
    # A arte nasce no chão (o corpo fica a meia altura da colisão).
    fence.position.y = -position.y
    body.add_child(fence)
    var collision := CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    var shape := BoxShape3D.new()
    shape.size = size
    collision.shape = shape
    body.add_child(collision)
    add_child(body)
    return body

func _add_box_obstacle(label: String, size: Vector3, position: Vector3, color: Color) -> void:
    var body := StaticBody3D.new()
    body.name = label
    var mesh := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = size
    mesh.mesh = box
    mesh.material_override = _material(color)
    body.add_child(mesh)
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    collision.shape = shape
    body.add_child(collision)
    body.position = position
    add_child(body)

func _add_boundary(size: Vector3, position: Vector3) -> void:
    _add_box_obstacle("TerrainBoundary", size, position, Color(0.12, 0.30, 0.12))

func _build_camera() -> void:
    camera = Camera3D.new()
    camera.name = "IsometricCamera"
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = camera_orthographic_size
    camera.position = farmer.global_position + Vector3(0, camera_height, camera_distance)
    camera.current = true
    add_child(camera)

func _update_camera_focus(delta: float) -> void:
    var offset := farmer.global_position - camera_focus
    var desired_focus := camera_focus
    if absf(offset.x) > camera_dead_zone.x:
        desired_focus.x = farmer.global_position.x - signf(offset.x) * camera_dead_zone.x
    if absf(offset.z) > camera_dead_zone.y:
        desired_focus.z = farmer.global_position.z - signf(offset.z) * camera_dead_zone.y
    desired_focus.x = clampf(desired_focus.x, -camera_limits.x, camera_limits.x)
    desired_focus.z = clampf(desired_focus.z, -camera_limits.y, camera_limits.y)
    camera_focus = camera_focus.lerp(desired_focus, minf(1.0, delta * camera_follow_speed))
    var desired_camera := camera_focus + Vector3(0.0, camera_height, camera_distance)
    camera.global_position = camera.global_position.lerp(desired_camera, minf(1.0, delta * camera_follow_speed))
    camera.look_at(camera_focus, Vector3.UP)

func _build_hud() -> void:
    player_level = PLAYER_LEVEL_SCRIPT.new() as PlayerLevel
    player_level.name = "PlayerLevel"
    add_child(player_level)
    # 1 XP por tomate vendido no balcão.
    sales_controller.sale_completed.connect(_on_sale_completed_xp)
    mission_tracker = MISSION_TRACKER_SCRIPT.new() as MissionTracker
    mission_tracker.name = "MissionTracker"
    add_child(mission_tracker)
    hud = FARM_HUD_SCENE.instantiate() as FarmHUD
    hud.name = "HUD"
    add_child(hud)
    var joystick := JOYSTICK_SCENE.instantiate()
    joystick.name = "VirtualJoystick"
    joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    joystick.position = Vector2(28, -250)
    hud.add_child(joystick)
    farmer.joystick_path = NodePath("../HUD/VirtualJoystick")
    hud.setup(wallet, harvest_inventory, sales_controller, player_level, mission_tracker)
    mission_tracker.setup(harvest_inventory, sales_controller, wallet, player_level)
    helper_pad.purchased.connect(_on_helper_purchased)
    eucalyptus_grove.chop_blocked.connect(_on_chop_blocked)
    # A estação inicial já está nas árvores; o aviso só aparece se ela virar com o jogo aberto.
    eucalyptus_grove.season_changed.connect(func(season: StringName) -> void: hud.show_banner(tr("SEASON_CHANGED") % tr(SeasonClock.label_key(season)), 2.4))
    helper_pad.out_of_money.connect(func(missing: int) -> void: hud.show_banner(tr("HELPER_NO_MONEY") % missing, 2.0))
    for entry in crop_areas:
        var crop_key := String(CropSign.CROPS[entry["crop"]]["key"]) if CropSign.has_crop(entry["crop"]) else String(entry["crop"])
        var pad := entry["pad"] as HelperPad
        pad.locked_touched.connect(func() -> void: hud.show_banner(tr("AREA_SOON_BANNER") % tr(crop_key), 1.8))
        if crop_grids.has(entry["crop"]):
            pad.purchased.connect(func(grade: int) -> void: hud.show_banner(tr("HELPER_HIRED_%s" % String(entry["crop"]).to_upper()) if grade == 1 else tr("HELPER_UPGRADED") % grade, 2.2))
            pad.out_of_money.connect(func(missing: int) -> void: hud.show_banner(tr("HELPER_NO_MONEY") % missing, 2.0))

func _on_helper_purchased(grade: int) -> void:
    if grade == 1:
        hud.show_banner(tr("HELPER_HIRED"), 2.4)
    else:
        hud.show_banner(tr("HELPER_UPGRADED") % grade, 2.0)

func _on_sale_completed_xp(_customer: Customer, _crates: int, units: int, _money: int) -> void:
    player_level.add_xp(units * ProgressionConfig.XP_PER_TOMATO_SOLD)

func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    return material
