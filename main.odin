package main

import "core:fmt"
import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

SCREEN_WIDTH :: 1024
SCREEN_HEIGHT :: 768
GAME_OVER := false
POINTS := 0
LIVES := 3
ASTEROID_NUMBER := 4
START_TIME := rl.GetTime()

main :: proc() {
	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Asteroids")
	defer rl.CloseWindow()

	sound: Sound
	init_audio(&sound)
	defer deinit_audio(&sound)

	rl.SetTargetFPS(60)

	player: Space_Ship
	spawn_space_ship(&player)

	projectile_list := make([dynamic]Projectile)
	defer delete(projectile_list)
	asteroid_list := make([dynamic]Asteroid)
	defer delete(asteroid_list)
	alien_projectile_list := make([dynamic]Projectile)
	defer delete(alien_projectile_list)
	particle_list := make([dynamic]Particle)
	defer delete(particle_list)

	generate_asteroids(&asteroid_list)
	alien: Alien
	init_alien(&alien, .big)

	for !rl.WindowShouldClose() {
		update_game(
			&player,
			&projectile_list,
			&asteroid_list,
			&alien,
			&alien_projectile_list,
			&particle_list,
			&sound,
		)
		draw_game(
			&player,
			&projectile_list,
			&asteroid_list,
			&alien,
			&alien_projectile_list,
			&particle_list,
		)
		free_all(context.temp_allocator)
	}
}

handle_game_over :: proc(
	player: ^Space_Ship,
	projectile_list: ^[dynamic]Projectile,
	asteroid_list: ^[dynamic]Asteroid,
	alien: ^Alien,
	alien_projectile_list: ^[dynamic]Projectile,
) {
	font_size: i32 = 50
	text: cstring = "Game Over"
	horizontal_center := rl.GetScreenWidth() / 2 - rl.MeasureText(text, font_size) / 2
	vertical_center := rl.GetScreenHeight() / 2 - font_size / 2
	rl.DrawText(text, horizontal_center, vertical_center, font_size, rl.WHITE)
	points_reached_text := fmt.ctprintf("Points: %d", POINTS)
	rl.DrawText(
		points_reached_text,
		horizontal_center,
		vertical_center + font_size,
		font_size,
		rl.WHITE,
	)

	if rl.GetTime() - player.death_time > 3.0 {
		clear(projectile_list)
		clear(asteroid_list)
		clear(alien_projectile_list)
		spawn_space_ship(player)
		ASTEROID_NUMBER = 4
		generate_asteroids(asteroid_list)
		despawn_alien(alien)
		POINTS = 0
		LIVES = 3
		GAME_OVER = false
	}
}

update_game :: proc(
	player: ^Space_Ship,
	projectile_list: ^[dynamic]Projectile,
	asteroid_list: ^[dynamic]Asteroid,
	alien: ^Alien,
	alien_projectile_list: ^[dynamic]Projectile,
	particle_list: ^[dynamic]Particle,
	sound: ^Sound,
) {
	if len(asteroid_list) == 0 && !alien.alive {
		generate_asteroids(asteroid_list)
	}

	handle_out_of_screen(player)
	handle_out_of_screen_alien(alien)

	update_space_ship(player)
	update_projectile_positions(projectile_list, 10)
	despawn_projectiles(projectile_list)
	update_asteroids(
		asteroid_list,
		projectile_list,
		alien_projectile_list,
		alien,
		particle_list,
		&sound.explosion,
	)
	update_alien(alien, &sound.alien_alarm)
	spawn_alien_projectile(alien, player, alien_projectile_list, &sound.projectile)
	update_alien_projectile_positions(alien_projectile_list, 10)
	despawn_projectiles(alien_projectile_list)
	update_particles(particle_list)

	if !GAME_OVER do check_space_ship_collision(player, asteroid_list, alien, alien_projectile_list, particle_list, &sound.explosion)
	check_alien_collision(alien, player, asteroid_list, particle_list, &sound.explosion)

	if !GAME_OVER && !player.inactive {
		if rl.IsKeyDown(.LEFT) {
			player.angle -= rl.DEG2RAD * 5
		}
		if rl.IsKeyDown(.RIGHT) {
			player.angle += rl.DEG2RAD * 5
		}
		if rl.IsKeyDown(.UP) {
			player.velocity += player.direction * 0.5
			draw_thrust_for_space_ship(player)
			if !rl.IsSoundPlaying(sound.thrust) do rl.PlaySound(sound.thrust)
		}
		if rl.IsKeyPressed(.SPACE) {
			rl.PlaySound(sound.projectile)
			spawn_projectile(player, projectile_list)
		}
	}
	if rl.IsKeyReleased(.UP) || player.inactive || GAME_OVER {
		if rl.IsSoundPlaying(sound.thrust) do rl.StopSound(sound.thrust)
	}

	play_background_heartbeat(sound)

	if GAME_OVER {
		handle_game_over(player, projectile_list, asteroid_list, alien, alien_projectile_list)
	} else {
		potentially_reset_space_ship(player)
	}
}

