extends Node3D
class_name FeedTrough
## DAIRY-002/003: cocho de milho das vacas. O fazendeiro traz caixas de milho
## na mochila e encosta na cerca do curral (qualquer lado, por fora, até
## FENCE_REACH); as caixas voam, uma a cada UNLOAD_INTERVAL, por cima da cerca
## até o cocho dentro do curral (pilha de caixas de milho, uma camada 3 x 3).
## As vacas comem dali, uma espiga por refeição (MilkStation.try_feed).

signal corn_delivered(units: int, stored_total: int)

const UNLOAD_INTERVAL := 0.16
const START_DELAY := 0.3

## Distância máxima (m) da cerca, por fora, para entregar o milho.
const FENCE_REACH := 1.3

## Cerca do curral (retângulo XZ do mundo).
var pen_rect := Rect2()
## Onde fica a pilha de milho (dentro do curral), XZ do mundo.
var stock_rect := Rect2()
var pile: TomatoPile
var _on_pad_time := 0.0
var _accumulator := 0.0

func setup(p_pen_rect: Rect2, p_stock_rect: Rect2, units_per_crate: int) -> void:
    pen_rect = p_pen_rect
    stock_rect = p_stock_rect
    position = Vector3(stock_rect.get_center().x, 0.0, stock_rect.get_center().y)
    pile = TomatoPile.new()
    pile.name = "FeederPile"
    pile.item_id = DairyConfig.FEED_ITEM
    pile.centered = true
    pile.grid_layout = true
    pile.max_crates = DairyConfig.FEEDER_MAX_CRATES
    pile.top_level = true
    add_child(pile)
    pile.setup(stock_rect, units_per_crate)

func get_stored_total() -> int:
    return pile.get_stored_total() if pile else 0

func get_capacity() -> int:
    return pile.get_capacity() if pile else 0

func take_corn(units: int) -> int:
    return pile.take_units(units) if pile else 0

## De onde sai a espiga que voa até a vaca (topo da pilha do cocho).
func get_corn_origin() -> Vector3:
    if pile == null or not pile.is_inside_tree():
        return Vector3(stock_rect.get_center().x, 0.6, stock_rect.get_center().y)
    var top := maxi(pile.get_crate_count() - 1, 0)
    return pile.to_global(pile.get_slot_local(top)) + Vector3(0.0, 0.6, 0.0)

## Fazendeiro encostado na cerca, por fora (a colisão não deixa entrar).
func contains_point(world_pos: Vector3) -> bool:
    var p := Vector2(world_pos.x, world_pos.z)
    return pen_rect.grow(FENCE_REACH).has_point(p) and not pen_rect.grow(-0.2).has_point(p)

## Um ponto logo do lado de fora da cerca (testes e capturas).
func get_fence_point() -> Vector3:
    return Vector3(stock_rect.get_center().x, 1.0, pen_rect.end.y + 0.7)

## Chame por frame. Encostado na cerca, descarrega o milho da mochila para o cocho.
## Retorna quantas espigas entraram neste quadro.
func process_farmer_position(world_pos: Vector3, delta: float, inventory: HarvestInventory, from_pos: Variant = null) -> int:
    if inventory == null or pile == null or not contains_point(world_pos):
        _on_pad_time = 0.0
        _accumulator = 0.0
        return 0
    _on_pad_time += delta
    if _on_pad_time < START_DELAY:
        return 0
    _accumulator += delta
    var moved := 0
    while _accumulator >= UNLOAD_INTERVAL:
        _accumulator -= UNLOAD_INTERVAL
        var units := mini(mini(inventory.units_per_crate, inventory.get_amount(DairyConfig.FEED_ITEM)), pile.get_free_capacity())
        if units <= 0:
            _accumulator = 0.0
            break
        var removed := inventory.remove(DairyConfig.FEED_ITEM, units)
        pile.add_units(removed, from_pos if from_pos is Vector3 else (world_pos + Vector3(0.0, 2.3, 0.0)))
        moved += removed
        corn_delivered.emit(removed, pile.get_stored_total())
    return moved
