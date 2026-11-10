extends RefCounted
class_name HelperConfig
## Ajudante da fazenda (FV-HELPER-001): custos e atributos por graduação, num
## lugar só. Graduação 0 = não contratado; 1 = contratado; 2..MAX_GRADE =
## melhorias. Contratar custa 100 dinheiros (definido pelo Celso em 8/11/2026);
## as melhorias dobram o preço (provisório, pedir confirmação).

const MAX_GRADE := 5

## Custo para chegar à graduação i + 1 (índice 0 = contratar).
const UPGRADE_COSTS: Array[int] = [100, 200, 400, 800, 1600]
## Recurso adicional da primeira contratação, medido em caixas/fardos completos
## já depositados na banca. Melhorias de graduação usam somente dinheiro.
const INITIAL_REQUIREMENTS := {
    &"tomato": {"item": &"wood", "crates": 20},
    &"corn": {"item": &"tomato", "crates": 20},
    &"pumpkin": {"item": &"corn", "crates": 20},
}
## Velocidade de caminhada (m/s) por graduação (índice 0 = graduação 1).
## O fazendeiro anda a 4,0 m/s.
const WALK_SPEEDS: Array[float] = [2.2, 2.6, 3.0, 3.4, 3.8]
## Caixas que o ajudante carrega por viagem até a parcela de pilha.
const CARRY_CRATES: Array[int] = [1, 1, 2, 2, 3]
## Segundos colhendo cada pé maduro.
const HARVEST_SECONDS: Array[float] = [1.0, 0.85, 0.7, 0.6, 0.5]
## Segundos semeando cada cova vazia.
const PLANT_SECONDS := 0.35
## O ajudante replanta covas vazias (depois que a safra inteira é colhida).
const REPLANTS := true

static func clamp_grade(grade: int) -> int:
    return clampi(grade, 0, MAX_GRADE)

## Custo da próxima graduação, ou -1 se já estiver no máximo.
static func next_cost(grade: int) -> int:
    var g := clamp_grade(grade)
    return UPGRADE_COSTS[g] if g < MAX_GRADE else -1

static func initial_requirement(crop: StringName) -> Dictionary:
    return INITIAL_REQUIREMENTS.get(crop, {}).duplicate()

static func walk_speed(grade: int) -> float:
    return WALK_SPEEDS[clampi(grade, 1, MAX_GRADE) - 1]

static func carry_crates(grade: int) -> int:
    return CARRY_CRATES[clampi(grade, 1, MAX_GRADE) - 1]

static func harvest_seconds(grade: int) -> float:
    return HARVEST_SECONDS[clampi(grade, 1, MAX_GRADE) - 1]
