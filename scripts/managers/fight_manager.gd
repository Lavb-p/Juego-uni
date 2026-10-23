extends Node2D

const CAMERA_ZOOM := 1.0
const SAVE_PATH := "user://boxing_progress.json"

# The original campaign order and fighter scenes are preserved.
const CAMPAIGN_SCENES: Array[String] = [
	"res://Scenes/enemies/BasicEnemy.tscn",
	"res://Scenes/enemies/Boss1.tscn",
	"res://Scenes/enemies/BasicEnemy.tscn",
	"res://Scenes/enemies/Boss2.tscn"
]

const CAMPAIGN_NAMES: Array[String] = [
	"RIVAL",
	"VINCHITA",
	"RIVAL REMATCH",
	"CHICHO MEDINA"
]

const RED_COLOR := Color("#ff4657")
const GOLD_COLOR := Color("#f4cf72")
const TEXT_COLOR := Color("#f4f5f7")
const MUTED_COLOR := Color("#aab0bf")
const PANEL_COLOR := Color("#141821")
const BORDER_COLOR := Color("#454b5c")

var campaign_index := 0
var campaign_transition := false
var campaign_mode := true

var ring: Node2D
var camera: Camera2D
var player: Boxer
var enemy: Boxer

var player_start_position: Vector2
var enemy_start_position: Vector2

var round_number := 1
var total_rounds := 3
var rounds_to_win := 2
var player_rounds_won := 0
var enemy_rounds_won := 0

var round_duration := 60.0
var time_left := 60.0
var between_rounds := false
var break_time := 0.0
var fight_over := false

var player_health_bar: ProgressBar
var player_stamina_bar: ProgressBar
var enemy_health_bar: ProgressBar
var enemy_stamina_bar: ProgressBar

var info_label: Label
var score_label: Label
var result_label: Label
var restart_button: Button
var enemy_title_label: Label
var save_button: Button

var menu_overlay: Control
var opponent_option: OptionButton
var continue_button: Button
var saved_progress: Dictionary = {}
var announcement_id := 0
var save_feedback_id := 0
var _last_timer_tick := -1


func _ready() -> void:
	_setup_input()

	ring = get_node_or_null("Ring") as Node2D
	player = get_node_or_null("Boxer") as Boxer
	enemy = get_node_or_null("Enemy") as Boxer

	if ring == null:
		push_error("FightManager: Ring node was not found inside Main.")
		return
	if player == null:
		push_error("FightManager: Boxer node is missing or has no Boxer script.")
		return
	if enemy == null:
		push_error("FightManager: Enemy node is missing or has no Boxer script.")
		return
	if CAMPAIGN_SCENES.is_empty():
		push_error("FightManager: the campaign contains no fights.")
		return

	ring.z_index = -100
	player_start_position = player.position
	enemy_start_position = enemy.position

	_setup_fighters()
	_create_camera()
	_make_ui()
	_update_camera_position(0.0)
	_update_ui()

	saved_progress = _load_progress()
	_build_main_menu()
	get_tree().paused = true


func _process(delta: float) -> void:
	_update_camera_position(delta)

	if fight_over:
		return

	if between_rounds:
		break_time -= delta
		if is_instance_valid(info_label):
			if campaign_transition:
				info_label.text = "NEXT FIGHT  %02d" % ceili(maxf(0.0, break_time))
			else:
				info_label.text = "BREAK  %02d" % ceili(maxf(0.0, break_time))

		if break_time <= 0.0:
			if campaign_transition:
				_start_next_fight()
			else:
				_start_next_round()
		return

	time_left -= delta
	var timer_seconds := ceili(maxf(0.0, time_left))
	if timer_seconds > 0 and timer_seconds <= 10 and timer_seconds != _last_timer_tick:
		SoundManager.play_sfx("timer_tick", -13.0, 0.0)
		_last_timer_tick = timer_seconds

	if time_left <= 0.0:
		time_left = 0.0
		_finish_round_by_time()

	_update_ui()


