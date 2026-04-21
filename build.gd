extends Node2D

# --- SOUND THINGAMAJIG FIX ---
# Preloading ensures the songs are included in your exported game and won't lag.
# Make sure your files are named exactly "TNT.mp3" and "jump.mp3" in your folder.
var snd_jump = preload("res://jump.mp3") if FileAccess.file_exists("res://jump.mp3") else null
var snd_boom = preload("res://TNT.mp3") if FileAccess.file_exists("res://TNT.mp3") else null

# --- CONFIG ---
var explosion_timer := 5.0
var time_left := 5.0
var score := 0
var best_score := 0
var current_speed := 550.0
var gravity := 2600.0
var jump_force := -980.0
var wall_jump_push := 600.0 
var wall_slide_speed := 150.0 
var is_dead := false

# Invincibility Config
var invincibility_timer := 3.0
var wall_speed := 280.0
var wall_x := -800.0

const SAVE_PATH = "user://escape_ultimate_best.save"

# Nodes
var player: CharacterBody2D
var player_sprite: ColorRect
var timer_bar: ProgressBar
var score_label: Label
var camera: Camera2D
var wall_node: ColorRect
var last_platform_pos := Vector2(0, 500)

var sfx_explosion: AudioStreamPlayer
var sfx_jump: AudioStreamPlayer

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()

func _ready():
	load_best_score()
	RenderingServer.set_default_clear_color(Color(0.01, 0.0, 0.05))
	setup_audio() 
	setup_lighting()
	setup_ui()
	setup_player()
	setup_death_wall()
	
	spawn_platform(Vector2(0, 550), Vector2(2000, 100)) 
	for i in range(1, 40):
		spawn_checked_chunk()

func setup_audio():
	sfx_explosion = AudioStreamPlayer.new()
	sfx_explosion.stream = snd_boom
	add_child(sfx_explosion)
	
	sfx_jump = AudioStreamPlayer.new()
	sfx_jump.stream = snd_jump
	add_child(sfx_jump)

func setup_lighting():
	var env = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.glow_enabled = true
	env.environment.glow_bloom = 0.5
	add_child(env)

func setup_ui():
	var canvas = CanvasLayer.new()
	add_child(canvas)
	
	score_label = Label.new()
	update_score_text()
	score_label.position = Vector2(25, 20)
	score_label.add_theme_font_size_override("font_size", 22) 
	canvas.add_child(score_label)
	
	timer_bar = ProgressBar.new()
	timer_bar.size = Vector2(300, 10)
	timer_bar.position = Vector2(25, 85)
	timer_bar.show_percentage = false
	canvas.add_child(timer_bar)

func update_score_text():
	score_label.text = "STREAK: " + str(score) + " | BEST: " + str(best_score)

func setup_player():
	player = CharacterBody2D.new()
	player.name = "Player"
	player_sprite = ColorRect.new()
	player_sprite.size = Vector2(40, 40)
	player_sprite.pivot_offset = Vector2(20, 40)
	player_sprite.position = Vector2(-20, -40)
	player_sprite.color = Color(0, 10, 10) 
	player.add_child(player_sprite)
	
	var col = CollisionShape2D.new()
	col.shape = RectangleShape2D.new()
	col.shape.size = Vector2(36, 36)
	player.add_child(col)
	
	camera = Camera2D.new()
	camera.enabled = true
	camera.position_smoothing_enabled = true
	player.add_child(camera)
	
	add_child(player)
	player.position = Vector2(100, 450)

func setup_death_wall():
	wall_node = ColorRect.new()
	wall_node.size = Vector2(150, 6000) 
	wall_node.position = Vector2(wall_x, -3000)
	wall_node.color = Color(2, 0, 0)
	add_child(wall_node)
	
	for i in range(100):
		var spike = Polygon2D.new()
		spike.polygon = PackedVector2Array([Vector2(150, 0), Vector2(220, 30), Vector2(150, 60)])
		spike.position = Vector2(0, i * 60)
		spike.color = Color(5, 0, 0)
		wall_node.add_child(spike)

