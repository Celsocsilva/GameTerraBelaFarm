extends Node
class_name HelperHiring
## Estado da contratação do ajudante: graduação atual e compra da próxima
## graduação com o saldo da Wallet (origem &"helper"). Sem apresentação: o
## HelperPad (plataforma no chão) e o FarmHelper só leem daqui.

signal grade_changed(grade: int)
## Tentativa sem saldo (o HUD mostra um aviso).
signal purchase_failed(cost: int)

var grade := 0
## Dinheiros já entregues na plataforma para a próxima graduação. Sair da
## plataforma só pausa: o que já foi pago continua valendo (nada é perdido).
var paid := 0

signal paid_changed(paid: int, cost: int)

func is_hired() -> bool:
    return grade > 0

func is_max() -> bool:
    return grade >= HelperConfig.MAX_GRADE

func get_next_cost() -> int:
    return HelperConfig.next_cost(grade)

func can_buy(wallet: Wallet) -> bool:
    return wallet != null and not is_max() and wallet.can_afford(get_next_cost())

## Contrata (graduação 0 -> 1) ou melhora (n -> n + 1). Retorna false sem gastar
## se não houver saldo ou se já estiver no máximo.
func try_buy(wallet: Wallet) -> bool:
    if wallet == null or is_max():
        return false
    var cost := get_remaining_cost()
    if not wallet.spend(cost, &"helper"):
        purchase_failed.emit(cost)
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
    var units := mini(mini(maxi(amount, 0), get_remaining_cost()), wallet.get_balance())
    if units <= 0 or not wallet.spend(units, &"helper"):
        return 0
    paid += units
    if paid >= get_next_cost():
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
    return {"version": 1, "grade": grade, "paid": paid}

func from_dict(data: Dictionary) -> void:
    set_grade(int(data.get("grade", 0)))
    paid = clampi(int(data.get("paid", 0)), 0, maxi(get_next_cost() - 1, 0))
    paid_changed.emit(paid, get_next_cost())