# -------------------------------------------------------------------
# CAMERA
# -------------------------------------------------------------------

func _create_camera() -> void:
	var existing_camera := get_node_or_null("FightCamera")
	if existing_camera != null:
		existing_camera.queue_free()

	camera = Camera2D.new()
	camera.name = "FightCamera"
	add_child(camera)
	camera.enabled = true
	camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	camera.position_smoothing_enabled = false
	camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	camera.global_position = ring.global_position
	camera.make_current()


func _update_camera_position(_delta: float) -> void:
	if not is_instance_valid(camera) or not is_instance_valid(ring):
		return
	if not camera.is_inside_tree():
		return
	camera.global_position = ring.global_position

# -------------------------------------------------------------------
# INPUT
# -------------------------------------------------------------------

func _setup_input() -> void:
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("jump", KEY_W)
	_add_key_action("jump", KEY_UP)
	_add_key_action("crouch", KEY_S)
	_add_key_action("crouch", KEY_DOWN)
	_add_key_action("crouch_attack", KEY_U)
	_add_key_action("dash", KEY_SPACE)
	_add_key_action("jab", KEY_J)
	_add_key_action("cross", KEY_K)
	_add_key_action("upper", KEY_L)
	_add_key_action("block", KEY_I)


func _add_key_action(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	for existing_event in InputMap.action_get_events(action_name):
		if existing_event is InputEventKey and existing_event.physical_keycode == keycode:
			return

	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action_name, event)


# -------------------------------------------------------------------
# IN-GAME HUD
# -------------------------------------------------------------------