func _physics_process(delta):
	if is_dead:
		if Input.is_action_just_pressed("ui_accept"): 
			Engine.time_scale = 1.0
			get_tree().reload_current_scene()
		return

	if invincibility_timer > 0:
		invincibility_timer -= delta
		player_sprite.modulate.a = 0.5 if Engine.get_frames_drawn() % 10 < 5 else 1.0
	else:
		player_sprite.modulate.a = 1.0

	wall_x += (wall_speed + (score * 8)) * delta
	wall_node.position.x = wall_x
	
	if invincibility_timer <= 0 and player.global_position.x < wall_x + 150:
		die("CRUSHED BY THE WALL")

	time_left -= delta
	timer_bar.value = (time_left / explosion_timer) * 100
	if time_left <= 0: boom()

	var vel = player.velocity
	var move = Input.get_axis("ui_left", "ui_right")
	
	if not player.is_on_floor():
		if player.is_on_wall() and move != 0:
			vel.y = min(vel.y + gravity * delta, wall_slide_speed)
		else:
			vel.y += gravity * delta
		if abs(vel.y) > 100:
			player_sprite.scale = player_sprite.scale.lerp(Vector2(0.7, 1.4), 10 * delta)
	else:
		if abs(vel.x) < 15:
			player_sprite.scale = Vector2(1, 1)
		else:
			player_sprite.scale = player_sprite.scale.lerp(Vector2(1, 1), 15 * delta)
	
	if Input.is_action_just_pressed("ui_accept"):
		if player.is_on_floor():
			vel.y = jump_force
			player_sprite.scale = Vector2(1.5, 0.5)
			if sfx_jump.stream: sfx_jump.play()
		elif player.is_on_wall():
			vel.y = jump_force * 0.8
			vel.x = -player.get_wall_normal().x * wall_jump_push
			if sfx_jump.stream: sfx_jump.play()

	vel.x = lerp(vel.x, move * current_speed, 0.2)
	player.velocity = vel
	player.move_and_slide()

	if invincibility_timer <= 0:
		for tnt in get_tree().get_nodes_in_group("tnt"):
			if player.global_position.distance_to(tnt.global_position) < 80:
				die("TNT EXPLOSION")

	if player.position.y > 2000: die("THE VOID")

func boom():
	score += 1
	if score > best_score:
		best_score = score
		save_best_score()
	update_score_text()
	time_left = explosion_timer
	current_speed += 15
	wall_speed += 10 
	if sfx_explosion.stream: sfx_explosion.play()
	apply_shake(40.0)
	spawn_checked_chunk()

func spawn_checked_chunk():
	var dist = randf_range(380, 500)
	var pos = Vector2(last_platform_pos.x + dist, clamp(last_platform_pos.y + randf_range(-200, 200), 200, 850))
	var size = Vector2(randf_range(450, 700), 75)
	spawn_platform(pos, size)
	last_platform_pos = pos
	var hazard_pos = pos.x + (size.x/2 - 60) * (1 if randf() > 0.5 else -1)
	if randf() < 0.3: spawn_spike(Vector2(hazard_pos, pos.y - 65))
	elif randf() < 0.2: spawn_tnt(Vector2(hazard_pos, pos.y - 75))

func spawn_platform(pos, size):
	var plat = StaticBody2D.new()
	plat.position = pos
	plat.add_to_group("platforms")
	var v = ColorRect.new()
	v.size = size
	v.position = -size/2
	v.color = Color(randf()*2 + 0.5, 0.1, 0.2)
	plat.add_child(v)
	var c = CollisionShape2D.new()
	c.shape = RectangleShape2D.new()
	c.shape.size = size
	plat.add_child(c)
	add_child(plat)

func spawn_spike(pos):
	var spike = Area2D.new()
	spike.position = pos
	var poly = Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(-20, 20), Vector2(0, -20), Vector2(20, 20)])
	poly.color = Color(5, 5, 5)
	spike.add_child(poly)
	var col = CollisionShape2D.new()
	col.shape = RectangleShape2D.new()
	col.shape.size = Vector2(25, 25)
	spike.add_child(col)
	spike.body_entered.connect(func(b): if b.name == "Player" and invincibility_timer <= 0: die("SPIKED"))
	add_child(spike)

func spawn_tnt(pos):
	var tnt = Node2D.new()
	tnt.position = pos
	tnt.add_to_group("tnt")
	var v = ColorRect.new()
	v.size = Vector2(40, 40)
	v.position = Vector2(-20, -20)
	v.color = Color(1, 0, 0)
	tnt.add_child(v)
	add_child(tnt)

func apply_shake(amt):
	var t = create_tween()
	t.tween_property(camera, "offset", Vector2(randf_range(-amt, amt), randf_range(-amt, amt)), 0.05)
	t.tween_property(camera, "offset", Vector2.ZERO, 0.05)

# --- REWRITTEN DIE FUNCTION TO AVOID COMPILER ERRORS ---
func die(reason: String):
	if is_dead:
		return
	is_dead = true
	Engine.time_scale = 0.3
	if sfx_explosion.stream != null:
		sfx_explosion.play()
	if score > best_score:
		best_score = score
		save_best_score()
	var msg = reason + "\nSTREAK: " + str(score) + " | BEST: " + str(best_score) + "\n[SPACE] TO RESTART"
	score_label.set_text(msg)
	score_label.set_position(Vector2(100, 200))

func save_best_score():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_var(best_score)

func load_best_score():
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file:
			best_score = file.get_var()
