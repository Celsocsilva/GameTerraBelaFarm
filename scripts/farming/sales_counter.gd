extends Node3D
class_name SalesCounter
## Balcão de vendas: o fazendeiro descarrega toda a mochila de tomates aqui e
## os clientes compram do estoque do balcão (SalesController).
## Adicione como filho direto de FarmWorld e chame place_at_map_foot(farm_size).
## Chame setup(inventory) e process_farmer_position(farmer.global_position, mãos).
##
## O balcão é sólido (StaticBody3D) e, com build_side_barriers, cercas baixas
## ligam as pontas do balcão às laterais do terreno: o fazendeiro fica sempre
## do lado da plantação (-Z) e não passa para o lado dos clientes (+Z).
##
## Visual (FV-PROPS-001): banca de feira com toalha xadrez vermelha no lugar do
## tampo marrom; a pegada, a colisão, as cercas laterais e a pilha de caixas não
## mudam. FV-PROPS-002 trocou a arte por uma versão mais funda; FV-STACK-001
## voltou para a banca plana (assets/sales/stall_market_gingham.png). A arte
## funda continua guardada em assets/sales, sem uso.
##
## As caixas usam a mesma arte das caixas da mochila (crate_full/crate_empty).
## FV-STACK-001: UMA única pilha vertical por cultura (CrateStack), com no
## máximo MAX_VISUAL_CRATES caixas visíveis; acima disso a contagem lógica segue
## correta e um contador "x12" aparece acima da pilha. Ao descarregar, cada
## caixa pula das mãos do fazendeiro até o seu lugar na pilha.

signal deposited(units: int, stored_total: int)
signal stock_taken(units: int, stored_total: int)
## FV-WOOD-001: depósito de um item extra (ex.: toras de madeira).
signal item_deposited(item: StringName, units: int, stored_total: int)

## Altura visual máxima da pilha (caixas); o resto vira o contador "xN".
const MAX_VISUAL_CRATES := 4
## Distância X (centro a centro) entre as pilhas de culturas diferentes.
const STACK_SPACING := 3.6
## Mesma arte das caixas da mochila do fazendeiro (BackpackCrates).
const CRATE_FULL_TEXTURE := preload("res://assets/harvest/crate_full.png")
const CRATE_EMPTY_TEXTURE := preload("res://assets/harvest/crate_empty.png")
## Largura de cada caixa no balcão e espaçamento: X entre colunas, Y entre
## camadas (a de cima apoiada na borda da de baixo), Z entre a fileira de trás
## e a da frente.
## Balcão e caixas ampliados 1,3x (FV-SALES-003): de 8,5 m para 11,05 m de
## largura e caixas de 1,3 m para 1,69 m, mantendo 6 colunas x 2 fileiras.
const COUNTER_SCALE := 1.3
const CRATE_WIDTH := 1.3 * COUNTER_SCALE
const CRATE_SPACING := Vector3(1.38, 0.7, 1.0) * COUNTER_SCALE
## Pulo de cada caixa das mãos do fazendeiro até a pilha.
const JUMP_TIME := 0.42
const JUMP_STAGGER := 0.09
const JUMP_HEIGHT := 1.6 * COUNTER_SCALE
## Tampo do balcão: 8,5 m de largura e fundo para 2 caixas, uma na frente da outra.
const COUNTER_SIZE := Vector3(8.5 * COUNTER_SCALE, 0.16, 2.25 * COUNTER_SCALE)
const BARRIER_HEIGHT := 0.7
## FV-WOOD-001 / CROP-CORN-001: posição X (local) da pilha de cada item extra
## vendido no balcão. O milho ocupa a vaga da esquerda reservada a ele em
## CrateStack; a madeira passou para a vaga da direita (da abóbora, que ainda
## não é vendida).
## Quatro vagas horizontais: milho, tomate, abóbora e madeira.
const ITEM_SLOT_X := {&"corn": -4.0, &"tomato": -1.35, &"pumpkin": 1.35, &"wood": 4.0}
## Arte da banca de feira plana (toalha xadrez vermelha) — FV-STACK-001.
const STALL_TEXTURE := preload("res://assets/sales/stall_market_gingham.png")
## Largura da arte na cena: a mesma do balcão (a colisão não muda).
const STALL_WIDTH := 8.5 * COUNTER_SCALE
## Meio da área da toalha vista de cima no PNG (fração da altura, do topo).
const STALL_CLOTH_CENTER := 0.27
## Inclinação da câmera do jogo (FarmWorld: camera_height == camera_distance).
const VIEW_PITCH_DEGREES := 45.0

