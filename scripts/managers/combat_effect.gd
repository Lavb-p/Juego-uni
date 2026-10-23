extends Node2D

const SPARK := preload("res://addons/kenney_particle_pack/spark_02.png")
const SPARK_SMALL := preload("res://addons/kenney_particle_pack/spark_01.png")
const FLASH := preload("res://addons/kenney_particle_pack/flare_01.png")
const SHIELD_RING := preload("res://addons/kenney_particle_pack/circle_03.png")
const DASH_TRACE := preload("res://addons/kenney_particle_pack/trace_07.png")
const DUST := preload("res://addons/kenney_particle_pack/dirt_02.png")
const SLASH := preload("res://addons/kenney_particle_pack/slash_03.png")
const SPECIAL_STAR := preload("res://addons/kenney_particle_pack/magic_03.png")
const HEAL_STAR := preload("res://addons/kenney_particle_pack/magic_05.png")
const KO_SMOKE := preload("res://addons/kenney_particle_pack/smoke_04.png")

var _lifetime := 0.55


func configure(kind: String, direction: Vector2 = Vector2.RIGHT) -> void:
	var facing := direction.normalized() if direction.length_squared() > 0.001 else Vector2.RIGHT
	match kind:
		"hit":
			_add_flash(SPARK, Color(1.0, 0.72, 0.25), Vector2(0.85, 0.68), facing.angle(), 0.28)
			_add_flash(FLASH, Color(1.0, 0.96, 0.72), Vector2(0.62, 0.62), 0.0, 0.18)
			_add_particles(SPARK_SMALL, Color(1.0, 0.73, 0.3), 5, 90.0, 165.0, 0.26)
			_lifetime = 0.34
		"block":
			_add_flash(SHIELD_RING, Color(0.38, 0.86, 1.0), Vector2(0.72, 0.72), 0.0, 0.35)
			_add_flash(SPECIAL_STAR, Color(0.72, 0.98, 1.0), Vector2(0.58, 0.58), facing.angle(), 0.28)
			_add_particles(SPARK_SMALL, Color(0.45, 0.9, 1.0), 3, 65.0, 120.0, 0.22)
			_lifetime = 0.34
		"dash":
			_add_flash(DASH_TRACE, Color(0.52, 0.86, 1.0), Vector2(0.58, 1.15), facing.angle() - PI / 2.0, 0.34)
			_add_particles(DUST, Color(0.7, 0.78, 0.82), 3, 35.0, 60.0, 0.28)
			_lifetime = 0.38
		"charge":
			_add_flash(SPECIAL_STAR, Color(1.0, 0.34, 0.2), Vector2(0.68, 0.68), 0.0, 0.4)
			_add_flash(FLASH, Color(1.0, 0.83, 0.25), Vector2(0.50, 0.50), 0.0, 0.34)
			_lifetime = 0.38
		"special":
			_add_flash(SLASH, Color(1.0, 0.72, 0.2), Vector2(0.88, 0.88), facing.angle(), 0.34)
			_add_flash(SPARK, Color(1.0, 0.42, 0.16), Vector2(0.7, 0.7), facing.angle(), 0.32)
			_add_particles(SPARK_SMALL, Color(1.0, 0.78, 0.32), 6, 110.0, 190.0, 0.32)
			_lifetime = 0.40
		"heal":
			_add_flash(HEAL_STAR, Color(0.38, 1.0, 0.58), Vector2(0.62, 0.62), 0.0, 0.48)
			_add_particles(FLASH, Color(0.55, 1.0, 0.55), 3, 35.0, 65.0, 0.4)
			_lifetime = 0.46
		"land":
			_add_particles(DUST, Color(0.78, 0.76, 0.7), 4, 35.0, 90.0, 0.25)
			_lifetime = 0.32
		"ko":
			_add_flash(KO_SMOKE, Color(0.85, 0.88, 0.92), Vector2(0.78, 0.62), 0.0, 0.52)
			_add_particles(DUST, Color(0.82, 0.8, 0.75), 4, 40.0, 85.0, 0.34)
			_lifetime = 0.48
	_lifetime_timer()


func _add_flash(texture: Texture2D, tint: Color, final_scale: Vector2, rotation_value: float, duration: float) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	var subtle_tint := tint
	subtle_tint.a *= 0.78
	sprite.modulate = subtle_tint
	sprite.rotation = rotation_value
	sprite.scale = final_scale * 0.18
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(sprite, "scale", final_scale, duration * 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "modulate:a", 0.0, duration).set_delay(duration * 0.12)
	tween.tween_property(sprite, "rotation", rotation_value + 0.24, duration)


func _add_particles(texture: Texture2D, tint: Color, count: int, speed_min: float, speed_max: float, particle_lifetime: float) -> void:
	var particles := GPUParticles2D.new()
	particles.texture = texture
	particles.amount = count
	particles.lifetime = particle_lifetime
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0.0, -1.0, 0.0)
	process_material.spread = 180.0
	process_material.initial_velocity_min = speed_min
	process_material.initial_velocity_max = speed_max
	process_material.gravity = Vector3(0.0, 240.0, 0.0)
	process_material.scale_min = 0.18
	process_material.scale_max = 0.32
	var particle_tint := tint
	particle_tint.a *= 0.72
	process_material.color = particle_tint
	particles.process_material = process_material
	add_child(particles)
	particles.emitting = true


func _lifetime_timer() -> void:
	get_tree().create_timer(_lifetime).timeout.connect(queue_free)