func _make_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "FightUI"
	layer.layer = 5
	add_child(layer)

	var hud := Control.new()
	hud.name = "HUD"
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)

	var player_title := _make_label(
		hud, "PLAYER", Vector2(28, 10), Vector2(300, 22), 15, GOLD_COLOR
	)
	player_title.add_theme_font_size_override("font_size", 15)

	_make_label(hud, "HEALTH", Vector2(29, 32), Vector2(90, 12), 9, MUTED_COLOR)
	player_health_bar = _bar(hud, Vector2(28, 44), 300, Color("#f04d5d"), 17)
	_make_label(hud, "STAMINA", Vector2(29, 64), Vector2(90, 12), 9, MUTED_COLOR)
	player_stamina_bar = _bar(hud, Vector2(28, 76), 300, Color("#54d6b0"), 13)

	enemy_title_label = _make_label(
		hud, CAMPAIGN_NAMES[campaign_index], Vector2(632, 10), Vector2(300, 22), 15, GOLD_COLOR
	)
	enemy_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_make_label(hud, "HEALTH", Vector2(842, 32), Vector2(90, 12), 9, MUTED_COLOR).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	enemy_health_bar = _bar(hud, Vector2(632, 44), 300, Color("#f04d5d"), 17)
	_make_label(hud, "STAMINA", Vector2(842, 64), Vector2(90, 12), 9, MUTED_COLOR).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	enemy_stamina_bar = _bar(hud, Vector2(632, 76), 300, Color("#54d6b0"), 13)

	var timer_panel := Panel.new()
	timer_panel.position = Vector2(382, 8)
	timer_panel.size = Vector2(196, 82)
	timer_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color("#171b25"), Color("#b94a52"), 2, 9)
	)
	hud.add_child(timer_panel)

	_make_label(
		hud, "PIXEL BOXING CLUB", Vector2(386, 12), Vector2(188, 15), 10, MUTED_COLOR
	).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label = _make_label(
		hud, "R1  •  01:00", Vector2(386, 28), Vector2(188, 29), 19, GOLD_COLOR
	)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label = _make_label(
		hud, "ROUNDS  0 - 0", Vector2(386, 59), Vector2(188, 20), 11, TEXT_COLOR
	)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	save_button = Button.new()
	save_button.text = "SAVE PROGRESS"
	save_button.position = Vector2(793, 100)
	save_button.size = Vector2(139, 29)
	save_button.add_theme_font_size_override("font_size", 11)
	_style_button(save_button, Color("#252c38"), Color("#5c6579"))
	save_button.pressed.connect(_save_progress.bind(true))
	hud.add_child(save_button)

	result_label = _make_label(
		hud, "", Vector2(190, 190), Vector2(580, 112), 30, RED_COLOR
	)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.add_theme_color_override("font_shadow_color", Color("#08090d"))
	result_label.add_theme_constant_override("shadow_offset_x", 2)
	result_label.add_theme_constant_override("shadow_offset_y", 2)

	restart_button = Button.new()
	restart_button.text = "MAIN MENU"
	restart_button.position = Vector2(390, 318)
	restart_button.size = Vector2(180, 40)
	restart_button.visible = false
	restart_button.add_theme_font_size_override("font_size", 14)
	_style_button(restart_button, Color("#a83240"), Color("#f06b76"))
	restart_button.pressed.connect(_show_main_menu)
	hud.add_child(restart_button)

	var controls_panel := PanelContainer.new()
	controls_panel.position = Vector2(24, 472)
	controls_panel.size = Vector2(912, 54)
	controls_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color("#121620"), Color("#454b5c"), 1, 7)
	)
	hud.add_child(controls_panel)

	var controls_margin := MarginContainer.new()
	controls_margin.add_theme_constant_override("margin_left", 7)
	controls_margin.add_theme_constant_override("margin_right", 7)
	controls_margin.add_theme_constant_override("margin_top", 5)
	controls_margin.add_theme_constant_override("margin_bottom", 5)
	controls_panel.add_child(controls_margin)

	var controls_row := HBoxContainer.new()
	controls_row.add_theme_constant_override("separation", 7)
	controls_margin.add_child(controls_row)
	_make_control_chip(controls_row, "A / D  MOVE")
	_make_control_chip(controls_row, "W  JUMP")
	_make_control_chip(controls_row, "S  CROUCH")
	_make_control_chip(controls_row, "SPACE  DASH")
	_make_control_chip(controls_row, "J  JAB")
	_make_control_chip(controls_row, "K  CROSS")
	_make_control_chip(controls_row, "L  UPPERCUT")
	_make_control_chip(controls_row, "U  LOW HIT")
	_make_control_chip(controls_row, "I  BLOCK")


func _make_label(
	parent: Control,
	text_value: String,
	position_value: Vector2,
	size_value: Vector2,
	font_size: int,
	font_color: Color
) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = position_value
	label.size = size_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	parent.add_child(label)
	return label


func _bar(
	parent: Control,
	pos: Vector2,
	bar_width: float,
	color: Color,
	bar_height: float
) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = pos
	bar.size = Vector2(bar_width, bar_height)
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.show_percentage = true
	bar.add_theme_font_size_override("font_size", 10)
	bar.add_theme_color_override("font_color", Color("#ffffff"))
	bar.add_theme_stylebox_override("fill", _panel_style(color, color.lightened(0.12), 1, 5))
	bar.add_theme_stylebox_override("background", _panel_style(Color("#282d38"), Color("#555c6b"), 1, 5))
	parent.add_child(bar)
	return bar


func _make_control_chip(parent: HBoxContainer, caption: String) -> void:
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.custom_minimum_size = Vector2(0, 32)
	chip.add_theme_stylebox_override(
		"panel", _panel_style(Color("#242a36"), Color("#555d70"), 1, 5)
	)
	parent.add_child(chip)

	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	chip.add_child(label)