draw_game :: proc(
	player: ^Space_Ship,
	projectiles: ^[dynamic]Projectile,
	asteroids: ^[dynamic]Asteroid,
	alien: ^Alien,
	alien_projectiles: ^[dynamic]Projectile,
	particle_list: ^[dynamic]Particle,
) {
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(rl.BLACK)
	if !GAME_OVER && !player.inactive do draw_space_ship(player)
	draw_projectiles(projectiles, rl.WHITE)
	draw_asteroids(asteroids)
	draw_alien(alien)
	draw_projectiles(alien_projectiles, rl.WHITE)
	draw_particles(particle_list)
	draw_points()
	draw_lives()
}

draw_points :: proc() {
	rl.DrawText(fmt.ctprintf("Points: %d", POINTS), 10, 10, 30, rl.WHITE)
}

handle_out_of_screen :: proc(player: ^Space_Ship) {
	if player.position.x > f32(rl.GetScreenWidth()) {
		player.position.x = 0
	} else if player.position.x < 0 {
		player.position.x = f32(rl.GetScreenWidth())
	}

	if player.position.y > f32(rl.GetScreenHeight()) {
		player.position.y = 0
	} else if player.position.y < 0 {
		player.position.y = f32(rl.GetScreenHeight())
	}
}

Space_Ship :: struct {
	position:   rl.Vector2,
	angle:      f32,
	direction:  rl.Vector2,
	velocity:   rl.Vector2,
	spawn_time: f64,
	death_time: f64,
	inactive:   bool,
	invincible: bool,
}

spawn_space_ship :: proc(space_ship: ^Space_Ship) {
	space_ship^ = {
		position   = {f32(rl.GetScreenWidth() / 2), f32(rl.GetScreenHeight() / 2)},
		angle      = 0,
		direction  = {0, 1},
		velocity   = {0, 0},
		spawn_time = rl.GetTime(),
		death_time = 0,
		inactive   = false,
		invincible = true,
	}
}

potentially_reset_space_ship :: proc(space_ship: ^Space_Ship) {
	if space_ship.inactive && rl.GetTime() - space_ship.death_time > 1 {
		spawn_space_ship(space_ship)
	}
}

check_space_ship_collision :: proc(
	space_ship: ^Space_Ship,
	asteroid_list: ^[dynamic]Asteroid,
	alien: ^Alien,
	alien_projectile_list: ^[dynamic]Projectile,
	particle_list: ^[dynamic]Particle,
	explosion_sound: ^rl.Sound,
) {
	if space_ship.invincible do return

	reset_space_ship :: proc(space_ship: ^Space_Ship, particle_list: ^[dynamic]Particle) {
		LIVES -= 1
		if LIVES == 0 do GAME_OVER = true
		spawn_particles(particle_list, space_ship.position)
		spawn_space_ship(space_ship)
		space_ship.position = {99999, 99999}
		space_ship.inactive = true
		space_ship.death_time = rl.GetTime()
	}

	space_ship_radius: f32 = 9
	for &asteroid in asteroid_list {
		collided := rl.CheckCollisionCircles(
			space_ship.position,
			space_ship_radius,
			asteroid.position,
			asteroid.radius,
		)
		if collided {
			rl.PlaySound(explosion_sound^)
			reset_space_ship(space_ship, particle_list)
			return
		}
	}

	for &alien_projectile, i in alien_projectile_list {
		collided := rl.CheckCollisionCircles(
			space_ship.position,
			space_ship_radius,
			alien_projectile.position,
			2,
		)
		if collided {
			rl.PlaySound(explosion_sound^)
			reset_space_ship(space_ship, particle_list)
			unordered_remove(alien_projectile_list, i)
			return
		}
	}

	collided_with_alien := rl.CheckCollisionCircleRec(
		space_ship.position,
		space_ship_radius,
		alien.hit_box,
	)
	if collided_with_alien {
		rl.PlaySound(explosion_sound^)
		reset_space_ship(space_ship, particle_list)
	}
}

