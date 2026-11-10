extends Node
class_name HelperHiring
## Estado da contratação do ajudante: graduação atual e compra da próxima
## graduação com o saldo da Wallet (origem &"helper"). Sem apresentação: o
## HelperPad (plataforma no chão) e o FarmHelper só leem daqui.

signal grade_changed(grade: int)
## Tentativa sem saldo (o HUD mostra um aviso).
signal purchase_failed(cost: int)
## A graduação inicial exige também um produto (fardos/caixas) entregue na
## plataforma, descarregado da mochila do fazendeiro.
signal requirement_failed(item: StringName, missing_crates: int)
## Unidades do produto já entregues para a contratação (HIRE-FIX-001).
signal material_changed(units: int, needed_units: int)

var grade := 0
## Dinheiros já entregues na plataforma para a próxima graduação. Sair da
## plataforma só pausa: o que já foi pago continua valendo (nada é perdido).
var paid := 0
var requirement_item: StringName = &""
var requirement_crates := 0
var requirement_units_per_crate := 8
## Legado: antes o material era contado no estoque do balcão. Desde o
## HIRE-FIX-001 ele é descarregado da mochila na própria plataforma
## (deliver_material); a fonte fica só para compatibilidade de chamadas.
var requirement_source: Object
## Unidades do material já descarregadas na plataforma (persistem ao sair).
var material_units := 0

signal paid_changed(paid: int, cost: int)

func is_hired() -> bool:
    return grade > 0

func is_max() -> bool:
    return grade >= HelperConfig.MAX_GRADE

func get_next_cost() -> int:
    return HelperConfig.next_cost(grade)

func configure_initial_requirement(item: StringName, crates: int, units_per_crate: int, source: Object) -> void:
    requirement_item = item
    requirement_crates = maxi(crates, 0)
    requirement_units_per_crate = maxi(units_per_crate, 1)
    requirement_source = source

func get_requirement_crates() -> int:
    return requirement_crates if grade == 0 else 0

func get_available_requirement_crates() -> int:
    if grade > 0 or requirement_crates <= 0:
        return requirement_crates
    return mini(requirement_crates, material_units / requirement_units_per_crate)

func get_missing_requirement_crates() -> int:
    return maxi(0, get_requirement_crates() - get_available_requirement_crates())

func has_initial_requirement() -> bool:
    return get_missing_requirement_crates() == 0

func get_requirement_units() -> int:
    return get_requirement_crates() * requirement_units_per_crate

func get_missing_requirement_units() -> int:
    return maxi(0, get_requirement_units() - material_units) if grade == 0 else 0

## Descarrega até `max_units` do material da mochila (`inventory`) para a
## contratação. Retorna quantas unidades saíram da mochila (nunca mais que o
## que falta, nunca mais do que o fazendeiro carrega).
func deliver_material(inventory: HarvestInventory, max_units: int) -> int:
    if inventory == null or grade > 0 or requirement_crates <= 0:
        return 0
    var units := mini(mini(maxi(max_units, 0), get_missing_requirement_units()), inventory.get_amount(requirement_item))
    if units <= 0:
        return 0
    var removed := inventory.remove(requirement_item, units)
    if removed <= 0:
        return 0
    material_units += removed
    material_changed.emit(material_units, get_requirement_units())
    # Dinheiro já completo (parado em preço - 1) + material agora completo:
    # o último dinheiro sai no próximo passo da plataforma.
    return removed

func _consume_initial_requirement() -> bool:
    if grade > 0 or requirement_crates <= 0:
        return true
    var missing := get_missing_requirement_crates()
    if missing > 0:
        requirement_failed.emit(requirement_item, missing)
        return false
    material_units = 0
    return true

func can_buy(wallet: Wallet) -> bool:
    return wallet != null and not is_max() and wallet.can_afford(get_next_cost()) and has_initial_requirement()

## Contrata (graduação 0 -> 1) ou melhora (n -> n + 1). Retorna false sem gastar
## se não houver saldo ou se já estiver no máximo.
func try_buy(wallet: Wallet) -> bool:
    if wallet == null or is_max():
        return false
    var cost := get_remaining_cost()
    if grade == 0 and not has_initial_requirement():
        requirement_failed.emit(requirement_item, get_missing_requirement_crates())
        return false
    if not wallet.spend(cost, &"helper"):
        purchase_failed.emit(cost)
        return false
    if not _consume_initial_requirement():
        wallet.add(cost, &"helper_refund")
        return false
    paid = 0
    grade += 1
    grade_changed.emit(grade)
    return true

func get_remaining_cost() -> int:
    return maxi(0, get_next_cost() - paid) if not is_max() else 0

## Paga `amount` dinheiros (um a um pela plataforma) da Wallet para a próxima
## graduação. Ao completar o preço, contrata/melhora e zera `paid`.
## Retorna quanto foi efetivamente pago.
func pay(wallet: Wallet, amount: int = 1) -> int:
    if wallet == null or is_max():
        return 0
    var remaining := get_remaining_cost()
    var units := mini(mini(maxi(amount, 0), remaining), wallet.get_balance())
    # Sem o material, a plataforma pode guardar no máximo 99/100 dinheiros.
    # Assim a graduação nunca é liberada e o último dinheiro não é consumido.
    if grade == 0 and units >= remaining and not has_initial_requirement():
        units = maxi(0, remaining - 1)
        requirement_failed.emit(requirement_item, get_missing_requirement_crates())
    if units <= 0 or not wallet.spend(units, &"helper"):
        return 0
    paid += units
    if paid >= get_next_cost():
        if not _consume_initial_requirement():
            paid = get_next_cost() - 1
            paid_changed.emit(paid, get_next_cost())
            return units
        paid = 0
        grade += 1
        paid_changed.emit(paid, get_next_cost())
        grade_changed.emit(grade)
    else:
        paid_changed.emit(paid, get_next_cost())
    return units

## Restauração de save / testes.
func set_grade(value: int) -> void:
    var target := HelperConfig.clamp_grade(value)
    if target == grade:
        return
    grade = target
    grade_changed.emit(grade)

func to_dict() -> Dictionary:
    return {"version": 2, "grade": grade, "paid": paid, "material_units": material_units}

func from_dict(data: Dictionary) -> void:
    set_grade(int(data.get("grade", 0)))
    paid = clampi(int(data.get("paid", 0)), 0, maxi(get_next_cost() - 1, 0))
    paid_changed.emit(paid, get_next_cost())
    material_units = clampi(int(data.get("material_units", 0)), 0, get_requirement_units())
    material_changed.emit(material_units, get_requirement_units())
