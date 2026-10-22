
extends CharacterBody2D
class_name Boxer

const BoxingAIController = preload("res://scripts/AI/boxing_ai.gd")
 
const HIT_EFFECT_SCENE = preload("res://Scenes/HitEffect.tscn")



signal stats_changed(boxer: Boxer)
signal knocked_out(boxer: Boxer)

@export var is_player: bool = true
@export var boxer_name: String = "Boxeador"
@export var max_health: float = 100.0
@export var max_stamina: float = 100.0
@export var move_speed: float = 190.0

@export var jab_damage: float = 6.0
@export var cross_damage: float = 12.0
@export var upper_damage: float = 16.0

@export_group("Estamina")
@export var stamina_regen_delay: float = 1.1
@export var stamina_regen_rate: float = 22.0

@export_group("Aturdimiento")
@export var hit_stun_duration: float = 0.25

@export_group("Retroceso")
@export var jab_knockback: float = 100.0
@export var cross_knockback: float = 180.0
@export var upper_knockback: float = 260.0
@export var knockback_friction: float = 900.0

@export_group("Animaciones")
@export var anim_idle: StringName = &"idle"
@export var anim_walk: StringName = &"walk"
@export var anim_jab: StringName = &"jab"
@export var anim_cross: StringName = &"cross"
@export var anim_upper: StringName = &"upper"
@export var anim_block: StringName = &"block"
@export var anim_dash: StringName = &"dash"
@export var anim_hit: StringName = &"hit"
@export var anim_ko: StringName = &"ko"

@export_group("Hitboxes")
@export var jab_active_delay: float = 0.09
@export var cross_active_delay: float = 0.14
@export var upper_active_delay: float = 0.12

@export var jab_active_duration: float = 0.11
@export var cross_active_duration: float = 0.13
@export var upper_active_duration: float = 0.22

@export_group("Sprite")
@export var sprite_scale: float = 1.0
@export var sprite_faces_left: bool = false

const JAB_COST := 8.0
const CROSS_COST := 15.0
const UPPER_COST := 20.0
const BLOCK_DRAIN := 12.0
const DASH_COST := 18.0

var health: float
var stamina: float
var facing: int = 1
var opponent: Boxer

var guarding := false
var attack_cooldown := 0.0
var dash_time := 0.0
var dash_direction: Vector2 = Vector2.ZERO
var is_out := false
var action_lock := 0.0
var regen_wait := 0.0
var hit_stun_time := 0.0
var footstep_timer := 0.0

var knockback_velocity: Vector2 = Vector2.ZERO

var current_animation: StringName = &""
var attack_animation_active := false

var ai_controller = BoxingAIController.new()

var active_attack_area: Area2D = null
var active_attack_damage: float = 0.0
var active_attack_knockback: float = 0.0
var attack_sequence: int = 0
var hit_targets: Dictionary = {}

# Posiciones originales de las hitboxes.
var jab_area_origin: Vector2
var cross_area_origin: Vector2
var upper_area_origin: Vector2
var critical_area_origin: Vector2

var jab_shape_origin: Vector2
var cross_shape_origin: Vector2
var upper_shape_origin: Vector2
var critical_shape_origin: Vector2

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

@onready var attack_jab: Area2D = $AttackJab
@onready var attack_cross: Area2D = $AttackCross
@onready var attack_upper: Area2D = $AttackUpper

@onready var jab_shape: CollisionShape2D = $AttackJab/CollisionShape2D
@onready var cross_shape: CollisionShape2D = $AttackCross/CollisionShape2D
@onready var upper_shape: CollisionShape2D = $AttackUpper/CollisionShape2D

# Opcionales: el rival básico y Boss1 no necesitan tenerlos.
@onready var attack_critical: Area2D = (
	get_node_or_null("AttackCritical") as Area2D
)

@onready var critical_shape: CollisionShape2D = (
	get_node_or_null("AttackCritical/CollisionShape2D")
	as CollisionShape2D
)