@export_range(0, 48, 1) var initial_displayed_crates: int = 0
## Recuado da cerca para caber a fila dupla de 7 clientes do lado +Z.
@export_range(1.0, 16.0, 0.1) var foot_inset: float = 10.5
## Distância máxima entre o fazendeiro e a borda do balcão para descarregar.
@export_range(0.5, 5.0, 0.1) var deposit_reach: float = 1.3
@export_range(1, 64, 1) var units_per_crate: int = 8
@export var item_id: StringName = &"tomato"
## Cercas baixas das pontas do balcão até as laterais do terreno.
@export var build_side_barriers: bool = true
## FV-WOOD-001: outros itens que o fazendeiro descarrega aqui, cada um na sua
## pilha (TomatoPile reaproveitada, com a arte de ItemArt).
@export var extra_items: Array[StringName] = [&"corn", &"pumpkin", &"wood"]

## Registro para testes: um item por caixa que pulou {"index", "from", "to"}.
var jump_log: Array[Dictionary] = []
var _crate_visuals: Array[Node3D] = []
var _displayed_crates := 0
var _stored_total := 0
var _inventory: HarvestInventory
var _farm_size := 0.0
var _body: StaticBody3D
var _camera: Camera3D
## Caixas ainda no ar (vaga visual -> quantas a caminho): só aparecem ao pousar.
var _in_flight: Dictionary = {}
var _count_label: Label3D
var _flyers: Array[Node3D] = []
## item -> TomatoPile com o estoque desse item no balcão.
var _extra_stacks: Dictionary = {}

func _ready() -> void:
    _body = StaticBody3D.new()
    _body.name = "CounterBody"
    add_child(_body)
    _build_stall_visual()
    var collision := CollisionShape3D.new()
    collision.name = "CounterCollision"
    var shape := BoxShape3D.new()
    shape.size = Vector3(COUNTER_SIZE.x, 1.6, COUNTER_SIZE.z + 0.27)
    collision.shape = shape
    collision.position = Vector3(0.0, 0.8, 0.07)
    _body.add_child(collision)
    for index in MAX_VISUAL_CRATES:
        _crate_visuals.append(_build_crate(index))
    _count_label = CrateStack.make_count_label()
    _count_label.position = _count_label_local()
    add_child(_count_label)
    set_displayed_crates(initial_displayed_crates)
    _build_extra_stacks()

func _build_extra_stacks() -> void:
    for item in extra_items:
        if item == item_id or _extra_stacks.has(item):
            continue
        var stack := TomatoPile.new()
        stack.name = "CounterStack_%s" % String(item).capitalize()
        stack.item_id = item
        stack.centered = true
        stack.units_per_crate = units_per_crate
        stack.crate_width = CRATE_WIDTH
        stack.max_crates = 999
        stack.position = Vector3(_item_slot_x(item), get_crate_base_height(), 0.0)
        add_child(stack)
        _extra_stacks[item] = stack

## Banca de feira com toalha xadrez (FV-PROPS-001): a arte inteira num único
## quadro inclinado que vai do chão na frente do balcão (+Z, lado dos clientes)
## até o alto da borda de trás (-Z, lado do fazendeiro). Com a câmera fixa a
## 45°, o quadro aparece na proporção exata do PNG e cobre a mesma pegada da
## colisão. As caixas ficam acima do quadro (sempre na frente dele na tela) e
## pousam sobre a toalha desenhada.
func _build_stall_visual() -> void:
    var stall := MeshInstance3D.new()
    stall.name = "StallVisual"
    var quad := QuadMesh.new()
    var depth := COUNTER_SIZE.z
    var rise := get_stall_rise()
    quad.size = Vector2(STALL_WIDTH, Vector2(depth, rise).length())
    stall.mesh = quad
    stall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var material := StandardMaterial3D.new()
    material.albedo_texture = STALL_TEXTURE
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
    material.alpha_scissor_threshold = 0.5
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    stall.material_override = material
    # Topo do quadro inclinado para trás (-Z): de (y 0, z +d/2) a (y rise, z -d/2).
    stall.rotation.x = -atan2(depth, rise)
    stall.position = Vector3(0.0, rise * 0.5, 0.0)
    _body.add_child(stall)

