
extends Boxer

signal ability_announced(message: String)

@export_group("Curación")
@export var heal_amount: float = 30.0
@export var heal_duration: float = 1.6
@export var heal_cooldown: float = 2.0
@export var heal_health_threshold: float = 0.95

@export_group("Retirada")
@export var retreat_distance: float = 180.0
@export var retreat_speed_multiplier: float = 1.15
@export var retreat_max_duration: float = 2.0

var _is_retreating: bool = false
var _is_healing: bool = false

var _decision_timer: float = 3.0
var _cooldown_timer: float = 3.0
var _retreat_timer: float = 0.0

var _heal_token: int = 0


func _ready() -> void:
	super._ready()
	_decision_timer = randf_range(2.0, 4.0)


func _enemy_ai(delta: float) -> void:
	if _is_healing:
		velocity = Vector2.ZERO
		return

	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	if _is_retreating:
		_process_retreat(delta)
		return

	_decision_timer -= delta

	if _decision_timer <= 0.0:
		_decision_timer = randf_range(2.0, 4.0)

		var health_ratio: float = health / max_health

		if (
			_cooldown_timer <= 0.0
			and health_ratio < heal_health_threshold
			and randf() < 0.80
		):
			_start_retreat()
			return

	super._enemy_ai(delta)


func _start_retreat() -> void:
	if opponent == null:
		return

	_is_retreating = true
	_retreat_timer = retreat_max_duration
	velocity = Vector2.ZERO


func _process_retreat(delta: float) -> void:
	if opponent == null:
		_is_retreating = false
		velocity = Vector2.ZERO
		return

	var away_x: float = global_position.x - opponent.global_position.x
	var distance: float = absf(away_x)

	if distance >= retreat_distance or _retreat_timer <= 0.0:
		_is_retreating = false
		velocity = Vector2.ZERO
		_start_healing()
		return

	_retreat_timer -= delta

	if not is_zero_approx(away_x):
		velocity = Vector2(signf(away_x) * move_speed * retreat_speed_multiplier, 0.0)
	else:
		velocity = Vector2.RIGHT * move_speed


func _start_healing() -> void:
	if _is_healing:
		return

	_is_healing = true
	SoundManager.play_sfx("heal", -1.5, 0.03)
	_spawn_combat_effect("heal", global_position + Vector2(0.0, -48.0), Vector2.UP)
	_heal_token += 1

	var my_token: int = _heal_token

	attack_animation_active = true
	action_lock = heal_duration

	ability_announced.emit("%s is using healing" % boxer_name)

	_play_anim("heal")

	await get_tree().create_timer(heal_duration).timeout

	# Si recibió un golpe, la curación queda cancelada.
	if my_token != _heal_token:
		return

	if not is_inside_tree():
		return

	health = minf(health + heal_amount, max_health)
	_spawn_combat_effect("heal", global_position + Vector2(0.0, -48.0), Vector2.UP)
	stats_changed.emit(self)

	_is_healing = false
	attack_animation_active = false
	action_lock = 0.0
	_cooldown_timer = heal_cooldown
	_decision_timer = randf_range(2.0, 4.0)

	_play_anim("idle")


func _on_interrupted_by_hit() -> void:
	if _is_healing:
		_heal_token += 1
		_is_healing = false
		attack_animation_active = false
		action_lock = 0.0
		_cooldown_timer = heal_cooldown

	if _is_retreating:
		_is_retreating = false
		velocity = Vector2.ZERO