should_blink :: proc(space_ship: ^Space_Ship) -> bool {
	if space_ship.invincible {
		if math.mod(rl.GetTime() - space_ship.spawn_time, 0.2) < 0.1 {
			return true
		}
	}
	return false
}

update_space_ship :: proc(space_ship: ^Space_Ship) {
	dir_angle := space_ship.angle - math.PI * 0.5
	space_ship.direction = rl.Vector2{math.cos(dir_angle), math.sin(dir_angle)}

	DRAG :: 0.03
	space_ship.velocity *= (1 - DRAG)
	space_ship.position += space_ship.velocity

	if rl.GetTime() - space_ship.spawn_time > 2 do space_ship.invincible = false
}

draw_space_ship :: proc(space_ship: ^Space_Ship) {
	if should_blink(space_ship) do return
	scale: f32 = 15
	points: [5]rl.Vector2 = {{-0.8, 1.0}, {0.0, -1.0}, {0.8, 1.0}, {0.4, 0.8}, {-0.4, 0.8}}
	points *= scale
	for i in 0 ..< len(points) {
		rl.DrawLineEx(
			space_ship.position + rl.Vector2Rotate(points[i], space_ship.angle),
			space_ship.position +
			rl.Vector2Rotate(points[(i + 1) % len(points)], space_ship.angle),
			2,
			rl.WHITE,
		)
	}
}

draw_thrust_for_space_ship :: proc(space_ship: ^Space_Ship) {
	if should_blink(space_ship) do return
	scale: f32 = 15
	thrust_points: [3]rl.Vector2 = {{0.4, 0.8}, {-0.4, 0.8}, {0.0, 1.2}}
	thrust_points *= scale
	for i in 0 ..< len(thrust_points) {
		rl.DrawLineEx(
			space_ship.position + rl.Vector2Rotate(thrust_points[i], space_ship.angle),
			space_ship.position +
			rl.Vector2Rotate(thrust_points[(i + 1) % len(thrust_points)], space_ship.angle),
			2,
			rl.WHITE,
		)
	}
}

Projectile :: struct {
	position:   rl.Vector2,
	direction:  rl.Vector2,
	time_alive: f64,
}

spawn_projectile :: proc(space_ship: ^Space_Ship, projectile_list: ^[dynamic]Projectile) {
	projectile := Projectile {
		{space_ship.position.x, space_ship.position.y},
		space_ship.direction,
		rl.GetTime(),
	}
	append(projectile_list, projectile)
}

update_projectile_positions :: proc(projectiles: ^[dynamic]Projectile, projectile_speed: f32) {
	for &projectile in projectiles {
		if projectile.position.x < 0 do projectile.position.x = f32(rl.GetScreenWidth())
		if projectile.position.y < 0 do projectile.position.y = f32(rl.GetScreenHeight())
		if projectile.position.x > f32(rl.GetScreenWidth()) do projectile.position.x = 0
		if projectile.position.y > f32(rl.GetScreenHeight()) do projectile.position.y = 0
		projectile.position += projectile_speed * projectile.direction
	}
}

despawn_projectiles :: proc(projectiles: ^[dynamic]Projectile, is_from_alien := false) {
	now := rl.GetTime()
	for i := 0; i < len(projectiles); i += 1 {
		if now - projectiles[i].time_alive > 1 {
			unordered_remove(projectiles, i)
			i -= 1
		}
	}
}

draw_projectiles :: proc(projectile_list: ^[dynamic]Projectile, color: rl.Color) {
	for projectile in projectile_list {
		rl.DrawCircle(cast(i32)projectile.position.x, cast(i32)projectile.position.y, 2, color)
	}
}

Asteroid :: struct {
	position:           rl.Vector2,
	velocity:           rl.Vector2,
	type:               Asteroid_Size,
	radius:             f32,
	points:             [16]rl.Vector2,
	angle:              f32,
	rotation_direction: int,
}

Asteroid_Size :: enum {
	big,
	medium,
	small,
}

