
extends Node2D

@onready var sparks: GPUParticles2D = $Sparks


func _ready() -> void:
	sparks.emitting = true
	await sparks.finished
	queue_free()