func _ready() -> void:
	health = max_health
	stamina = max_stamina

	add_to_group("boxers")
	animated_sprite.scale = Vector2(sprite_scale, sprite_scale)

	if animated_sprite.sprite_frames == null:
		push_warning(boxer_name + ": AnimatedSprite2D no tiene SpriteFrames.")

	jab_area_origin = attack_jab.position
	cross_area_origin = attack_cross.position
	upper_area_origin = attack_upper.position

	jab_shape_origin = jab_shape.position
	cross_shape_origin = cross_shape.position
	upper_shape_origin = upper_shape.position

	attack_jab.body_entered.connect(
		_on_attack_body_entered.bind(attack_jab)
	)
	attack_cross.body_entered.connect(
		_on_attack_body_entered.bind(attack_cross)
	)
	attack_upper.body_entered.connect(
		_on_attack_body_entered.bind(attack_upper)
	)

	attack_jab.monitoring = false
	attack_cross.monitoring = false
	attack_upper.monitoring = false

	# Preparar la hitbox crítica únicamente si existe.
	if attack_critical != null and critical_shape != null:
		critical_area_origin = attack_critical.position
		critical_shape_origin = critical_shape.position

		attack_critical.body_entered.connect(
			_on_attack_body_entered.bind(attack_critical)
		)
		attack_critical.monitoring = false

	_update_attack_directions()
	_update_sprite_direction()

	stats_changed.emit(self)


func _physics_process(delta: float) -> void:
	if is_out:
		velocity = Vector2.ZERO
		knockback_velocity = Vector2.ZERO

		_play_anim(anim_ko)

		return

	footstep_timer = maxf(0.0, footstep_timer - delta)
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	action_lock = maxf(0.0, action_lock - delta)
	regen_wait = maxf(0.0, regen_wait - delta)

	# Girar hacia el rival.
	if opponent != null and is_instance_valid(opponent) and not opponent.is_out:
		var new_facing := (
			1 if opponent.global_position.x >= global_position.x else -1
		)

		if new_facing != facing:
			facing = new_facing
			_update_attack_directions()
			_update_sprite_direction()

	if hit_stun_time > 0.0:
		hit_stun_time = maxf(0.0, hit_stun_time - delta)
		guarding = false
		dash_time = 0.0

		_apply_knockback(delta)
		move_and_slide()
		stats_changed.emit(self)
		return

	if dash_time > 0.0:
		dash_time = maxf(0.0, dash_time - delta)
		velocity = dash_direction * move_speed * 2.8
		guarding = false
		_play_anim(anim_dash)

	elif attack_animation_active:
		velocity = Vector2.ZERO

	elif action_lock > 0.0:
		velocity = Vector2.ZERO

	elif is_player:
		_player_controls()

	else:
		_enemy_ai(delta)

	if guarding:
		stamina = maxf(0.0, stamina - BLOCK_DRAIN * delta)
		regen_wait = stamina_regen_delay

		if stamina <= 0.0:
			guarding = false

	elif regen_wait <= 0.0 and action_lock <= 0.0 and dash_time <= 0.0:
		stamina = minf(
			max_stamina,
			stamina + stamina_regen_rate * delta
		)

	_apply_knockback(delta)
	move_and_slide()

	if (
		footstep_timer <= 0.0
		and velocity.length() > 28.0
		and dash_time <= 0.0
		and not guarding
		and not attack_animation_active
		and action_lock <= 0.0
	):
		SoundManager.play_sfx("footstep", -12.0, 0.12)
		footstep_timer = 0.36

	if not attack_animation_active:
		if guarding and dash_time <= 0.0:
			_play_anim(anim_block)
		elif dash_time <= 0.0 and action_lock <= 0.0:
			if velocity.length() > 8.0:
				_play_anim(anim_walk)
			else:
				_play_anim(anim_idle)

	stats_changed.emit(self)


# --------------------------------------------------
# DIRECCION DE LAS HITBOXES
# --------------------------------------------------

func _update_attack_directions() -> void:
	attack_jab.position = jab_area_origin
	attack_cross.position = cross_area_origin
	attack_upper.position = upper_area_origin

	var sprite_x: float = animated_sprite.position.x

	var jab_total_x: float = jab_area_origin.x + jab_shape_origin.x
	var cross_total_x: float = cross_area_origin.x + cross_shape_origin.x
	var upper_total_x: float = upper_area_origin.x + upper_shape_origin.x

	var jab_target_x: float = sprite_x + (jab_total_x - sprite_x) * facing
	var cross_target_x: float = sprite_x + (cross_total_x - sprite_x) * facing
	var upper_target_x: float = sprite_x + (upper_total_x - sprite_x) * facing

	jab_shape.position = Vector2(
		jab_target_x - jab_area_origin.x,
		jab_shape_origin.y
	)

	cross_shape.position = Vector2(
		cross_target_x - cross_area_origin.x,
		cross_shape_origin.y
	)

	upper_shape.position = Vector2(
		upper_target_x - upper_area_origin.x,
		upper_shape_origin.y
	)

	# Reflejar también la hitbox crítica del jefe 2.
	if attack_critical != null and critical_shape != null:
		attack_critical.position = critical_area_origin

		var critical_total_x: float = (
			critical_area_origin.x + critical_shape_origin.x
		)

		var critical_target_x: float = (
			sprite_x + (critical_total_x - sprite_x) * facing
		)

		critical_shape.position = Vector2(
			critical_target_x - critical_area_origin.x,
			critical_shape_origin.y
		)