generate_asteroids :: proc(asteroid_list: ^[dynamic]Asteroid) {
	for _ in 0 ..< ASTEROID_NUMBER {
		asteroid := generate_single_asteroid(Asteroid_Size.big)
		append(asteroid_list, asteroid)
	}
	if ASTEROID_NUMBER < 10 {
		ASTEROID_NUMBER += 1
	}
	START_TIME = rl.GetTime()
}

generate_single_asteroid :: proc(type: Asteroid_Size, position: rl.Vector2 = {}) -> Asteroid {
	position := position
	velocity: rl.Vector2
	angle: f32 = 0
	rotation_choices: [2]int = {-1, 1}
	rotation_direction := rand.choice(rotation_choices[:])
	radius: f32

	switch type {
	case .big:
		top_bottom_spawn := rl.Vector2{f32(rl.GetRandomValue(0, rl.GetScreenWidth())), 0}
		left_right_spawn := rl.Vector2{0, f32(rl.GetRandomValue(0, rl.GetScreenHeight()))}
		spawn_choices: [2]rl.Vector2 = {top_bottom_spawn, left_right_spawn}
		position = rand.choice(spawn_choices[:])
		velocity = {f32(rl.GetRandomValue(-2, 2)), f32(rl.GetRandomValue(-2, 2))}
		radius = 60
	case .medium:
		velocity = {f32(rl.GetRandomValue(-3, 3)), f32(rl.GetRandomValue(-3, 3))}
		radius = 35
	case .small:
		velocity = {f32(rl.GetRandomValue(-4, 4)), f32(rl.GetRandomValue(-4, 4))}
		radius = 15
	}

	points: [16]rl.Vector2
	for i in 0 ..< len(points) {
		random_radius_modifier: f32
		switch type {
		case .big:
			random_radius_modifier = f32(rl.GetRandomValue(0, 20))
		case .medium:
			random_radius_modifier = f32(rl.GetRandomValue(0, 15))
		case .small:
			random_radius_modifier = f32(rl.GetRandomValue(0, 5))
		}
		points[i] = rl.Vector2Rotate({radius - random_radius_modifier, 0}, f32(i) * math.PI / 8)
	}

	if velocity.x == 0 do velocity.x = 1
	if velocity.y == 0 do velocity.y = 1

	return Asteroid{position, velocity, type, radius, points, angle, rotation_direction}
}

update_asteroids :: proc(
	asteroid_list: ^[dynamic]Asteroid,
	projectile_list: ^[dynamic]Projectile,
	alien_projectile_list: ^[dynamic]Projectile,
	alien: ^Alien,
	particle_list: ^[dynamic]Particle,
	explosion_sound: ^rl.Sound,
) {
	for &asteroid in asteroid_list {
		asteroid.angle += 0.01 * f32(asteroid.rotation_direction)
		asteroid.position += asteroid.velocity
		handle_out_of_screen_asteroids(&asteroid)
	}
	check_laser_collision(
		projectile_list,
		asteroid_list,
		false,
		alien,
		particle_list,
		explosion_sound,
	)
	check_laser_collision(
		alien_projectile_list,
		asteroid_list,
		true,
		nil,
		particle_list,
		explosion_sound,
	)
}

handle_out_of_screen_asteroids :: proc(asteroid: ^Asteroid) {
	if asteroid.position.x > f32(rl.GetScreenWidth()) {
		asteroid.position.x = 0
	} else if asteroid.position.x < 0 {
		asteroid.position.x = f32(rl.GetScreenWidth())
	}

	if asteroid.position.y > f32(rl.GetScreenHeight()) {
		asteroid.position.y = 0
	} else if asteroid.position.y < 0 {
		asteroid.position.y = f32(rl.GetScreenHeight())
	}
}

draw_asteroids :: proc(asteroid_list: ^[dynamic]Asteroid) {
	for &asteroid in asteroid_list {
		for i in 0 ..< len(asteroid.points) {
			rl.DrawLineEx(
				asteroid.position + rl.Vector2Rotate(asteroid.points[i], asteroid.angle),
				asteroid.position +
				rl.Vector2Rotate(asteroid.points[(i + 1) % len(asteroid.points)], asteroid.angle),
				asteroid.type == .big ? 3 : asteroid.type == .medium ? 2 : 1,
				rl.WHITE,
			)
		}
	}
}