## Altura (m) da borda de trás do quadro da banca, para que a arte apareça na
## tela com a mesma proporção do PNG: altura na tela = rise*cos(p) + fundo*sen(p).
static func get_stall_rise() -> float:
    var pitch := deg_to_rad(VIEW_PITCH_DEGREES)
    var screen_height := STALL_WIDTH * float(STALL_TEXTURE.get_height()) / float(STALL_TEXTURE.get_width())
    return (screen_height - COUNTER_SIZE.z * sin(pitch)) / cos(pitch)

## Altura da base das caixas: o meio das 2 fileiras cai no meio da toalha
## desenhada (STALL_CLOTH_CENTER, fração da altura do PNG a partir do topo).
static func get_crate_base_height() -> float:
    var pitch := deg_to_rad(VIEW_PITCH_DEGREES)
    var screen_height := STALL_WIDTH * float(STALL_TEXTURE.get_height()) / float(STALL_TEXTURE.get_width())
    var top_on_screen := get_stall_rise() * cos(pitch) + COUNTER_SIZE.z * 0.5 * sin(pitch)
    return (top_on_screen - STALL_CLOTH_CENTER * screen_height) / cos(pitch)

func _process(_delta: float) -> void:
    _orient_sprites()

## O pé visível do mapa é a borda +Z. O inset mantém a pilha dentro da cerca.
## Requer que o balcão seja filho direto de FarmWorld, sem transform no pai.
func place_at_map_foot(farm_size: float) -> void:
    _farm_size = farm_size
    position = Vector3(0.0, 0.0, farm_size * 0.5 - foot_inset)
    if build_side_barriers and is_inside_tree():
        _build_barriers()

func setup(inventory: HarvestInventory) -> void:
    _inventory = inventory

## Meia largura (X) e meia profundidade (Z) da área sólida do balcão.
func get_half_extents() -> Vector2:
    return Vector2(COUNTER_SIZE.x * 0.5, COUNTER_SIZE.z * 0.5)

## Distância no plano XZ entre um ponto e a borda do balcão (0 se dentro).
func distance_to_counter(world_pos: Vector3) -> float:
    var local := world_pos - global_position
    var half := get_half_extents()
    var dx := maxf(absf(local.x) - half.x, 0.0)
    var dz := maxf(absf(local.z) - half.y, 0.0)
    return Vector2(dx, dz).length()

## Chame por frame. Encostar no balcão descarrega toda a mochila de tomates.
## hands_pos é o ponto de onde as caixas pulam (mãos do fazendeiro); sem ele,
## as caixas aparecem direto na pilha.
func process_farmer_position(world_pos: Vector3, hands_pos: Variant = null) -> void:
    if _inventory == null or not is_instance_valid(_inventory):
        return
    if distance_to_counter(world_pos) <= deposit_reach:
        deposit_from(_inventory, hands_pos)

## Remove todos os tomates carregados e retorna a quantidade efetivamente guardada.
## O balcão não tem limite de estoque: toda a produção cabe nele. Com hands_pos,
## cada caixa nova pula das mãos do fazendeiro até o seu lugar na pilha.
func deposit_from(inventory: HarvestInventory, hands_pos: Variant = null) -> int:
    if inventory == null or not is_instance_valid(inventory):
        return 0
    var extra := _deposit_extras(inventory, hands_pos)
    var carried := inventory.get_amount(item_id)
    if carried <= 0:
        return extra
    var removed := inventory.remove(item_id, carried)
    var before := _displayed_crates
    _stored_total += removed
    _sync_display()
    if hands_pos is Vector3 and is_inside_tree():
        for index in range(before, _displayed_crates):
            _launch_crate(index, hands_pos, float(index - before) * JUMP_STAGGER)
    if removed > 0:
        deposited.emit(removed, _stored_total)
    return removed + extra