func _panel_style(
	background_color: Color,
	border_color: Color,
	border_width: int = 1,
	corner_radius: int = 6
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = 7.0
	style.content_margin_right = 7.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _style_button(button: Button, background: Color, border: Color) -> void:
	button.add_theme_stylebox_override("normal", _panel_style(background, border, 1, 6))
	button.add_theme_stylebox_override("hover", _panel_style(background.lightened(0.12), border.lightened(0.12), 1, 6))
	button.add_theme_stylebox_override("pressed", _panel_style(background.darkened(0.12), border, 1, 6))
	button.add_theme_stylebox_override("disabled", _panel_style(Color("#222630"), Color("#363b48"), 1, 6))
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", Color("#ffffff"))
	button.add_theme_color_override("font_pressed_color", GOLD_COLOR)
	button.add_theme_color_override("font_disabled_color", MUTED_COLOR)
	button.pressed.connect(_play_ui_click)
	button.mouse_entered.connect(_play_ui_hover)


func _play_ui_click() -> void:
	SoundManager.play_sfx("ui_click", -5.0, 0.025)


func _play_ui_hover() -> void:
	SoundManager.play_sfx("ui_hover", -12.0, 0.01)


func _on_opponent_selected(_index: int) -> void:
	SoundManager.play_sfx("ui_click", -6.0, 0.02)


# -------------------------------------------------------------------
# MAIN MENU
# -------------------------------------------------------------------

func _build_main_menu() -> void:
	var menu_layer := CanvasLayer.new()
	menu_layer.name = "MainMenuLayer"
	menu_layer.layer = 20
	menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(menu_layer)

	menu_overlay = Control.new()
	menu_overlay.name = "MainMenuOverlay"
	menu_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_layer.add_child(menu_overlay)

	var background := ColorRect.new()
	background.color = Color(0.035, 0.045, 0.065, 0.96)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_overlay.add_child(background)

	var decorative_line := ColorRect.new()
	decorative_line.color = Color("#a83240")
	decorative_line.position = Vector2(0, 0)
	decorative_line.size = Vector2(960, 5)
	menu_overlay.add_child(decorative_line)

	var menu_panel := PanelContainer.new()
	menu_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu_panel.offset_left = -270
	menu_panel.offset_right = 270
	menu_panel.offset_top = -226
	menu_panel.offset_bottom = 226
	menu_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color("#171b25"), Color("#a83b48"), 2, 10)
	)
	menu_overlay.add_child(menu_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 17)
	margin.add_theme_constant_override("margin_bottom", 17)
	menu_panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)

	var title := Label.new()
	title.text = "PIXEL BOXING CLUB"
	title.custom_minimum_size = Vector2(0, 42)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", GOLD_COLOR)
	title.add_theme_color_override("font_outline_color", Color("#612530"))
	title.add_theme_constant_override("outline_size", 2)
	layout.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Step into the ring. Choose your next challenge."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", MUTED_COLOR)
	layout.add_child(subtitle)

	var separator := HSeparator.new()
	layout.add_child(separator)

	var choose_label := Label.new()
	choose_label.text = "CHOOSE YOUR FIGHT"
	choose_label.add_theme_font_size_override("font_size", 12)
	choose_label.add_theme_color_override("font_color", GOLD_COLOR)
	layout.add_child(choose_label)

	opponent_option = OptionButton.new()
	opponent_option.custom_minimum_size = Vector2(0, 39)
	opponent_option.add_item("Campaign  —  all four fights", 0)
	opponent_option.add_item("Rival  —  exhibition fight", 1)
	opponent_option.add_item("Vinchita  —  healing boss", 2)
	opponent_option.add_item("Chicho Medina  —  final boss", 3)
	opponent_option.select(0)
	opponent_option.item_selected.connect(_on_opponent_selected)
	opponent_option.add_theme_font_size_override("font_size", 14)
	opponent_option.add_theme_color_override("font_color", TEXT_COLOR)
	opponent_option.add_theme_stylebox_override("normal", _panel_style(Color("#222734"), Color("#555d70"), 1, 6))
	layout.add_child(opponent_option)

	var start_button := Button.new()
	start_button.text = "START FIGHT"
	start_button.custom_minimum_size = Vector2(0, 41)
	start_button.add_theme_font_size_override("font_size", 15)
	_style_button(start_button, Color("#a83240"), Color("#f06b76"))
	start_button.pressed.connect(_start_selected_challenge)
	layout.add_child(start_button)

	continue_button = Button.new()
	continue_button.text = "CONTINUE SAVED PROGRESS"
	continue_button.custom_minimum_size = Vector2(0, 38)
	continue_button.add_theme_font_size_override("font_size", 13)
	_style_button(continue_button, Color("#283b42"), Color("#4b9d92"))
	continue_button.pressed.connect(_resume_saved_progress)
	layout.add_child(continue_button)

	var controls_title := Label.new()
	controls_title.text = "CONTROLS"
	controls_title.add_theme_font_size_override("font_size", 11)
	controls_title.add_theme_color_override("font_color", GOLD_COLOR)
	layout.add_child(controls_title)

	var controls_copy := Label.new()
	controls_copy.text = "A / D Move     W / ↑ Jump     S / ↓ Crouch     SPACE Dash\nJ Jab     K Cross     L Uppercut     U Crouch Hit     I Block"
	controls_copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_copy.add_theme_font_size_override("font_size", 12)
	controls_copy.add_theme_color_override("font_color", TEXT_COLOR)
	controls_copy.add_theme_color_override("font_shadow_color", Color("#07080b"))
	layout.add_child(controls_copy)

	var footer := Label.new()
	footer.text = "Your progress is saved on this computer."
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 10)
	footer.add_theme_color_override("font_color", MUTED_COLOR)
	layout.add_child(footer)

	_refresh_continue_button()
	menu_overlay.visible = true


