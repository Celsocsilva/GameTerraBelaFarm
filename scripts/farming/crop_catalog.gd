extends RefCounted
class_name CropCatalog
## CROP-CORN-001: dados de cada cultura plantável (arte dos estágios, alturas,
## rendimento, preço e arte do fruto que voa até a mochila). O tomate continua
## com os valores originais de CropPlant/HarvestController/SalesController; o
## milho reaproveita todo o fluxo do tomate com os dados abaixo.

const TOMATO := &"tomato"
const CORN := &"corn"
const PUMPKIN := &"pumpkin"

const CROPS := {
    &"tomato": {
        "stages": [
            "res://assets/crops/tomato/stages/tomato_stage_01_sprout.png",
            "res://assets/crops/tomato/stages/tomato_stage_02_flowering.png",
            "res://assets/crops/tomato/stages/tomato_stage_03_green_2_fruits.png",
            "res://assets/crops/tomato/stages/tomato_stage_04_ripe_3_fruits.png",
        ],
        "heights": [0.8, 1.05, 1.2, 1.35],
        "fruit": "res://assets/harvest/tomato_ripe.png",
        "fruit_height": 0.6,
        "yield": 6,
        "price_per_crate": 3,
    },
    # Broto -> jovem com cinco folhas -> com uma espiga -> maduro com duas espigas.
    &"corn": {
        "stages": [
            "res://assets/crops/corn/stages/corn_stage_01_sprout.png",
            "res://assets/crops/corn/stages/corn_stage_02_young_five_leaves.png",
            "res://assets/crops/corn/stages/corn_stage_03_one_ear.png",
            "res://assets/crops/corn/stages/corn_stage_04_mature_two_ears.png",
        ],
        # O milho é mais alto que o tomate e cresce bem mais entre os estágios.
        # CORN-SIZE-002 (09/11): pedido do Celso — milho 10% maior e, no mesmo
        # dia, mais 20% (x1,1 x 1,2 = x1,32 na altura e na largura máxima):
        # era [0.75, 1.25, 1.55, 1.8] e 1.15 da cova.
        "heights": [0.75 * 1.32, 1.25 * 1.32, 1.55 * 1.32, 1.8 * 1.32],
        "max_width_fraction": 1.15 * 1.32,
        "fruit": "res://assets/harvest/corn_cob.png",
        "fruit_height": 0.7,
        # Provisório: 4 espigas por pé (duas espigas visíveis no desenho).
        "yield": 4,
        # Provisório: caixa de milho vale 4 (tomate 3, fardo de madeira 6).
        "price_per_crate": 4,
    },
    # Broto -> rama florida -> frutos verdes/amarelos -> abóboras maduras.
    &"pumpkin": {
        "stages": [
            "res://assets/crops/pumpkin/stages/pumpkin_stage_01_sprout.png",
            "res://assets/crops/pumpkin/stages/pumpkin_stage_02_flowering.png",
            "res://assets/crops/pumpkin/stages/pumpkin_stage_03_green_fruit.png",
            "res://assets/crops/pumpkin/stages/pumpkin_stage_04_ripe.png",
        ],
        # Cultura rasteira larga, deliberadamente maior e mais destacada.
        "heights": [1.1, 1.55, 1.9, 2.35],
        "max_width_fraction": 1.55,
        "fruit": "res://assets/crops/pumpkin/stages/pumpkin_stage_04_ripe.png",
        "fruit_height": 0.9,
        "yield": 2,
        "price_per_crate": 6,
    },
}

static func has_crop(crop: StringName) -> bool:
    return CROPS.has(crop)

static func _data(crop: StringName) -> Dictionary:
    return CROPS.get(crop, CROPS[TOMATO])

static func stage_assets(crop: StringName) -> Array:
    return _data(crop)["stages"]

static func stage_heights(crop: StringName) -> PackedFloat32Array:
    return PackedFloat32Array(_data(crop)["heights"])

static func yield_per_crop(crop: StringName) -> int:
    return int(_data(crop)["yield"])

static func price_per_crate(crop: StringName) -> int:
    return int(_data(crop)["price_per_crate"])

static func fruit_texture(crop: StringName) -> Texture2D:
    return load(String(_data(crop)["fruit"])) as Texture2D

static func fruit_height(crop: StringName) -> float:
    return float(_data(crop)["fruit_height"])

static func max_width_fraction(crop: StringName) -> float:
    return float(_data(crop).get("max_width_fraction", 1.15))
