extends Node2D

# --- SOUNDS ---
var snd_jump = preload("res://jump.mp3") if FileAccess.file_exists("res://jump.mp3") else null

# --- CONFIG ---
var current_speed := 750.0
var gravity := 3100.0
var jump_force := -1100.0
var wall_jump_push := 800.0
var wall_slide_speed := 250.0

var score := 0
var best_score := 0
var is_dead := false
var invincibility_timer := 3.0

# Wall Config
var wall_x := -1200.0
var wall_speed := 350.0

const SAVE_PATH = "user://escape_ultimate_best.save"

# Nodes
var player: CharacterBody2D
var player_sprite: ColorRect
var score_label: Label
var canvas: CanvasLayer
var camera: Camera2D
var wall_node: ColorRect
var last_platform_pos := Vector2(0, 550)

var sfx_jump: AudioStreamPlayer

func _ready():
	Engine.time_scale = 1.0
	load_best_score()
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.05))
	
	setup_ui()
	setup_audio()
	setup_player()
	setup_death_wall()
	
	# Initial Floor
	spawn_platform(Vector2(0, 600), Vector2(2000, 100), false)
	
	for i in range(30):
		spawn_next_chunk()

func setup_audio():
	sfx_jump = AudioStreamPlayer.new()
	sfx_jump.stream = snd_jump
	add_child(sfx_jump)

func setup_ui():
	canvas = CanvasLayer.new()
	add_child(canvas)
	
	score_label = Label.new()
	score_label.size = Vector2(1152, 648) # Match standard window size
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_label.add_theme_font_size_override("font_size", 40)
	canvas.add_child(score_label)
	update_score_text()

func update_score_text():
	if not is_dead:
		score_label.text = "STREAK: " + str(score) + " | BEST: " + str(best_score)
		score_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP # Move to top while playing

func setup_player():
	player = CharacterBody2D.new()
	player_sprite = ColorRect.new()
	player_sprite.size = Vector2(40, 40)
	player_sprite.position = Vector2(-20, -40)
	player_sprite.color = Color(0, 8, 10) 
	player.add_child(player_sprite)
	
	var col = CollisionShape2D.new()
	col.shape = RectangleShape2D.new()
	col.shape.size = Vector2(38, 38)
	player.add_child(col)
	
	camera = Camera2D.new()
	camera.enabled = true
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 12.0
	player.add_child(camera)
	
	add_child(player)
	player.position = Vector2(200, 400)

func setup_death_wall():
	wall_node = ColorRect.new()
	wall_node.size = Vector2(250, 4000)
	wall_node.position = Vector2(wall_x, -2000)
	wall_node.color = Color(4, 0, 0)
	add_child(wall_node)
	
	for i in range(80):
		var s = Polygon2D.new()
		s.polygon = PackedVector2Array([Vector2(250, 0), Vector2(320, 25), Vector2(250, 50)])
		s.position = Vector2(0, i * 50)
		s.color = Color(5, 0, 0)
		wall_node.add_child(s)

func _physics_process(delta):
	if is_dead:
		if Input.is_action_just_pressed("ui_accept"):
			get_tree().reload_current_scene()
		return

	if invincibility_timer > 0:
		invincibility_timer -= delta
		player_sprite.modulate.a = 0.5 if Engine.get_frames_drawn() % 10 < 5 else 1.0
	else:
		player_sprite.modulate.a = 1.0

	var vel = player.velocity
	var move = Input.get_axis("ui_left", "ui_right")
	
	if not player.is_on_floor():
		if player.is_on_wall() and move != 0:
			vel.y = min(vel.y + (gravity * 0.5) * delta, wall_slide_speed)
		else:
			vel.y += gravity * delta
	
	if Input.is_action_just_pressed("ui_accept"):
		if player.is_on_floor():
			vel.y = jump_force
			if sfx_jump.stream: sfx_jump.play()
		elif player.is_on_wall():
			vel.y = jump_force * 0.9
			vel.x = -player.get_wall_normal().x * wall_jump_push
			if sfx_jump.stream: sfx_jump.play()

	if move != 0:
		vel.x = lerp(vel.x, move * current_speed, 0.2)
	else:
		vel.x = lerp(vel.x, 0.0, 0.15)
		
	player.velocity = vel
	player.move_and_slide()

	if player.position.x > score * 150:
		score = int(player.position.x / 150)
		update_score_text()
		spawn_next_chunk()

	wall_x += (wall_speed + (score * 3)) * delta
	wall_node.position.x = wall_x
	
	if invincibility_timer <= 0:
		if player.global_position.x < wall_x + 250:
			die("CRUSHED BY SPIKE WALL")
		if player.position.y > 1800:
			die("VOID CONSUMED YOU")

func spawn_next_chunk():
	var gap = randf_range(300, 500)
	var height = clamp(last_platform_pos.y + randf_range(-180, 180), 200, 900)
	var pos = Vector2(last_platform_pos.x + gap, height)
	var size = Vector2(randf_range(350, 700), 70)
	
	var plat = spawn_platform(pos, size, true)
	
	# Add spikes TO the platform (they become children)
	if randf() > 0.4:
		# Local position relative to the platform center (0,0)
		var spike_lx = randf_range(-size.x/2 + 40, size.x/2 - 40)
		spawn_spike(plat, Vector2(spike_lx, -35))
			
	last_platform_pos = pos

func spawn_platform(pos, size, can_disintegrate) -> StaticBody2D:
	var plat = StaticBody2D.new()
	plat.position = pos
	
	var rect = ColorRect.new()
	rect.size = size
	rect.position = -size/2
	rect.color = Color(0.1, 0.4, 0.8)
	plat.add_child(rect)
	
	var col = CollisionShape2D.new()
	col.shape = RectangleShape2D.new()
	col.shape.size = size
	plat.add_child(col)
	
	add_child(plat)
	
	if can_disintegrate:
		check_touch(plat, rect)
	return plat

func check_touch(body, visual):
	while true:
		if not is_instance_valid(body) or is_dead: break
		await get_tree().process_frame
		if player.is_on_floor() and player.get_last_slide_collision():
			if player.get_last_slide_collision().get_collider() == body:
				var t = create_tween()
				# Platform and ALL children (spikes) will fade
				t.tween_property(body, "modulate", Color(1, 0, 0, 0), 0.6)
				t.parallel().tween_property(visual, "scale:y", 0.0, 0.6)
				await t.finished
				body.queue_free()
				break

func spawn_spike(parent_node, local_pos):
	var spike = Area2D.new()
	spike.position = local_pos
	
	var poly = Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(-25, 35), Vector2(0, -15), Vector2(25, 35)])
	poly.color = Color(10, 10, 10)
	spike.add_child(poly)
	
	var col = CollisionShape2D.new()
	col.shape = RectangleShape2D.new()
	col.shape.size = Vector2(30, 30)
	spike.add_child(col)
	
	spike.body_entered.connect(func(b): if b == player and invincibility_timer <= 0: die("IMPALED"))
	parent_node.add_child(spike) # Attached to platform!

func die(reason: String):
	if is_dead: return
	is_dead = true
	Engine.time_scale = 0.4
	
	if score > best_score:
		best_score = score
		save_best_score()
	
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_label.text = reason + "\nSTREAK: " + str(score) + " | BEST: " + str(best_score) + "\n[SPACE] TO RESTART"

func save_best_score():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file: file.store_var(best_score)

func load_best_score():
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file: best_score = file.get_var()
