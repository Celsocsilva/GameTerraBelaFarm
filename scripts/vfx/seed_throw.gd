extends Node3D
class_name SeedThrow
## Punhado de sementes lançado da mão do fazendeiro até a célula.
## Duas camadas de partículas: grãos no tamanho original (GPUParticles3D) e uma
## nuvem de grãos menores e variados (FineSeeds), mais aberta, que "pulveriza" o
## punhado no ar. Ao pousar, grãos ficam espalhados no sulco e somem aos poucos.
## Cada instância faz um único lançamento e se libera ao terminar.

## Emitido quando o centro do punhado toca o solo (após flight_time).
signal landed(target: Vector3)

@export_range(0.4, 1.4, 0.05) var flight_time: float = 0.85
@export var gravity: Vector3 = Vector3(0.0, -9.8, 0.0)
## 1.0 solta tudo no mesmo quadro; valores menores escalonam o punhado.
@export_range(0.5, 1.0, 0.01) var release_explosiveness: float = 0.86

@export_group("Grãos principais")
## SEED-002: grãos menores (eram 0,65–1,45) e um punhado mais aberto.
@export_range(4, 24, 1) var seed_amount: int = 8
@export_range(0.2, 1.6, 0.05) var seed_scale_min: float = 0.4
@export_range(0.2, 1.6, 0.05) var seed_scale_max: float = 0.85
@export_range(0.0, 45.0, 1.0) var spread_degrees: float = 18.0
## Variação de força (0.15 = ±15%), espalha a queda ao redor do alvo.
@export_range(0.0, 0.5, 0.01) var velocity_variation: float = 0.15

@export_group("Grãos finos")
@export_range(0, 48, 1) var fine_amount: int = 20
@export_range(0.03, 1.0, 0.01) var fine_scale_min: float = 0.07
@export_range(0.1, 1.0, 0.05) var fine_scale_max: float = 0.35
@export_range(0.0, 60.0, 1.0) var fine_spread_degrees: float = 36.0
@export_range(0.0, 0.5, 0.01) var fine_velocity_variation: float = 0.3

@export_group("Grãos no solo")
@export_range(0, 40, 1) var ground_grain_count: int = 14
@export_range(0.1, 2.0, 0.05) var ground_scatter_radius: float = 1.25
## SEED-002: o rastro de grãos no solo é alongado na direção do arremesso
## (elipse), como a semente lançada a lanço que "escorre" para a frente.
@export_range(1.0, 3.0, 0.05) var ground_scatter_stretch: float = 1.6
@export_range(0.2, 3.0, 0.1) var ground_grain_lifetime: float = 1.1

const SEED_ATLAS := preload("res://assets/seeds/tomato_seed_atlas_2x2.png")
const ATLAS_FRAMES := 2
const SEED_QUAD_SIZE := 0.62

@onready var particles: GPUParticles3D = $GPUParticles3D
@onready var fine_particles: GPUParticles3D = $FineSeeds
var _launched := false

## `delay` (SEED-002) escalona os punhados de um mesmo passo: perto primeiro,
## longe depois, como um único gesto de semear a lanço.
var _throw_direction := Vector2(0.0, 1.0)

func launch(origin: Vector3, target: Vector3, delay: float = 0.0) -> void:
	if _launched:
		push_warning("SeedThrow.launch chamado duas vezes; instancie uma nova cena por punhado.")
		return
	_launched = true
	global_position = origin
	var flat := Vector2(target.x - origin.x, target.z - origin.z)
	if flat.length() > 0.001:
		_throw_direction = flat.normalized()
	if delay > 0.0:
		visible = false
		await get_tree().create_timer(delay).timeout
		if not is_inside_tree():
			return
		visible = true

	var velocity := solve_launch_velocity(origin, target, gravity, flight_time)
	_configure_layer(particles, velocity, seed_amount, seed_scale_min, seed_scale_max, spread_degrees, velocity_variation)
	_configure_layer(fine_particles, velocity, fine_amount, fine_scale_min, fine_scale_max, fine_spread_degrees, fine_velocity_variation)

	await get_tree().create_timer(flight_time).timeout
	landed.emit(target)
	_scatter_on_ground(target)
	# A última semente sai após (1 - explosiveness) do voo; os grãos no solo somem depois.
	var tail := maxf(flight_time * (1.0 - release_explosiveness), ground_grain_lifetime)
	await get_tree().create_timer(tail + 0.1).timeout
	queue_free()

func _configure_layer(layer: GPUParticles3D, velocity: Vector3, amount: int, scale_min: float, scale_max: float, spread: float, variation: float) -> void:
	if amount <= 0:
		layer.emitting = false
		layer.visible = false
		return
	# Material próprio por lançamento para não alterar outros punhados ativos.
	var material := layer.process_material.duplicate() as ParticleProcessMaterial
	layer.process_material = material
	var speed := velocity.length()
	material.direction = velocity.normalized() if speed > 0.001 else Vector3.UP
	material.spread = spread
	material.initial_velocity_min = speed * (1.0 - variation)
	material.initial_velocity_max = speed * (1.0 + variation)
	material.gravity = gravity
	material.scale_min = minf(scale_min, scale_max)
	material.scale_max = maxf(scale_min, scale_max)
	layer.amount = amount
	layer.lifetime = flight_time
	layer.explosiveness = release_explosiveness
	layer.restart()
	layer.emitting = true

## Grãos deitados no sulco, mais densos no centro e em tamanhos variados (muitos
## pequenos, poucos grandes), que somem aos poucos: semente espalhada no terreno.
func _scatter_on_ground(center: Vector3) -> void:
	var cell_size := SEED_ATLAS.get_size() / ATLAS_FRAMES
	var ground_y := center.y - 0.17
	for i in ground_grain_count:
		var grain := Sprite3D.new()
		grain.name = "GroundGrain"
		grain.texture = SEED_ATLAS
		grain.region_enabled = true
		var frame := randi() % (ATLAS_FRAMES * ATLAS_FRAMES)
		grain.region_rect = Rect2(Vector2(frame % ATLAS_FRAMES, frame / ATLAS_FRAMES) * cell_size, cell_size)
		grain.shaded = false
		grain.double_sided = true
		var size_roll := randf()
		grain.pixel_size = SEED_QUAD_SIZE / cell_size.x * lerpf(fine_scale_min, seed_scale_max, size_roll * size_roll)
		grain.rotation = Vector3(-PI * 0.5, randf() * TAU, 0.0)
		add_child(grain)
		var radius := ground_scatter_radius * pow(randf(), 0.8)
		var angle := randf() * TAU
		# Elipse alongada na direção do arremesso (SEED-002).
		var along := cos(angle) * radius * ground_scatter_stretch
		var across := sin(angle) * radius
		var dir := _throw_direction
		var side := Vector2(-dir.y, dir.x)
		var offset := dir * along + side * across
		# Pequeno degrau em Y evita z-fighting entre grãos sobrepostos.
		grain.global_position = Vector3(center.x + offset.x, ground_y + 0.004 * i, center.z + offset.y)
		var tween := grain.create_tween()
		tween.tween_interval(ground_grain_lifetime * randf_range(0.35, 0.6))
		tween.tween_property(grain, "modulate:a", 0.0, ground_grain_lifetime * 0.4)

## Velocidade inicial para que o centro do punhado chegue ao alvo sob gravidade.
static func solve_launch_velocity(origin: Vector3, target: Vector3, gravity_vector: Vector3, time: float) -> Vector3:
	var t := maxf(time, 0.1)
	return (target - origin - 0.5 * gravity_vector * t * t) / t