## Itens extras carregados (ex.: madeira) vão para a pilha própria, com os
## fardos pulando das mãos como as caixas de tomate.
func _deposit_extras(inventory: HarvestInventory, hands_pos: Variant) -> int:
    var total := 0
    for item in _extra_stacks:
        var carried := inventory.get_amount(item)
        if carried <= 0:
            continue
        var removed := inventory.remove(item, carried)
        var stack := _extra_stacks[item] as TomatoPile
        stack.add_units(removed, hands_pos if hands_pos is Vector3 and is_inside_tree() else null)
        total += removed
        item_deposited.emit(item, removed, stack.get_stored_total())
    return total

## Pilha de um item extra no balcão (null se o item não é vendido aqui).
func get_extra_stack(item: StringName) -> TomatoPile:
    return _extra_stacks.get(item) as TomatoPile

## Estoque (unidades) de qualquer item vendido no balcão.
func get_item_total(item: StringName) -> int:
    if item == item_id:
        return _stored_total
    var stack := get_extra_stack(item)
    return stack.get_stored_total() if stack else 0

func get_item_stock_crates(item: StringName) -> int:
    return int(ceil(float(get_item_total(item)) / float(units_per_crate)))

## Retira estoque de qualquer item para uma venda. Nunca negativo.
func take_item_units(item: StringName, units: int) -> int:
    if item == item_id:
        return take_units(units)
    var stack := get_extra_stack(item)
    return stack.take_units(units) if stack else 0

func set_item_total(item: StringName, total: int) -> void:
    if item == item_id:
        set_stored_total(total)
    elif get_extra_stack(item):
        get_extra_stack(item).set_stored_total(total)

## Itens com estoque agora, o principal (tomate) primeiro.
func get_stocked_items() -> Array[StringName]:
    var items: Array[StringName] = []
    if _stored_total > 0:
        items.append(item_id)
    for item in _extra_stacks:
        if (_extra_stacks[item] as TomatoPile).get_stored_total() > 0:
            items.append(item)
    return items

func has_any_stock() -> bool:
    return not get_stocked_items().is_empty()

## Retira estoque para uma venda. Nunca deixa estoque negativo.
func take_units(units: int) -> int:
    var taken := clampi(units, 0, _stored_total)
    if taken <= 0:
        return 0
    _stored_total -= taken
    _sync_display()
    stock_taken.emit(taken, _stored_total)
    return taken

func get_stored_total() -> int:
    return _stored_total

## Caixas à venda (a última pode estar incompleta).
func get_stock_crates() -> int:
    return int(ceil(float(_stored_total) / float(units_per_crate)))

## Restauração de save; não altera o inventário do fazendeiro.
func set_stored_total(total: int) -> void:
    _stored_total = maxi(total, 0)
    _sync_display()

func _sync_display() -> void:
    set_displayed_crates(get_stock_crates())

## Contagem lógica de caixas na pilha (sem limite); a pilha mostra no máximo
## MAX_VISUAL_CRATES e o contador cobre o resto.
func set_displayed_crates(count: int) -> void:
    _displayed_crates = maxi(count, 0)
    _refresh_visible()

## Caixas do estoque na pilha (contagem lógica, inclui as que ainda estão pulando).
func get_displayed_crates() -> int:
    return _displayed_crates

## Caixas efetivamente visíveis na pilha (as que já pousaram).
func get_visible_crate_count() -> int:
    var count := 0
    for crate in _crate_visuals:
        if crate.visible:
            count += 1
    return count

func get_flying_crate_count() -> int:
    return _flyers.size()

## Texto do contador acima da pilha ("" enquanto todas as caixas aparecem).
func get_count_text() -> String:
    return _count_label.text if _count_label and _count_label.visible else ""

func get_count_label() -> Label3D:
    return _count_label

## Posição (mundo) da base da caixa de um índice da pilha (índices além do
## limite visual pousam no topo).
func get_crate_slot_position(index: int) -> Vector3:
    return to_global(_slot_local(index))

func get_crate_texture(index: int) -> Texture2D:
    return (_crate_visuals[index].get_node("CrateSprite") as Sprite3D).texture

