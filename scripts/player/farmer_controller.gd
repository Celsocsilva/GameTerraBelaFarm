extends CharacterBody3D
class_name FarmerController

@export var move_speed: float = 4.0
@export var acceleration: float = 18.0
@export var deceleration: float = 24.0
@export var gravity: float = 18.0
## SOW-SPEED-001: fração da velocidade enquanto semeia sobre o canteiro (o
## FarmWorld liga `sowing`). A troca é suave para não dar tranco.
@export_range(0.2, 1.0, 0.05) var sowing_speed_factor: float = 0.55
var sowing := false
var _speed_factor := 1.0
@export var joystick_path: NodePath = NodePath("../HUD/VirtualJoystick")

var _joystick: Control
var _camera: Camera3D
## FARMER-GAME-001: modelo 3D (assets/animations/Farmer/farmer_character.tscn) e seu animador.
var visual: Node3D
var animator: FarmerAnimator

func _ready() -> void:
    _camera = get_viewport().get_camera_3d()
    _joystick = get_node_or_null(joystick_path)
    visual = get_node_or_null("Visual") as Node3D
    if visual:
        animator = visual.get_node_or_null("FarmerAnimator") as FarmerAnimator
    if animator:
        animator.model_scale = visual.scale.y

## FLICK-002: move no _process (e não no _physics_process) para andar no mesmo
## ritmo da câmera. No celular a tela roda a 120 Hz e a física a 60 Hz: com a
## câmera suave e o fazendeiro em passos de física, o modelo e a sombra pareciam
## tremer/deixar um rastro do quadro anterior.
func _process(delta: float) -> void:
    if _joystick == null:
        _joystick = get_node_or_null("../HUD/VirtualJoystick")
    var input_vector := _read_input()
    _speed_factor = move_toward(_speed_factor, sowing_speed_factor if sowing else 1.0, delta * 2.5)
    var target := Vector3(input_vector.x, 0.0, input_vector.y) * move_speed * _speed_factor
    var rate := acceleration if input_vector.length_squared() > 0.001 else deceleration
    velocity.x = move_toward(velocity.x, target.x, rate * delta)
    velocity.z = move_toward(velocity.z, target.z, rate * delta)
    if is_on_floor():
        velocity.y = -0.5
    else:
        velocity.y -= gravity * delta
    if input_vector.length_squared() > 0.001:
        var facing := Vector3(input_vector.x, 0.0, input_vector.y)
        rotation.y = lerp_angle(rotation.y, atan2(-facing.x, -facing.z), min(1.0, delta * 12.0))
    move_and_slide()
    if animator:
        animator.update_locomotion(get_horizontal_speed())

## Velocidade real no chão (depois das colisões), usada pela animação.
func get_horizontal_speed() -> float:
    return Vector2(get_real_velocity().x, get_real_velocity().z).length()

func _read_input() -> Vector2:
    var keyboard := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    if keyboard.length_squared() > 0.001:
        return keyboard
    if _joystick and _joystick.has_method("get_output"):
        return _joystick.get_output()
    return Vector2.ZERO