func _update_sprite_direction() -> void:
	animated_sprite.flip_h = (facing < 0) != sprite_faces_left


# --------------------------------------------------
# RETROCESO
# --------------------------------------------------

func _apply_knockback(delta: float) -> void:
	if knockback_velocity.length() > 1.0:
		velocity = knockback_velocity
		knockback_velocity = knockback_velocity.move_toward(
			Vector2.ZERO,
			knockback_friction * delta
		)
	else:
		knockback_velocity = Vector2.ZERO


# --------------------------------------------------
# CONTROLES DEL JUGADOR
# --------------------------------------------------

func _player_controls() -> void:
	var input_direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
        "move_down"
	)

	guarding = Input.is_action_pressed("block") and stamina > 0.0

	if guarding:
		velocity = input_direction * move_speed * 0.30
	else:
		velocity = input_direction * move_speed

	if Input.is_action_just_pressed("dash"):
		if input_direction != Vector2.ZERO:
			_start_dash(input_direction)

	if not guarding and dash_time <= 0.0:
		if Input.is_action_just_pressed("jab"):
			_attack("jab")
		elif Input.is_action_just_pressed("cross"):
			_attack("cross")
		elif Input.is_action_just_pressed("upper"):
			_attack("upper")


# --------------------------------------------------
# INTELIGENCIA ARTIFICIAL
# --------------------------------------------------

func _enemy_ai(delta: float) -> void:
	ai_controller.update(self, delta)


# --------------------------------------------------
# DASH
# --------------------------------------------------

func _start_dash(direction: Vector2) -> void:
	if stamina < DASH_COST:
		return
	if dash_time > 0.0 or action_lock > 0.0:
		return
	if attack_animation_active or hit_stun_time > 0.0:
		return
	if direction == Vector2.ZERO:
		return

	stamina -= DASH_COST
	SoundManager.play_sfx("dash", -3.0, 0.08)
	regen_wait = stamina_regen_delay
	dash_direction = direction.normalized()
	dash_time = 0.18
	guarding = false

	_play_anim(anim_dash)
	stats_changed.emit(self)


# --------------------------------------------------
# ATAQUES NORMALES
# --------------------------------------------------

func _attack(kind: String) -> void:
	print(boxer_name, " intenta ejecutar: ", kind)

	if attack_cooldown > 0.0 or guarding or dash_time > 0.0:
		print("Ataque cancelado: cooldown, bloqueo o dash.")
		return

	if action_lock > 0.0 or attack_animation_active or hit_stun_time > 0.0:
		print("Ataque cancelado: acción bloqueada o aturdimiento.")
		return

	if opponent == null or not is_instance_valid(opponent) or opponent.is_out:
		print("Ataque cancelado: rival inválido.")
		return

	var cost := JAB_COST
	var damage := jab_damage
	var knockback := jab_knockback
	var cooldown := 0.30
	var anim: StringName = anim_jab
	var active_delay := jab_active_delay
	var active_duration := jab_active_duration
	var hitbox: Area2D = attack_jab

	match kind:
		"jab":
			pass

		"cross":
			cost = CROSS_COST
			damage = cross_damage
			knockback = cross_knockback
			cooldown = 0.52
			anim = anim_cross
			active_delay = cross_active_delay
			active_duration = cross_active_duration
			hitbox = attack_cross

		"upper":
			cost = UPPER_COST
			damage = upper_damage
			knockback = upper_knockback
			cooldown = 0.68
			anim = anim_upper
			active_delay = upper_active_delay
			active_duration = upper_active_duration
			hitbox = attack_upper

		_:
			push_warning("Ataque desconocido: " + kind)
			return

	if animated_sprite.sprite_frames == null:
		push_warning("No hay SpriteFrames asignados.")
		return

	if not animated_sprite.sprite_frames.has_animation(anim):
		push_warning("No existe la animación: " + String(anim))
		return

	var fps := animated_sprite.sprite_frames.get_animation_speed(anim)
	var frame_count := animated_sprite.sprite_frames.get_frame_count(anim)

	if fps <= 0.0 or frame_count <= 0:
		push_warning("Animación sin FPS o fotogramas: " + String(anim))
		return

	if stamina < cost:
		print("Ataque cancelado: estamina insuficiente.")
		return

	var animation_duration := float(frame_count) / fps

	attack_sequence += 1
	var this_attack := attack_sequence

	_deactivate_all_hitboxes()

	stamina -= cost
	regen_wait = stamina_regen_delay
	attack_cooldown = cooldown
	guarding = false
	velocity = Vector2.ZERO
	attack_animation_active = true
	action_lock = animation_duration + 0.05

	current_animation = anim
	_update_sprite_direction()
	animated_sprite.play(anim)
	SoundManager.play_sfx("swing_" + kind, -3.0, 0.06)

	print(
		boxer_name,
		" inició ", kind,
		" | daño: ", damage,
		" | hitbox: ", hitbox.name
	)

	_activate_hitbox_after_delay(
		hitbox,
		active_delay,
		active_duration,
		damage,
		knockback,
		this_attack
	)

	await get_tree().create_timer(animation_duration).timeout

	if not is_inside_tree():
		return
	if this_attack != attack_sequence:
		return

	_deactivate_all_hitboxes()
	attack_animation_active = false
	action_lock = 0.0
	current_animation = &""

	stats_changed.emit(self)