check_laser_collision :: proc(
	projectiles: ^[dynamic]Projectile,
	asteroids: ^[dynamic]Asteroid,
	projectile_from_alien: bool = false,
	alien: ^Alien,
	particle_list: ^[dynamic]Particle,
	explosion_sound: ^rl.Sound,
) {
	for &projectile, i in projectiles {
		for &asteroid, j in asteroids {
			collided := rl.CheckCollisionPointCircle(
				projectile.position,
				asteroid.position,
				asteroid.radius,
			)
			if collided {
				switch asteroid.type {
				case .big:
					if !projectile_from_alien && !GAME_OVER do POINTS += 20
					asteroid1 := generate_single_asteroid(Asteroid_Size.medium, asteroid.position)
					asteroid2 := generate_single_asteroid(Asteroid_Size.medium, asteroid.position)
					if asteroid1.position == asteroid2.position &&
					   asteroid1.velocity == asteroid2.velocity {
						asteroid2.velocity = asteroid1.velocity + {1, 0}
					}
					append(asteroids, asteroid1, asteroid2)
				case .medium:
					if !projectile_from_alien && !GAME_OVER do POINTS += 50
					asteroid1 := generate_single_asteroid(Asteroid_Size.small, asteroid.position)
					asteroid2 := generate_single_asteroid(Asteroid_Size.small, asteroid.position)
					if asteroid1.position == asteroid2.position &&
					   asteroid1.velocity == asteroid2.velocity {
						asteroid2.velocity = asteroid1.velocity + {1, 0}
					}
					append(asteroids, asteroid1, asteroid2)
				case .small:
					if !projectile_from_alien && !GAME_OVER do POINTS += 100
				}

				rl.PlaySound(explosion_sound^)
				spawn_particles(particle_list, asteroid.position)

				unordered_remove(projectiles, i)
				unordered_remove(asteroids, j)

				return
			}
		}
	}

	if !projectile_from_alien {
		for &projectile, i in projectiles {
			collided := rl.CheckCollisionCircleRec(projectile.position, 2, alien.hit_box)
			if collided {
				if alien.type == .big do POINTS += 200
				else do POINTS += 1000
				rl.PlaySound(explosion_sound^)
				unordered_remove(projectiles, i)
				spawn_particles(particle_list, alien.position)
				despawn_alien(alien)
			}
		}
	}
}

Alien_Type :: enum {
	big,
	small,
}

Alien :: struct {
	type:                  Alien_Type,
	position:              rl.Vector2,
	direction:             rl.Vector2,
	change_direction_time: f64,
	spawn_projectile_time: f64,
	hit_box:               rl.Rectangle,
	scale:                 f32,
	inactive_time:         f64,
	alive:                 bool,
}

init_alien :: proc(alien: ^Alien, alien_type: Alien_Type) {
	alien.type = alien_type
	alien.position = {99999, 99999}
	alien.direction = {0, 0}
	if alien_type == .big do alien.scale = 30
	else do alien.scale = 15
	alien.inactive_time = rl.GetTime()
	alien.alive = false
	alien.hit_box = rl.Rectangle {
		alien.position.x - 0.7 * alien.scale,
		alien.position.y - 0.4 * alien.scale,
		1.4 * alien.scale,
		0.8 * alien.scale,
	}
}

spawn_alien :: proc(alien: ^Alien) {
	possible_x_start_pos: [2]f32 = {0, f32(rl.GetScreenWidth())}
	alien.position =  {
		rand.choice(possible_x_start_pos[:]),
		f32(rl.GetRandomValue(200, rl.GetScreenHeight() - 200)),
	}
	if alien.position.x == possible_x_start_pos[0] do alien.direction = {1, 0}
	else if alien.position.x == possible_x_start_pos[1] do alien.direction = {-1, 0}
	alien.inactive_time = rl.GetTime()
	alien.alive = true
	alien.hit_box = rl.Rectangle {
		alien.position.x - 0.7 * alien.scale,
		alien.position.y - 0.4 * alien.scale,
		1.4 * alien.scale,
		0.8 * alien.scale,
	}
}

despawn_alien :: proc(alien: ^Alien) {
	if GAME_OVER do alien.type = .big
	else do alien.type = rand.choice_enum(Alien_Type)
	if alien.type == .big do alien.scale = 30
	else do alien.scale = 15
	alien.position = {99999, 99999}
	alien.direction = {0, 0}
	alien.alive = false
	alien.inactive_time = rl.GetTime()
	alien.hit_box = rl.Rectangle {
		alien.position.x - 0.7 * alien.scale,
		alien.position.y - 0.4 * alien.scale,
		1.4 * alien.scale,
		0.8 * alien.scale,
	}
}