func _show_main_menu() -> void:
	SoundManager.set_crowd_enabled(false)
	if is_instance_valid(menu_overlay):
		menu_overlay.visible = true
	if is_instance_valid(restart_button):
		restart_button.visible = false
	saved_progress = _load_progress()
	_refresh_continue_button()
	get_tree().paused = true


func _refresh_continue_button() -> void:
	if is_instance_valid(continue_button):
		continue_button.disabled = saved_progress.is_empty()


func _start_selected_challenge() -> void:
	var selected := opponent_option.selected
	campaign_mode = selected == 0
	match selected:
		0:
			campaign_index = 0
		1:
			campaign_index = 0
		2:
			campaign_index = 1
		3:
			campaign_index = 3
		_:
			campaign_index = 0

	if not _replace_enemy(CAMPAIGN_SCENES[campaign_index]):
		return

	round_number = 1
	player_rounds_won = 0
	enemy_rounds_won = 0
	time_left = round_duration
	between_rounds = false
	campaign_transition = false
	break_time = 0.0
	fight_over = false
	player.reset_for_round()
	enemy.reset_for_round()
	player.position = player_start_position
	enemy.position = enemy_start_position
	result_label.text = ""
	restart_button.visible = false
	menu_overlay.visible = false
	get_tree().paused = false
	SoundManager.set_crowd_enabled(true)
	SoundManager.play_sfx("round_bell", -1.0, 0.0)
	_last_timer_tick = -1
	_update_camera_position(0.0)
	_update_ui()
	_show_announcement("FIGHT %d\n%s" % [campaign_index + 1, CAMPAIGN_NAMES[campaign_index]], 1.8)
	_save_progress(false)