func _activate_hitbox_after_delay(
	hitbox: Area2D,
	delay: float,
	duration: float,
	damage: float,
	knockback: float,
	this_attack: int
) -> void:
	await get_tree().create_timer(delay).timeout

	if not is_inside_tree():
		return
	if this_attack != attack_sequence:
		return
	if is_out or not attack_animation_active:
		return
	if opponent == null or not is_instance_valid(opponent) or opponent.is_out:
		return

	active_attack_area = hitbox
	active_attack_damage = damage
	active_attack_knockback = knockback
	hit_targets.clear()

	hitbox.set_deferred("monitoring", true)

	print(boxer_name, " activó la hitbox: ", hitbox.name)

	await get_tree().physics_frame

	if not is_inside_tree():
		return
	if this_attack != attack_sequence or active_attack_area != hitbox:
		return

	var cuerpos_detectados := hitbox.get_overlapping_bodies()

	print(
		"DIAGNÓSTICO | ", boxer_name,
		" | Hitbox: ", hitbox.name,
		" | Cuerpos detectados: ", cuerpos_detectados.size()
	)

	for body in cuerpos_detectados:
		print("Cuerpo encontrado: ", body.name)
		_try_hit_body(body, hitbox)

	await get_tree().create_timer(duration).timeout

	if not is_inside_tree():
		return
	if this_attack != attack_sequence:
		return

	_deactivate_all_hitboxes()


func _on_attack_body_entered(body: Node2D, hitbox: Area2D) -> void:
	_try_hit_body(body, hitbox)


func _try_hit_body(body: Node2D, hitbox: Area2D) -> void:
	if hitbox != active_attack_area:
		return
	if not attack_animation_active or is_out:
		return
	if not body is Boxer:
		return

	var target := body as Boxer

	if target == self or target != opponent or target.is_out:
		return

	var target_id := target.get_instance_id()

	if hit_targets.has(target_id):
		return


	
	hit_targets[target_id] = true

	print(
	boxer_name, " conectó ", hitbox.name,
	" contra ", target.boxer_name
)

	_spawn_hit_effect(target)


	hit_targets[target_id] = true

	print(
		boxer_name, " conectó ", hitbox.name,
		" contra ", target.boxer_name
	)


	# Si se activa AttackCritical, el daño es el 25 %
	# de la vida máxima del rival.
	if attack_critical != null and hitbox == attack_critical:
		var critical_damage: float = target.max_health * 0.25

		print(
			"¡GOLPE CRÍTICO! Daño base: ",
			critical_damage,
			" | 25 % de la vida máxima de ",
			target.boxer_name
		)

		target.receive_hit(
			critical_damage,
			active_attack_knockback,
			global_position
		)
	else:
		target.receive_hit(
			active_attack_damage,
			active_attack_knockback,
			global_position
		)


func _deactivate_all_hitboxes() -> void:
	if is_instance_valid(attack_jab):
		attack_jab.set_deferred("monitoring", false)

	if is_instance_valid(attack_cross):
		attack_cross.set_deferred("monitoring", false)

	if is_instance_valid(attack_upper):
		attack_upper.set_deferred("monitoring", false)

	if attack_critical != null:
		attack_critical.set_deferred("monitoring", false)

	active_attack_area = null
	active_attack_damage = 0.0
	active_attack_knockback = 0.0
	hit_targets.clear()


# --------------------------------------------------
# RECIBIR DAÑO
# --------------------------------------------------

