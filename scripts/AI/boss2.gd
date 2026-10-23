
extends Boxer

signal ability_announced(message: String)

@export_group("Estadísticas del jefe")
@export var boss2_max_health: float = 100.0

@export_group("Movimiento")
@export var chase_speed: float = 115.0
@export var attack_distance: float = 65.0

@export_group("Probabilidades de ataque")
@export_range(0.0, 1.0) var critical_probability: float = 0.25
@export_range(0.0, 1.0) var jab_probability: float = 0.25
@export_range(0.0, 1.0) var cross_probability: float = 0.25
@export_range(0.0, 1.0) var upper_probability: float = 0.25

@export_group("Golpe crítico")
@export var critical_damage_percent: float = 0.25
@export var critical_windup: float = 0.65
@export var critical_duration: float = 0.25
@export var critical_knockback: float = 220.0

var _critical_decision_timer: float = 0.2
var _critical_in_progress: bool = false
var _critical_token: int = 0


func _ready() -> void:
	max_health = boss2_max_health
	move_speed = chase_speed
	super._ready()
	health = max_health
	stats_changed.emit(self)


func _enemy_ai(delta: float) -> void:
	if is_out:
		velocity = Vector2.ZERO
		return

	if opponent == null or not is_instance_valid(opponent) or opponent.is_out:
		velocity = Vector2.ZERO
		return

	if _critical_in_progress or attack_animation_active or action_lock > 0.0:
		velocity = Vector2.ZERO
		return

	var difference_x: float = opponent.global_position.x - global_position.x

	# Mirar hacia el jugador.
	facing = 1 if difference_x >= 0.0 else -1
	_update_attack_directions()
	_update_sprite_direction()

	# Perseguir al jugador si está lejos.
	if absf(difference_x) > attack_distance:
		velocity = Vector2(signf(difference_x) * chase_speed, 0.0)
		return

	# Detenerse cuando esté cerca para atacar.
	velocity = Vector2.ZERO

	_critical_decision_timer -= delta

	if _critical_decision_timer > 0.0:
		return

	_critical_decision_timer = 0.2

	# Elegir uno de los cuatro ataques con 25% de probabilidad.
	var roll: float = randf()

	if roll < critical_probability:
		_start_critical()
	elif roll < critical_probability + jab_probability:
		_attack("jab")
	elif roll < critical_probability + jab_probability + cross_probability:
		_attack("cross")
	else:
		_attack("upper")


func _start_critical() -> void:
	if _critical_in_progress or is_out:
		return

	if opponent == null or not is_instance_valid(opponent) or opponent.is_out:
		return

	if attack_critical == null or critical_shape == null:
		push_error("Boss2: falta AttackCritical o su CollisionShape2D.")
		return

	if critical_shape.shape == null or critical_shape.disabled:
		push_error("Boss2: revisá la forma y Disabled de AttackCritical.")
		return

	_critical_in_progress = true
	SoundManager.play_sfx("critical_charge", -1.5, 0.025)
	_spawn_combat_effect("charge", global_position + Vector2(0.0, -52.0), Vector2.UP)
	_critical_token += 1
	var my_token: int = _critical_token

	facing = 1 if opponent.global_position.x >= global_position.x else -1
	_update_attack_directions()
	_update_sprite_direction()

	attack_sequence += 1
	var this_attack: int = attack_sequence

	_deactivate_all_hitboxes()

	attack_animation_active = true
	guarding = false
	velocity = Vector2.ZERO
	action_lock = critical_windup + critical_duration

	ability_announced.emit("%s is charging a critical strike" % boxer_name)

	if animated_sprite.sprite_frames == null:
		_cancel_critical()
		return

	if not animated_sprite.sprite_frames.has_animation("critical"):
		push_error("Boss2: no existe la animación critical.")
		_cancel_critical()
		return

	current_animation = &"critical"
	animated_sprite.play("critical")

	# Tiempo de preparación antes de golpear.
	await get_tree().create_timer(critical_windup).timeout

	if not is_inside_tree() or my_token != _critical_token:
		return

	if is_out or opponent == null or not is_instance_valid(opponent):
		_cancel_critical()
		return

	if opponent.is_out or this_attack != attack_sequence:
		_cancel_critical()
		return

	# Actualizar la dirección antes del impacto.
	facing = 1 if opponent.global_position.x >= global_position.x else -1
	_update_attack_directions()
	_update_sprite_direction()

	_spawn_combat_effect("special", global_position + Vector2(float(facing) * 24.0, -52.0), Vector2(float(facing), 0.0))
	active_attack_area = attack_critical
	active_attack_damage = opponent.max_health * critical_damage_percent
	active_attack_knockback = critical_knockback
	hit_targets.clear()

	attack_critical.set_deferred("monitoring", true)

	await get_tree().physics_frame

	if not is_inside_tree() or my_token != _critical_token:
		return

	for body in attack_critical.get_overlapping_bodies():
		_try_hit_body(body, attack_critical)

	# Mantener activa la hitbox durante el impacto.
	await get_tree().create_timer(critical_duration).timeout

	if not is_inside_tree() or my_token != _critical_token:
		return

	_deactivate_all_hitboxes()

	_critical_in_progress = false
	attack_animation_active = false
	action_lock = 0.0
	_critical_decision_timer = 0.2

	if not is_out:
		_play_anim("idle")


func _cancel_critical() -> void:
	_critical_token += 1
	_critical_in_progress = false
	attack_animation_active = false
	action_lock = 0.0

	_deactivate_all_hitboxes()

	if not is_out:
		_play_anim("idle")


func _on_interrupted_by_hit() -> void:
	if _critical_in_progress:
		_cancel_critical()