func _resume_saved_progress() -> void:
	saved_progress = _load_progress()
	if saved_progress.is_empty():
		_refresh_continue_button()
		return

	campaign_mode = bool(saved_progress.get("campaign_mode", true))
	campaign_index = clampi(
		int(saved_progress.get("campaign_index", 0)), 0, CAMPAIGN_SCENES.size() - 1
	)
	if not _replace_enemy(CAMPAIGN_SCENES[campaign_index]):
		return

	round_number = clampi(int(saved_progress.get("round_number", 1)), 1, total_rounds)
	player_rounds_won = clampi(int(saved_progress.get("player_rounds_won", 0)), 0, rounds_to_win - 1)
	enemy_rounds_won = clampi(int(saved_progress.get("enemy_rounds_won", 0)), 0, rounds_to_win - 1)
	time_left = clampf(float(saved_progress.get("time_left", round_duration)), 0.1, round_duration)

	player.reset_for_round()
	enemy.reset_for_round()
	player.health = clampf(float(saved_progress.get("player_health", player.max_health)), 0.1, player.max_health)
	player.stamina = clampf(float(saved_progress.get("player_stamina", player.max_stamina)), 0.0, player.max_stamina)
	enemy.health = clampf(float(saved_progress.get("enemy_health", enemy.max_health)), 0.1, enemy.max_health)
	enemy.stamina = clampf(float(saved_progress.get("enemy_stamina", enemy.max_stamina)), 0.0, enemy.max_stamina)
	player.position = player_start_position
	enemy.position = enemy_start_position
	between_rounds = false
	campaign_transition = false
	break_time = 0.0
	fight_over = false
	result_label.text = ""
	restart_button.visible = false
	menu_overlay.visible = false
	get_tree().paused = false
	SoundManager.set_crowd_enabled(true)
	SoundManager.play_sfx("round_bell", -1.0, 0.0)
	_last_timer_tick = -1
	_update_camera_position(0.0)
	_update_ui()
	_show_announcement("PROGRESS RESTORED", 1.5)


func _replace_enemy(scene_path: String) -> bool:
	if is_instance_valid(enemy):
		if enemy.knocked_out.is_connected(_on_knockout):
			enemy.knocked_out.disconnect(_on_knockout)
		if enemy.stats_changed.is_connected(_on_stats_changed):
			enemy.stats_changed.disconnect(_on_stats_changed)
		if is_instance_valid(player) and player.opponent == enemy:
			player.opponent = null
		remove_child(enemy)
		enemy.queue_free()

	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("FightManager: could not load opponent scene: " + scene_path)
		return false

	var new_enemy := packed_scene.instantiate() as Boxer
	if new_enemy == null:
		push_error("FightManager: the opponent scene root does not use the Boxer script.")
		return false

	new_enemy.name = "Enemy"
	new_enemy.position = enemy_start_position
	add_child(new_enemy)
	enemy = new_enemy
	_setup_fighters()
	return true


# -------------------------------------------------------------------
# FIGHTERS / HUD UPDATES
# -------------------------------------------------------------------

func _setup_fighters() -> void:
	player.is_player = true
	player.boxer_name = "PLAYER"
	enemy.is_player = false
	enemy.boxer_name = CAMPAIGN_NAMES[campaign_index]
	player.opponent = enemy
	enemy.opponent = player

	if not player.knocked_out.is_connected(_on_knockout):
		player.knocked_out.connect(_on_knockout)
	if not enemy.knocked_out.is_connected(_on_knockout):
		enemy.knocked_out.connect(_on_knockout)
	if not player.stats_changed.is_connected(_on_stats_changed):
		player.stats_changed.connect(_on_stats_changed)


func _on_stats_changed(_boxer: Boxer) -> void:
	_update_ui()