draw_alien :: proc(alien: ^Alien) {
	points: [6]rl.Vector2 =  {
		{-0.9, 0},
		{-0.5, 0.4},
		{0.5, 0.4},
		{0.9, 0},
		{0.5, -0.3},
		{-0.5, -0.3},
	}
	for i in 0 ..< len(points) {
		rl.DrawLineEx(
			alien.position + points[i] * alien.scale,
			alien.position + points[(i + 1) % len(points)] * alien.scale,
			2,
			rl.WHITE,
		)
	}
	rl.DrawLineEx(
		alien.position + points[0] * alien.scale,
		alien.position + points[3] * alien.scale,
		2,
		rl.WHITE,
	)

	head_points: [4]rl.Vector2 = {points[4], {0.3, -0.6}, {-0.3, -0.6}, points[5]}
	for i in 0 ..< len(head_points) {
		if i == len(head_points) - 1 do break
		rl.DrawLineEx(
			alien.position + head_points[i] * alien.scale,
			alien.position + head_points[i + 1] * alien.scale,
			2,
			rl.WHITE,
		)
	}
}

update_alien :: proc(alien: ^Alien, alien_alarm: ^rl.Sound) {
	spawn_time: f64 = 10
	if POINTS > 20000 do spawn_time = 5
	else if POINTS > 10000 do spawn_time = 6
	else if POINTS > 5000 do spawn_time = 7
	else if POINTS > 2000 do spawn_time = 8
	else if POINTS > 1000 do spawn_time = 9

	should_spawn := rl.GetTime() - alien.inactive_time > spawn_time
	if should_spawn && !alien.alive do spawn_alien(alien)
	if alien.change_direction_time == 0 do alien.change_direction_time = rl.GetTime()
	if !(alien.position.x < 300 && alien.direction.x == 1 ||
		   alien.position.x > f32(rl.GetScreenWidth() - 300)) {
		if rl.GetTime() - alien.change_direction_time > 0.5 {
			x := f32(rl.GetRandomValue(-1, 1))
			y := f32(rl.GetRandomValue(-1, 1))
			if x == 0 && y == 0 do x = 1
			alien.direction = {x, y}
			alien.change_direction_time = 0
		}
	}
	alien.position += 2 * alien.direction
	alien.hit_box =  {
		alien.position.x - 0.7 * alien.scale,
		alien.position.y - 0.4 * alien.scale,
		1.4 * alien.scale,
		0.8 * alien.scale,
	}

	if alien.alive && !rl.IsSoundPlaying(alien_alarm^) do rl.PlaySound(alien_alarm^)
}

spawn_alien_projectile :: proc(
	alien: ^Alien,
	space_ship: ^Space_Ship,
	alien_projectile_list: ^[dynamic]Projectile,
	projectile_sound: ^rl.Sound,
) {
	if alien.spawn_projectile_time == 0 do alien.spawn_projectile_time = rl.GetTime()
	should_fire: bool
	if alien.type == .big do should_fire = rl.GetTime() - alien.spawn_projectile_time > 1
	else do should_fire = rl.GetTime() - alien.spawn_projectile_time > 0.7
	if should_fire && alien.alive {
		projectile := Projectile {
			{alien.position.x, alien.position.y},
			rl.Vector2Normalize(space_ship.position - alien.position),
			rl.GetTime(),
		}
		append(alien_projectile_list, projectile)
		alien.spawn_projectile_time = 0
		rl.PlaySound(projectile_sound^)
	}
}

update_alien_projectile_positions :: proc(
	alien_projectiles: ^[dynamic]Projectile,
	alien_projectile_speed: f32,
) {
	for &projectile in alien_projectiles {
		projectile.position += alien_projectile_speed * projectile.direction
	}
}

check_alien_collision :: proc(
	alien: ^Alien,
	space_ship: ^Space_Ship,
	asteroid_list: ^[dynamic]Asteroid,
	particle_list: ^[dynamic]Particle,
	explosion_sound: ^rl.Sound,
) {
	collided_with_asteroid := false
	for &asteroid in asteroid_list {
		collided_with_asteroid = rl.CheckCollisionCircleRec(
			asteroid.position,
			asteroid.radius,
			alien.hit_box,
		)
		if collided_with_asteroid {
			rl.PlaySound(explosion_sound^)
			spawn_particles(particle_list, alien.position)
			despawn_alien(alien)
			return
		}
	}
}

