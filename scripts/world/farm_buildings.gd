extends Node3D
class_name FarmBuildings
## FARM-005 (10/11): construções da biblioteca de assets espalhadas pela
## fazenda (celeiro, paiol, galinheiro, oficina e galpão de máquinas). Por
## enquanto são cenário: sprite em pé (billboard, como a casa do fazendeiro)
## com a base na frente da construção e uma caixa de colisão no corpo.

## [nome, textura, base XZ (frente, centro), largura na tela (m)]
var specs: Array = []
var buildings: Array[StaticBody3D] = []

## Pegada XZ desenhada (sprite em pé cobre o gramado atrás da base).
static func get_art_rect(base: Vector2, width: float) -> Rect2:
    var depth := width * 0.78
    return Rect2(base.x - width * 0.5, base.y - depth, width, depth + 0.6)

## Corpo sólido (colisão): miolo da arte, um pouco atrás da base.
static func get_body_rect(base: Vector2, width: float) -> Rect2:
    var body := Vector2(width * 0.62, width * 0.36)
    return Rect2(base.x - body.x * 0.5, base.y - 0.8 - body.y, body.x, body.y)

func setup(list: Array) -> void:
    specs = list
    for spec in specs:
        var texture := load(String(spec[1])) as Texture2D
        var base: Vector2 = spec[2]
        var width := float(spec[3])
        var body := StaticBody3D.new()
        body.name = String(spec[0])
        body.position = Vector3(base.x, 0.0, base.y)
        add_child(body)
        var sprite := Sprite3D.new()
        sprite.name = "Art"
        sprite.texture = texture
        sprite.pixel_size = width / float(texture.get_width())
        sprite.centered = false
        sprite.offset = Vector2(-texture.get_width() * 0.5, -texture.get_height() * 0.01)
        sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        sprite.shaded = false
        sprite.double_sided = true
        sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
        sprite.alpha_scissor_threshold = 0.3
        sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
        sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        body.add_child(sprite)
        var solid := get_body_rect(base, width)
        var collision := CollisionShape3D.new()
        collision.name = "CollisionShape3D"
        var shape := BoxShape3D.new()
        shape.size = Vector3(solid.size.x, 2.4, solid.size.y)
        collision.shape = shape
        collision.position = Vector3(solid.get_center().x - base.x, 1.2, solid.get_center().y - base.y)
        body.add_child(collision)
        buildings.append(body)

func get_art_rects(margin: float = 0.0) -> Array[Rect2]:
    var rects: Array[Rect2] = []
    for spec in specs:
        rects.append(get_art_rect(spec[2], float(spec[3])).grow(margin))
    return rects