func _update_ui() -> void:
	if not is_instance_valid(player) or not is_instance_valid(enemy):
		return

	if is_instance_valid(player_health_bar):
		player_health_bar.max_value = player.max_health
		player_health_bar.value = player.health
	if is_instance_valid(player_stamina_bar):
		player_stamina_bar.max_value = player.max_stamina
		player_stamina_bar.value = player.stamina
	if is_instance_valid(enemy_health_bar):
		enemy_health_bar.max_value = enemy.max_health
		enemy_health_bar.value = enemy.health
	if is_instance_valid(enemy_stamina_bar):
		enemy_stamina_bar.max_value = enemy.max_stamina
		enemy_stamina_bar.value = enemy.stamina

	if is_instance_valid(score_label):
		score_label.text = "ROUNDS  %d - %d" % [player_rounds_won, enemy_rounds_won]
	if is_instance_valid(enemy_title_label):
		enemy_title_label.text = CAMPAIGN_NAMES[campaign_index]
	if is_instance_valid(info_label) and not fight_over and not between_rounds:
		var seconds_left := maxi(0, ceili(time_left))
		info_label.text = "R%d  •  %02d:%02d" % [round_number, int(seconds_left / 60), seconds_left % 60]
		info_label.add_theme_color_override(
			"font_color", RED_COLOR if seconds_left <= 10 else GOLD_COLOR
		)
	if is_instance_valid(save_button):
		save_button.disabled = fight_over or between_rounds


# -------------------------------------------------------------------
# ROUND FLOW — THE ORIGINAL COMBAT RULES ARE KEPT
# -------------------------------------------------------------------

func _on_knockout(boxer: Boxer) -> void:
	if fight_over or between_rounds:
		return
	if boxer == enemy:
		_complete_round("player")
	else:
		_complete_round("enemy")


func _finish_round_by_time() -> void:
	if fight_over or between_rounds:
		return
	if player.health > enemy.health:
		_complete_round("player")
	elif enemy.health > player.health:
		_complete_round("enemy")
	else:
		_complete_round("draw")


func _complete_round(winner: String) -> void:
	if fight_over or between_rounds:
		return

	SoundManager.play_sfx("round_end", -1.5, 0.02)
	if winner == "player":
		player_rounds_won += 1
		_show_announcement("PLAYER WINS THE ROUND!", 2.0)
	elif winner == "enemy":
		enemy_rounds_won += 1
		_show_announcement("OPPONENT WINS THE ROUND!", 2.0)
	else:
		_show_announcement("ROUND DRAW", 2.0)

	_update_ui()
	if player_rounds_won >= rounds_to_win:
		_finish_match("player")
		return
	if enemy_rounds_won >= rounds_to_win:
		_finish_match("enemy")
		return
	if round_number >= total_rounds:
		if player_rounds_won > enemy_rounds_won:
			_finish_match("player")
		elif enemy_rounds_won > player_rounds_won:
			_finish_match("enemy")
		else:
			_finish_match("draw")
		return

	between_rounds = true
	campaign_transition = false
	break_time = 3.0
	info_label.text = "BETWEEN ROUNDS"


func _finish_match(winner: String) -> void:
	between_rounds = false
	campaign_transition = false

	if winner == "player":
		if campaign_mode and campaign_index < CAMPAIGN_SCENES.size() - 1:
			between_rounds = true
			campaign_transition = true
			break_time = 3.0
			SoundManager.play_sfx("victory", -4.0, 0.0)
			_show_announcement("FIGHT WON!\nA NEW CHALLENGER APPROACHES", 2.0)
			info_label.text = "NEXT FIGHT  03"
			_update_ui()
			return

		fight_over = true
		announcement_id += 1
		if campaign_mode:
			result_label.text = "YOU ARE THE CHAMPION!\nYOU WON EVERY FIGHT!"
		else:
			result_label.text = "VICTORY!\nYOU DEFEATED %s" % CAMPAIGN_NAMES[campaign_index]
	elif winner == "enemy":
		fight_over = true
		announcement_id += 1
		result_label.text = "DEFEAT\nROUND SCORE: %d - %d" % [player_rounds_won, enemy_rounds_won]
	else:
		fight_over = true
		announcement_id += 1
		result_label.text = "DRAW\nROUND SCORE: %d - %d" % [player_rounds_won, enemy_rounds_won]

	SoundManager.set_crowd_enabled(false)
	if winner == "player":
		SoundManager.play_sfx("victory", -0.5, 0.0)
	elif winner == "enemy":
		SoundManager.play_sfx("defeat", -0.5, 0.0)
	else:
		SoundManager.play_sfx("draw", -1.0, 0.0)

	info_label.text = "CAMPAIGN COMPLETE" if winner == "player" and campaign_mode else "FIGHT COMPLETE"
	restart_button.visible = true
	_update_ui()


