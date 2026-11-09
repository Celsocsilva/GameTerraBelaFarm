extends Node
class_name SalesController
## Vendas no Balcão de vendas. O primeiro cliente de cada fila, já parado no
## lugar, é atendido quando o balcão tem tomates: após serve_time segundos ele
## compra uma quantidade sorteada de caixas (min..max_crates_per_customer,
## limitada ao estoque), paga price_per_crate por caixa (proporcional para a
## última caixa incompleta), o dinheiro vai para a base 3 x 5 e o cliente sai
## levando as caixas; os de trás andam um lugar (CustomerQueue.release_front).
## Sem estoque o cliente continua esperando e a paciência normal da fila vale.

signal sale_completed(customer: Customer, crates: int, units: int, money: int)
## FV-WOOD-001: mesma venda, com o item vendido (tomato, wood...).
signal item_sold(item: StringName, customer: Customer, crates: int, units: int, money: int)

@export_range(1, 99, 1) var price_per_crate: int = 3
## FV-WOOD-001: preço de um fardo cheio de toras (8) no balcão.
@export_range(1, 999, 1) var wood_price_per_bundle: int = WoodConfig.PRICE_PER_BUNDLE
@export_range(1, 10, 1) var min_crates_per_customer: int = 1
@export_range(1, 10, 1) var max_crates_per_customer: int = 3
## Tempo de atendimento no balcão antes de a compra acontecer.
@export_range(0.0, 10.0, 0.1) var serve_time: float = 1.2

var rng := RandomNumberGenerator.new()
## Registro para testes: {"customer", "crates", "units", "money"}.
var sales_log: Array[Dictionary] = []
var _queue: CustomerQueue
var _counter: SalesCounter
var _money: MoneyStack

func _ready() -> void:
    rng.randomize()

func setup(queue: CustomerQueue, counter: SalesCounter, money: MoneyStack) -> void:
    _queue = queue
    _counter = counter
    _money = money

func set_seed(value: int) -> void:
    rng.seed = value

## Preço de uma venda: price_per_crate por caixa cheia, proporcional (para cima)
## numa caixa incompleta.
func price_for_units(units: int, item: StringName = &"tomato") -> int:
    if units <= 0:
        return 0
    return int(ceil(float(units) * float(price_per_crate_of(item)) / float(_counter.units_per_crate)))

## Preço por caixa (ou fardo) cheio de cada item.
func price_per_crate_of(item: StringName) -> int:
    if item == WoodConfig.ITEM:
        return wood_price_per_bundle
    if item != &"tomato" and CropCatalog.has_crop(item):
        return CropCatalog.price_per_crate(item)
    return price_per_crate

func _process(delta: float) -> void:
    tick(delta)

## Avança os atendimentos; separado de _process para testes determinísticos.
func tick(delta: float) -> void:
    if _queue == null or _counter == null or _money == null:
        return
    for lane in CustomerQueue.LANES:
        var members := _queue.get_lane(lane)
        if members.is_empty():
            continue
        var customer: Customer = members[0]
        if not _is_ready_to_buy(customer):
            continue
        if not _counter.has_any_stock():
            customer.remove_meta("serve_left")
            continue
        var serve_left: float = customer.get_meta("serve_left", serve_time)
        serve_left -= delta
        # Em atendimento o cliente não desiste.
        customer.patience_left = maxf(customer.patience_left, serve_left + 0.5)
        if serve_left > 0.0:
            customer.set_meta("serve_left", serve_left)
            continue
        customer.remove_meta("serve_left")
        _sell_to(customer, lane)

func _is_ready_to_buy(customer: Customer) -> bool:
    return customer.slot == 0 and customer.has_arrived and not customer.is_leaving and not customer.is_walking()

func _sell_to(customer: Customer, lane: int) -> void:
    # Com mais de um item no balcão (tomate e madeira), cada cliente leva um
    # deles, sorteado. Só tomate: nenhum sorteio extra (testes com seed iguais).
    var items := _counter.get_stocked_items()
    if items.is_empty():
        return
    var item: StringName = items[0] if items.size() == 1 else items[rng.randi_range(0, items.size() - 1)]
    var wanted := rng.randi_range(min_crates_per_customer, maxi(min_crates_per_customer, max_crates_per_customer))
    var crates := mini(wanted, _counter.get_item_stock_crates(item))
    var units := _counter.take_item_units(item, crates * _counter.units_per_crate)
    if units <= 0:
        return
    var money := price_for_units(units, item)
    _money.add_money(money)
    customer.carry_crates(crates, item)
    _queue.release_front(lane)
    sales_log.append({"customer": customer, "item": item, "crates": crates, "units": units, "money": money, "carried": customer.get_carried_crates()})
    sale_completed.emit(customer, crates, units, money)
    item_sold.emit(item, customer, crates, units, money)
