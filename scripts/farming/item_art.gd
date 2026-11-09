extends RefCounted
class_name ItemArt
## Arte de cada item carregado em caixas (FV-WOOD-001): a mochila, a pilha do
## balcão e os voos usam a mesma regra. Tomate: caixa cheia / caixa parcial.
## Madeira: fardo amarrado de 8 toras (cheio) e fardos de 4 ou 6 toras para o
## fardo incompleto do topo, conforme a quantidade de toras nele.

const CRATE_FULL := preload("res://assets/harvest/crate_full.png")
const CRATE_EMPTY := preload("res://assets/harvest/crate_empty.png")
## CROP-CORN-001: caixa cheia de espigas (a parcial usa a caixa vazia).
const CRATE_CORN_FULL := preload("res://assets/harvest/crate_corn_full.png")
const LOG_BUNDLE_4 := preload("res://assets/items/logs/log_bundle_4.png")
const LOG_BUNDLE_6 := preload("res://assets/items/logs/log_bundle_6.png")
const LOG_BUNDLE_8 := preload("res://assets/items/logs/log_bundle_8.png")

## Largura relativa à caixa de tomate (o fardo é mais "cheio" que a caixa).
const WIDTH_SCALE := {&"wood": 0.9}

static func full_texture(item: StringName) -> Texture2D:
    if item == &"corn":
        return CRATE_CORN_FULL
    return LOG_BUNDLE_8 if item == &"wood" else CRATE_FULL

## Arte do caixote incompleto com `units` unidades (de `per_crate`).
static func partial_texture(item: StringName, units: int, per_crate: int) -> Texture2D:
    if item != &"wood":
        return CRATE_EMPTY
    var fraction := float(units) / float(maxi(per_crate, 1))
    if fraction <= 0.5:
        return LOG_BUNDLE_4
    if fraction <= 0.75:
        return LOG_BUNDLE_6
    return LOG_BUNDLE_8

static func width_scale(item: StringName) -> float:
    return float(WIDTH_SCALE.get(item, 1.0))

## Mini tomates dentro da caixa parcial só existem para o tomate.
static func has_partial_fill(item: StringName) -> bool:
    return item == &"tomato"