func _start_next_fight() -> void:
	if not campaign_mode or campaign_index >= CAMPAIGN_SCENES.size() - 1:
		return

	between_rounds = false
	campaign_transition = false
	break_time = 0.0
	campaign_index += 1
	if not _replace_enemy(CAMPAIGN_SCENES[campaign_index]):
		fight_over = true
		return

	round_number = 1
	player_rounds_won = 0
	enemy_rounds_won = 0
	time_left = round_duration
	fight_over = false
	between_rounds = false
	campaign_transition = false
	player.reset_for_round()
	enemy.reset_for_round()
	player.position = player_start_position
	enemy.position = enemy_start_position
	restart_button.visible = false
	result_label.text = ""
	_show_announcement("NEXT CHALLENGER\n%s" % CAMPAIGN_NAMES[campaign_index], 2.0)
	_update_camera_position(0.0)
	_update_ui()
	_save_progress(false)
	_last_timer_tick = -1
	SoundManager.play_sfx("round_bell", -1.0, 0.0)


func _start_next_round() -> void:
	round_number += 1
	time_left = round_duration
	between_rounds = false
	campaign_transition = false
	break_time = 0.0
	player.reset_for_round()
	enemy.reset_for_round()
	player.position = player_start_position
	enemy.position = enemy_start_position
	result_label.text = ""
	_update_camera_position(0.0)
	_update_ui()
	_save_progress(false)
	_last_timer_tick = -1
	SoundManager.play_sfx("round_bell", -1.0, 0.0)


func _show_announcement(message: String, duration: float = 2.0) -> void:
	if not is_instance_valid(result_label):
		return

	announcement_id += 1
	var current_announcement := announcement_id
	result_label.text = message
	result_label.add_theme_color_override("font_color", RED_COLOR)
	get_tree().create_timer(duration).timeout.connect(
		func() -> void:
			if not is_instance_valid(result_label):
				return
			if current_announcement == announcement_id and not fight_over:
				result_label.text = ""
	)


# -------------------------------------------------------------------
# SAVE / LOAD
# -------------------------------------------------------------------

func _save_progress(show_feedback: bool = true) -> void:
	if fight_over or between_rounds or not is_instance_valid(player) or not is_instance_valid(enemy):
		if show_feedback and is_instance_valid(save_button):
			save_button.text = "SAVE UNAVAILABLE"
			SoundManager.play_sfx("ui_error", -5.0, 0.0)
		return

	var data: Dictionary = {
		"campaign_mode": campaign_mode,
		"campaign_index": campaign_index,
		"round_number": round_number,
		"player_rounds_won": player_rounds_won,
		"enemy_rounds_won": enemy_rounds_won,
		"time_left": time_left,
		"player_health": player.health,
		"player_stamina": player.stamina,
		"enemy_health": enemy.health,
		"enemy_stamina": enemy.stamina
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not save progress to the user data folder.")
		if show_feedback and is_instance_valid(save_button):
			save_button.text = "SAVE FAILED"
			SoundManager.play_sfx("ui_error", -3.0, 0.0)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	if show_feedback and is_instance_valid(save_button):
		save_button.text = "SAVED!"
		SoundManager.play_sfx("save_success", -2.0, 0.0)
		save_feedback_id += 1
		var current_feedback := save_feedback_id
		get_tree().create_timer(1.5).timeout.connect(
			func() -> void:
				if is_instance_valid(save_button) and current_feedback == save_feedback_id:
					save_button.text = "SAVE PROGRESS"
		)

	saved_progress = data
	_refresh_continue_button()


func _load_progress() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed
	return {}
