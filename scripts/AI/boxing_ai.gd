
extends RefCounted

var decision_cooldown: float = 0.0
var action_cooldown: float = 0.0
var dash_cooldown: float = 0.0
var mode: String = "approach"

const ATTACK_RANGE: float = 150.0
const COMFORT_DISTANCE: float = 100.0
const RETREAT_DISTANCE: float = 165.0
const DASH_COST: float = 18.0

const DASH_ESCAPE_DISTANCE: float = 65.0
const DASH_APPROACH_DISTANCE: float = 230.0

const DASH_ESCAPE_COOLDOWN: float = 1.2
const DASH_APPROACH_COOLDOWN: float = 1.7


func update(boxer: Variant, delta: float) -> void:
	if boxer == null or not is_instance_valid(boxer):
		return

	decision_cooldown = maxf(0.0, decision_cooldown - delta)
	action_cooldown = maxf(0.0, action_cooldown - delta)
	dash_cooldown = maxf(0.0, dash_cooldown - delta)

	var rival = boxer.opponent

	if rival == null or not is_instance_valid(rival) or rival.is_out:
		boxer.velocity = Vector2.ZERO
		boxer.guarding = false
		return

	var offset_x: float = rival.global_position.x - boxer.global_position.x
	var distance: float = absf(offset_x)
	var toward := Vector2(signf(offset_x), 0.0)

	boxer.guarding = false

	# Elegir una acción cuando termina el tiempo de decisión.
	if decision_cooldown <= 0.0:
		decision_cooldown = randf_range(0.15, 0.30)

		if distance > ATTACK_RANGE:
			if (
				distance > DASH_APPROACH_DISTANCE
				and boxer.stamina >= DASH_COST
				and dash_cooldown <= 0.0
				and randf() < 0.25
			):
				mode = "dash_in"
			else:
				mode = "approach"
		else:
			var roll := randf()

			if (
				distance < DASH_ESCAPE_DISTANCE
				and boxer.stamina >= DASH_COST
				and dash_cooldown <= 0.0
				and roll < 0.10
			):
				mode = "dash_out"
			elif roll < 0.82:
				mode = "attack"
			elif roll < 0.92:
				mode = "guard"
			else:
				mode = "retreat"

	# Ejecutar la acción elegida.
	match mode:
		"approach":
			boxer.velocity = toward * boxer.move_speed * 0.70

			if distance <= COMFORT_DISTANCE:
				boxer.velocity = Vector2.ZERO
				mode = "attack"

		"retreat":
			boxer.velocity = -toward * boxer.move_speed * 0.50

			if distance >= RETREAT_DISTANCE:
				boxer.velocity = Vector2.ZERO
				mode = "approach"

		"dash_in":
			boxer.velocity = Vector2.ZERO

			if (
				dash_cooldown <= 0.0
				and boxer.stamina >= DASH_COST
				and boxer.dash_time <= 0.0
			):
				boxer._start_dash(toward)
				dash_cooldown = DASH_APPROACH_COOLDOWN

			mode = "approach"

		"dash_out":
			boxer.velocity = Vector2.ZERO

			if (
				dash_cooldown <= 0.0
				and boxer.stamina >= DASH_COST
				and boxer.dash_time <= 0.0
			):
				boxer._start_dash(-toward)
				dash_cooldown = DASH_ESCAPE_COOLDOWN

			mode = "retreat"

		"guard":
			boxer.velocity = Vector2.ZERO
			boxer.guarding = boxer.stamina > 0.0

		"attack":
			if distance > ATTACK_RANGE:
				boxer.velocity = toward * boxer.move_speed * 0.70
				mode = "approach"
			else:
				boxer.velocity = Vector2.ZERO

				if (
					action_cooldown <= 0.0
					and boxer.action_lock <= 0.0
					and boxer.attack_cooldown <= 0.0
					and not boxer.attack_animation_active
					and not boxer.guarding
					and boxer.hit_stun_time <= 0.0
				):
					var attack_roll := randf()

					if attack_roll < 0.55:
						boxer._attack("jab")
					elif attack_roll < 0.85:
						boxer._attack("cross")
					else:
						boxer._attack("upper")

					action_cooldown = randf_range(0.20, 0.35)

		_:
			boxer.velocity = Vector2.ZERO


func reset() -> void:
	decision_cooldown = 0.0
	action_cooldown = 0.0
	dash_cooldown = 0.0
	mode = "approach"