func receive_hit(
	amount: float,
	knockback: float = 0.0,
	attacker_position: Vector2 = Vector2.ZERO
) -> void:
	if is_out:
		return

	var final_damage := amount

	if guarding:
		SoundManager.play_sfx("block", -2.5, 0.08)
		final_damage *= 0.25
		stamina = maxf(0.0, stamina - amount * 1.1)
		regen_wait = stamina_regen_delay

		if stamina <= 0.0:
			guarding = false
	else:
		var impact_sound := "impact_heavy" if amount >= 14.0 else "impact_light"
		SoundManager.play_sfx(impact_sound, -1.5, 0.08)
		# Permite que los jefes cancelen habilidades
		# cuando reciben un golpe que no han bloqueado.
		_on_interrupted_by_hit()

		attack_sequence += 1
		_deactivate_all_hitboxes()

		velocity = Vector2.ZERO
		guarding = false
		dash_time = 0.0
		attack_animation_active = false
		action_lock = 0.0

		var push_direction := global_position - attacker_position

		if push_direction.length_squared() > 0.001:
			push_direction = push_direction.normalized()
		else:
			push_direction = Vector2(-float(facing), 0.0)

		knockback_velocity = push_direction * knockback

		if (
			animated_sprite.sprite_frames != null
			and animated_sprite.sprite_frames.has_animation(anim_hit)
		):
			var fps := animated_sprite.sprite_frames.get_animation_speed(anim_hit)
			var frames := animated_sprite.sprite_frames.get_frame_count(anim_hit)

			if fps > 0.0 and frames > 0:
				hit_stun_time = maxf(
					hit_stun_duration,
					float(frames) / fps
				)
			else:
				hit_stun_time = hit_stun_duration
		else:
			hit_stun_time = hit_stun_duration

		current_animation = &""
		_play_anim(anim_hit)

	health = maxf(0.0, health - final_damage)

	print(
		boxer_name, " recibió ", final_damage,
		" de daño. Vida restante: ", health
	)

	stats_changed.emit(self)

	if health <= 0.0:
		is_out = true
		attack_sequence += 1
		_deactivate_all_hitboxes()

		hit_stun_time = 0.0
		velocity = Vector2.ZERO
		knockback_velocity = Vector2.ZERO
		guarding = false
		attack_animation_active = false
		current_animation = &""


		# El KO se reproduce una sola vez y no debe entrar en bucle.
		if animated_sprite.sprite_frames != null:
			if animated_sprite.sprite_frames.has_animation(anim_ko):
				animated_sprite.sprite_frames.set_animation_loop(
					anim_ko,
					false
				)

				current_animation = anim_ko
				_update_sprite_direction()
				animated_sprite.play(anim_ko)
			else:
				push_warning("No existe la animación de KO: " + String(anim_ko))


		_play_anim(anim_ko)

		SoundManager.play_sfx("knockout", 0.0, 0.03)
		knocked_out.emit(self)


# Las clases de los jefes podrán sobrescribir este método.
func _on_interrupted_by_hit() -> void:
	pass


# --------------------------------------------------
# REINICIAR ROUND
# --------------------------------------------------

func reset_for_round() -> void:
	attack_sequence += 1
	_deactivate_all_hitboxes()

	health = max_health
	stamina = max_stamina
	guarding = false
	attack_cooldown = 0.0
	dash_time = 0.0
	dash_direction = Vector2.ZERO
	action_lock = 0.0
	regen_wait = 0.0
	footstep_timer = 0.0
	hit_stun_time = 0.0
	knockback_velocity = Vector2.ZERO
	is_out = false
	attack_animation_active = false
	velocity = Vector2.ZERO
	current_animation = &""

	_update_attack_directions()
	_update_sprite_direction()
	ai_controller.reset()
	_play_anim(anim_idle)


# --------------------------------------------------
# ANIMACIONES
# --------------------------------------------------


func _play_anim(anim_name: StringName) -> void:
	if animated_sprite.sprite_frames == null:
		return

	if not animated_sprite.sprite_frames.has_animation(anim_name):
		push_warning("No existe la animación: " + String(anim_name))
		return


	# No reiniciar una animación que ya está reproduciéndose.

	if current_animation == anim_name and animated_sprite.is_playing():
		return

	current_animation = anim_name
	_update_sprite_direction()
	animated_sprite.play(anim_name)

#PARTICULAS#

func _spawn_hit_effect(target: Node2D) -> void:
	for i in range(3):
		var effect = HIT_EFFECT_SCENE.instantiate()
		get_tree().current_scene.add_child(effect)

		effect.global_position = (
			global_position + target.global_position
		) / 2.0

		effect.position += Vector2(
			randf_range(-12.0, 12.0),
			randf_range(-12.0, 12.0)
		)