func _refresh_visible() -> void:
    var partial := _stored_total % units_per_crate != 0 and _displayed_crates == get_stock_crates()
    var shown := mini(_displayed_crates, MAX_VISUAL_CRATES)
    for index in _crate_visuals.size():
        var crate := _crate_visuals[index]
        crate.visible = index < shown and not _in_flight.has(index)
        var sprite := crate.get_node("CrateSprite") as Sprite3D
        # A caixa do topo, se incompleta, usa a arte de caixa parcial, como na mochila.
        var texture: Texture2D = CRATE_EMPTY_TEXTURE if partial and index == shown - 1 else CRATE_FULL_TEXTURE
        if sprite.texture != texture:
            _apply_texture(sprite, texture)
    if _count_label:
        var text := CrateStack.count_text(_displayed_crates, MAX_VISUAL_CRATES)
        _count_label.text = text
        _count_label.visible = text != ""
        _count_label.position = _count_label_local()

## Uma caixa sai das mãos, sobe em arco e pousa no seu lugar com um "pulo".
func _launch_crate(index: int, from: Vector3, delay: float) -> void:
    var slot := CrateStack.visual_index(index, MAX_VISUAL_CRATES)
    _in_flight[slot] = int(_in_flight.get(slot, 0)) + 1
    _refresh_visible()
    var target := get_crate_slot_position(index)
    var flyer := Node3D.new()
    flyer.name = "JumpingCrate_%02d" % index
    flyer.top_level = true
    add_child(flyer)
    flyer.global_position = from
    # FV-POLISH-001: a caixa da mochila já tem o tamanho da do balcão.
    flyer.set_meta("grow", 1.0)
    var sprite := _make_crate_sprite(CRATE_FULL_TEXTURE)
    sprite.name = "CrateSprite"
    flyer.add_child(sprite)
    _flyers.append(flyer)
    jump_log.append({"index": index, "from": from, "to": target})
    _orient_sprites()
    # Cada caixa só aparece quando sai das mãos (as outras esperam a vez).
    flyer.visible = false
    var tween := create_tween()
    tween.tween_interval(delay)
    tween.tween_callback(flyer.show)
    tween.tween_method(_move_flyer.bind(flyer, from, target), 0.0, 1.0, JUMP_TIME)
    tween.tween_callback(_land_crate.bind(slot, flyer))

func _move_flyer(t: float, flyer: Node3D, from: Vector3, to: Vector3) -> void:
    if not is_instance_valid(flyer):
        return
    var arc := 4.0 * t * (1.0 - t) * JUMP_HEIGHT
    flyer.global_position = from.lerp(to, t) + Vector3(0.0, arc, 0.0)
    _orient_sprites()

func _land_crate(index: int, flyer: Node3D) -> void:
    _flyers.erase(flyer)
    if is_instance_valid(flyer):
        flyer.queue_free()
    var left := int(_in_flight.get(index, 1)) - 1
    if left > 0:
        _in_flight[index] = left
    else:
        _in_flight.erase(index)
    _refresh_visible()
    if index < _crate_visuals.size() and _crate_visuals[index].visible:
        var crate := _crate_visuals[index]
        var tween := create_tween()
        tween.tween_method(_squash.bind(crate), 1.0, 0.0, 0.2)

## Achatamento rápido ao pousar.
func _squash(amount: float, crate: Node3D) -> void:
    if is_instance_valid(crate):
        crate.set_meta("squash", amount)
        _orient_sprites()

## Termina todos os pulos na hora (testes e capturas).
func finish_jumps() -> void:
    for stack in _extra_stacks.values():
        (stack as TomatoPile).finish_jumps()
    for flyer in _flyers:
        if is_instance_valid(flyer):
            flyer.queue_free()
    _flyers.clear()
    _in_flight.clear()
    _refresh_visible()

## Plano vertical virado para a câmera (billboard só no eixo Y), com a altura
## compensada pela inclinação da câmera, igual às caixas da mochila.
func _sprite_basis() -> Basis:
    if _camera == null or not is_instance_valid(_camera):
        _camera = get_viewport().get_camera_3d() if is_inside_tree() else null
    if _camera == null:
        return Basis.IDENTITY
    var toward := _camera.global_basis.z
    toward.y = 0.0
    if toward.length() < 0.001:
        return Basis.IDENTITY
    toward = toward.normalized()
    var right := Vector3.UP.cross(toward).normalized()
    var stretch := 1.0 / maxf(0.3, _camera.global_basis.y.y)
    return Basis(right, Vector3.UP * stretch, toward)