handle_out_of_screen_alien :: proc(alien: ^Alien) {
	if alien.position.x == 99999 && alien.position.y == 99999 do return
	if alien.position.x > f32(rl.GetScreenWidth()) {
		alien.position.x = 0
	} else if alien.position.x < 0 {
		alien.position.x = f32(rl.GetScreenWidth())
	}

	if alien.position.y > f32(rl.GetScreenHeight()) {
		alien.position.y = 0
	} else if alien.position.y < 0 {
		alien.position.y = f32(rl.GetScreenHeight())
	}
}

Particle :: struct {
	position:   rl.Vector2,
	direction:  rl.Vector2,
	time_alive: f64,
}

spawn_particles :: proc(particle_list: ^[dynamic]Particle, position: rl.Vector2) {
	for i in 0 ..< 10 {
		append(
			particle_list,
			Particle {
				position = position,
				direction = rl.Vector2 {
					math.cos(f32(i) * math.PI / 5),
					math.sin(f32(i) * math.PI / 5),
				},
				time_alive = rl.GetTime(),
			},
		)
	}
}

update_particles :: proc(particles: ^[dynamic]Particle) {
	for i := 0; i < len(particles); i += 1 {
		if rl.GetTime() - particles[i].time_alive > 0.5 {
			unordered_remove(particles, i)
			i -= 1
			continue
		}
		particles[i].position += 2 * particles[i].direction
	}
}

draw_particles :: proc(particle_list: ^[dynamic]Particle) {
	for &particle in particle_list {
		rl.DrawRectangleV(particle.position, 2, rl.WHITE)
	}
}

draw_lives :: proc() {
	scale: f32 = 12
	points: [5]rl.Vector2 = {{-0.8, 1.0}, {0.0, -1.0}, {0.8, 1.0}, {0.4, 0.8}, {-0.4, 0.8}}
	points *= scale
	for life_index in 0 ..< LIVES {
		start_pos := rl.Vector2{10 + scale + f32(life_index) * 30, 60}
		for point_index in 0 ..< len(points) {
			rl.DrawLineEx(
				start_pos + points[point_index],
				start_pos + points[(point_index + 1) % len(points)],
				1,
				rl.WHITE,
			)
		}
	}
}

Sound :: struct {
	projectile:     rl.Sound,
	explosion:      rl.Sound,
	thrust:         rl.Sound,
	alien_alarm:    rl.Sound,
	heartbeat_low:  rl.Sound,
	heartbeat_high: rl.Sound,
}

init_audio :: proc(sound: ^Sound) {
	rl.InitAudioDevice()
	sound.projectile = rl.LoadSound("./audio/laser.wav")
	sound.explosion = rl.LoadSound("./audio/explosion.wav")
	sound.thrust = rl.LoadSound("./audio/thrust.wav")
	sound.alien_alarm = rl.LoadSound("./audio/alien_alarm.wav")
	sound.heartbeat_low = rl.LoadSound("./audio/heartbeat_low.wav")
	sound.heartbeat_high = rl.LoadSound("./audio/heartbeat_high.wav")
}

deinit_audio :: proc(sound: ^Sound) {
	rl.UnloadSound(sound.projectile)
	rl.UnloadSound(sound.explosion)
	rl.UnloadSound(sound.thrust)
	rl.UnloadSound(sound.alien_alarm)
	rl.UnloadSound(sound.heartbeat_low)
	rl.UnloadSound(sound.heartbeat_high)
	rl.CloseAudioDevice()
}

play_background_heartbeat :: proc(sound: ^Sound) {
	play_sound: bool
	play_speed := [?]f64{1, 0.5, 0.25}
	speed_index := 0
	current_time := rl.GetTime()
	if current_time - START_TIME > 20 do speed_index = 2
	else if current_time - START_TIME > 10 do speed_index = 1
	if math.mod(current_time, play_speed[speed_index]) < f64(rl.GetFrameTime()) {
		play_sound = true
	}
	if play_sound {
		heartbeats := [2]rl.Sound{sound.heartbeat_low, sound.heartbeat_high}
		@(static)
		i := 0
		if i == 0 do i = 1
		else do i = 0
		rl.PlaySound(heartbeats[i])
	}
}