func _orient_sprites() -> void:
    if not is_inside_tree():
        return
    var basis := _sprite_basis()
    for crate in _crate_visuals:
        var squash: float = crate.get_meta("squash", 0.0)
        var shaped := Basis(basis.x * (1.0 + 0.15 * squash), basis.y * (1.0 - 0.2 * squash), basis.z)
        (crate.get_node("CrateSprite") as Node3D).global_basis = shaped
    for flyer in _flyers:
        if is_instance_valid(flyer):
            var grow: float = flyer.get_meta("grow", 1.0)
            (flyer.get_node("CrateSprite") as Node3D).global_basis = Basis(basis.x * grow, basis.y * grow, basis.z)

## Cercas (sólidas) das pontas do balcão até as laterais do terreno, na
## linha central do balcão. Os clientes não têm física e não são afetados.
func _build_barriers() -> void:
    var half := get_half_extents()
    var span := _farm_size * 0.5 - half.x
    if span <= 0.05:
        return
    for side in [-1.0, 1.0]:
        var barrier := StaticBody3D.new()
        barrier.name = "CounterBarrier_%s" % ("L" if side < 0.0 else "R")
        barrier.position = Vector3(side * (half.x + span * 0.5), 0.0, 0.0)
        add_child(barrier)
        # ENV-FENCE-001: a cerca usa a arte de madeira do projeto (FenceRun),
        # com postes nas pontas e vãos iguais; a colisão abaixo não mudou.
        var fence := FenceRun.new()
        fence.name = "Fence"
        fence.length = span
        barrier.add_child(fence)
        var collision := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = Vector3(span, 1.6, 0.3)
        collision.shape = shape
        collision.position.y = 0.8
        barrier.add_child(collision)

## Pilha única da cultura (item_id): uma caixa em cima da outra, no meio da
## toalha. Índices além do limite visual ficam no topo.
func _slot_local(index: int) -> Vector3:
    var layer := CrateStack.visual_index(index, MAX_VISUAL_CRATES)
    # Camadas de cima um pouco à frente (+Z): cobrem a borda da caixa de baixo
    # sem disputar profundidade no mesmo plano.
    return Vector3(
        _item_slot_x(item_id),
        get_crate_base_height() + layer * CRATE_SPACING.y,
        layer * 0.03
    )

func _item_slot_x(item: StringName) -> float:
    return float(ITEM_SLOT_X.get(item, 0.0))

## Contador logo acima da caixa do topo.
func _count_label_local() -> Vector3:
    var crate_height := CRATE_WIDTH * float(CRATE_FULL_TEXTURE.get_height()) / float(CRATE_FULL_TEXTURE.get_width())
    var stretch := 1.0 / cos(deg_to_rad(VIEW_PITCH_DEGREES))
    return _slot_local(MAX_VISUAL_CRATES - 1) + Vector3(0.0, crate_height * stretch + 0.45, 0.2)

func _build_crate(index: int) -> Node3D:
    var crate := Node3D.new()
    crate.name = "CounterCrate_%02d" % index
    crate.position = _slot_local(index)
    add_child(crate)
    var sprite := _make_crate_sprite(CRATE_FULL_TEXTURE)
    sprite.name = "CrateSprite"
    crate.add_child(sprite)
    return crate

func _make_crate_sprite(texture: Texture2D) -> Sprite3D:
    var sprite := Sprite3D.new()
    _apply_texture(sprite, texture)
    sprite.centered = false
    sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
    sprite.shaded = false
    sprite.double_sided = true
    sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
    sprite.alpha_scissor_threshold = 0.5
    sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    return sprite

func _apply_texture(sprite: Sprite3D, texture: Texture2D) -> void:
    sprite.texture = texture
    sprite.pixel_size = CRATE_WIDTH / float(texture.get_width())
    sprite.offset = Vector2(-texture.get_width() * 0.5, 0.0)

func _add_box(parent: Node3D, label: String, size: Vector3, offset: Vector3, material: Material) -> void:
    var mesh := BoxMesh.new()
    mesh.size = size
    var visual := MeshInstance3D.new()
    visual.name = label
    visual.mesh = mesh
    visual.material_override = material
    visual.position = offset
    parent.add_child(visual)

func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.85
    return material
