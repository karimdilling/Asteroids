package main

import "core:fmt"
import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

SCREEN_WIDTH :: 1024
SCREEN_HEIGHT :: 768
GAME_OVER := false
POINTS := 0

main :: proc() {
	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Asteroids")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	player := Space_Ship {
		position   = {f32(rl.GetScreenWidth() / 2), f32(rl.GetScreenHeight() / 2)},
		angle      = 0,
		direction  = {0, 1},
		velocity   = {0, 0},
		death_time = 0,
		invincible = true,
	}
	projectile_list := make([dynamic]Projectile)
	defer delete(projectile_list)
	asteroid_list := make([dynamic]Asteroid)
	defer delete(asteroid_list)
	alien_projectile_list := make([dynamic]Projectile)
	defer delete(alien_projectile_list)
	particle_list := make([dynamic]Particle)
	defer delete(particle_list)

	generate_asteroids(&asteroid_list)
	alien := init_alien()

	start_game_time := rl.GetTime()

	for !rl.WindowShouldClose() {
		update_game(
			&player,
			&projectile_list,
			&asteroid_list,
			&alien,
			&alien_projectile_list,
			&start_game_time,
			&particle_list,
		)
		draw_game(
			&player,
			&projectile_list,
			&asteroid_list,
			&alien,
			&alien_projectile_list,
			&start_game_time,
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
	start_game_time: ^f64,
) {
	font_size: i32 = 50
	text: cstring = "Game Over"
	horizontal_center := rl.GetScreenWidth() / 2 - rl.MeasureText(text, font_size) / 2
	vertical_center := rl.GetScreenHeight() / 2 - font_size / 2
	rl.DrawText(text, horizontal_center, vertical_center, font_size, rl.RED)
	points_reached_text := fmt.ctprintf("Points: %d", POINTS)
	rl.DrawText(
		points_reached_text,
		horizontal_center,
		vertical_center + font_size,
		font_size,
		rl.RED,
	)

	if player.death_time != 0.0 && rl.GetTime() - player.death_time > 3.0 {
		clear(projectile_list)
		clear(asteroid_list)
		clear(alien_projectile_list)
		player^ = {
			position   = {f32(rl.GetScreenWidth() / 2), f32(rl.GetScreenHeight() / 2)},
			angle      = 0,
			direction  = {0, 1},
			velocity   = {0, 0},
			death_time = 0,
			invincible = true,
		}
		generate_asteroids(asteroid_list)
		player.death_time = 0
		despawn_alien(alien)
		POINTS = 0
		GAME_OVER = false
		start_game_time^ = rl.GetTime()
	}
}

update_game :: proc(
	player: ^Space_Ship,
	projectile_list: ^[dynamic]Projectile,
	asteroid_list: ^[dynamic]Asteroid,
	alien: ^Alien,
	alien_projectile_list: ^[dynamic]Projectile,
	start_game_time: ^f64,
	particle_list: ^[dynamic]Particle,
) {
	if len(asteroid_list) == 0 {
		generate_asteroids(asteroid_list)
	}

	handle_out_of_screen(player)
	handle_out_of_screen_alien(alien)

	dir_angle := player.angle - math.PI * 0.5
	player.direction = rl.Vector2{math.cos(dir_angle), math.sin(dir_angle)}

	DRAG :: 0.03
	player.velocity *= (1 - DRAG)
	player.position += player.velocity

	update_projectile_positions(projectile_list, 10)
	update_asteroids(asteroid_list, projectile_list, alien_projectile_list, alien, particle_list)
	update_alien(alien)
	spawn_alien_projectile(alien, player, alien_projectile_list)
	update_alien_projectile_positions(alien_projectile_list, 5)
	update_particles(particle_list)

	if !GAME_OVER do check_space_ship_collision(player, asteroid_list, alien, alien_projectile_list, particle_list)
	if rl.GetTime() - start_game_time^ > 2 do player.invincible = false
	check_alien_collision(alien, player, asteroid_list, particle_list)

	if !GAME_OVER {
		if rl.IsKeyDown(.LEFT) {
			player.angle -= rl.DEG2RAD * 5
		}
		if rl.IsKeyDown(.RIGHT) {
			player.angle += rl.DEG2RAD * 5
		}
		if rl.IsKeyDown(.UP) {
			player.velocity += player.direction * 0.5
			draw_thrust_for_space_ship(player, start_game_time)
		}
		if rl.IsKeyPressed(.SPACE) {
			spawn_projectile(player, projectile_list)
		}
	}

	if GAME_OVER {
		handle_game_over(
			player,
			projectile_list,
			asteroid_list,
			alien,
			alien_projectile_list,
			start_game_time,
		)
	}
}

draw_game :: proc(
	player: ^Space_Ship,
	projectiles: ^[dynamic]Projectile,
	asteroids: ^[dynamic]Asteroid,
	alien: ^Alien,
	alien_projectiles: ^[dynamic]Projectile,
	start_game_time: ^f64,
	particle_list: ^[dynamic]Particle,
) {
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(rl.BLACK)
	if !GAME_OVER do draw_space_ship(player, start_game_time)
	draw_projectiles(projectiles, rl.RED)
	draw_asteroids(asteroids)
	draw_alien(alien)
	draw_projectiles(alien_projectiles, rl.WHITE)
	draw_particles(particle_list)
	draw_points()
}

draw_points :: proc() {
	rl.DrawText(fmt.ctprintf("Points: %d", POINTS), 0, 0, 30, rl.WHITE)
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
	death_time: f64,
	invincible: bool,
}

check_space_ship_collision :: proc(
	space_ship: ^Space_Ship,
	asteroid_list: ^[dynamic]Asteroid,
	alien: ^Alien,
	alien_projectile_list: ^[dynamic]Projectile,
	particle_list: ^[dynamic]Particle,
) {
	if space_ship.invincible do return

	space_ship_radius: f32 = 9
	for &asteroid in asteroid_list {
		collided := rl.CheckCollisionCircles(
			space_ship.position,
			space_ship_radius,
			asteroid.position,
			asteroid.radius,
		)
		if collided {
			GAME_OVER = true
			space_ship.death_time = rl.GetTime()
			spawn_particles(particle_list, space_ship.position)
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
			GAME_OVER = true
			space_ship.death_time = rl.GetTime()
			unordered_remove(alien_projectile_list, i)
			spawn_particles(particle_list, space_ship.position)
			return
		}
	}

	collided_with_alien := rl.CheckCollisionCircleRec(
		space_ship.position,
		space_ship_radius,
		alien.hit_box,
	)
	if collided_with_alien {
		GAME_OVER = true
		space_ship.death_time = rl.GetTime()
		spawn_particles(particle_list, space_ship.position)
	}
}

should_blink :: proc(space_ship: ^Space_Ship, start_game_time: ^f64) -> bool {
	if space_ship.invincible {
		if math.mod(rl.GetTime() - start_game_time^, 0.2) < 0.1 {
			return true
		}
	}
	return false
}

draw_space_ship :: proc(space_ship: ^Space_Ship, start_game_time: ^f64) {
	if should_blink(space_ship, start_game_time) do return
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

draw_thrust_for_space_ship :: proc(space_ship: ^Space_Ship, start_game_time: ^f64) {
	if should_blink(space_ship, start_game_time) do return
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
	position:  rl.Vector2,
	direction: rl.Vector2,
}

spawn_projectile :: proc(space_ship: ^Space_Ship, projectile_list: ^[dynamic]Projectile) {
	projectile := Projectile{{space_ship.position.x, space_ship.position.y}, space_ship.direction}
	append(projectile_list, projectile)
}

update_projectile_positions :: proc(projectiles: ^[dynamic]Projectile, projectile_speed: f32) {
	for &projectile in projectiles {
		projectile.position += projectile_speed * projectile.direction
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
	for _ in 0 ..< 10 {
		asteroid := generate_single_asteroid(Asteroid_Size.big)
		append(asteroid_list, asteroid)
	}
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
) {
	for &asteroid in asteroid_list {
		asteroid.angle += 0.01 * f32(asteroid.rotation_direction)
		asteroid.position += asteroid.velocity
		handle_out_of_screen_asteroids(&asteroid)
	}
	check_laser_collision(projectile_list, asteroid_list, false, alien, particle_list)
	check_laser_collision(alien_projectile_list, asteroid_list, true, nil, particle_list)
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
				POINTS += 200
				unordered_remove(projectiles, i)
				spawn_particles(particle_list, alien.position)
				despawn_alien(alien)
			}
		}
	}
}

Alien :: struct {
	position:              rl.Vector2,
	direction:             rl.Vector2,
	change_direction_time: f64,
	spawn_projectile_time: f64,
	hit_box:               rl.Rectangle,
	scale:                 f32,
	inactive_time:         f64,
	alive:                 bool,
}

init_alien :: proc() -> Alien {
	alien := Alien {
		position      = {99999, 99999},
		direction     = {0, 0},
		scale         = 30,
		inactive_time = rl.GetTime(),
		alive         = false,
	}
	alien.hit_box = rl.Rectangle {
		alien.position.x - 0.7 * alien.scale,
		alien.position.y - 0.4 * alien.scale,
		1.4 * alien.scale,
		0.8 * alien.scale,
	}

	return alien
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
	points: [6]rl.Vector2 = {{-1, 0}, {-0.7, 0.4}, {0.7, 0.4}, {1, 0}, {0.7, -0.4}, {-0.7, -0.4}}
	for i in 0 ..< len(points) {
		if i == len(points) - 1 do break
		rl.DrawLineEx(
			alien.position + points[i] * alien.scale,
			alien.position + points[i + 1] * alien.scale,
			2,
			rl.WHITE,
		)
	}
	rl.DrawLineEx(
		alien.position + points[0] * alien.scale,
		alien.position + points[len(points) - 1] * alien.scale,
		2,
		rl.WHITE,
	)
	rl.DrawLineEx(
		alien.position + points[0] * alien.scale,
		alien.position + points[3] * alien.scale,
		2,
		rl.WHITE,
	)
	rl.DrawCircleSectorLines(alien.position + {0, -0.4} * alien.scale, 10, -180, 0, 1, rl.WHITE)
}

update_alien :: proc(alien: ^Alien) {
	if rl.GetTime() - alien.inactive_time > 10 && !alien.alive do spawn_alien(alien)
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
}

spawn_alien_projectile :: proc(
	alien: ^Alien,
	space_ship: ^Space_Ship,
	alien_projectile_list: ^[dynamic]Projectile,
) {
	if alien.spawn_projectile_time == 0 do alien.spawn_projectile_time = rl.GetTime()
	if rl.GetTime() - alien.spawn_projectile_time > 1 {
		projectile := Projectile {
			{alien.position.x, alien.position.y},
			rl.Vector2Normalize(space_ship.position - alien.position),
		}
		append(alien_projectile_list, projectile)
		alien.spawn_projectile_time = 0
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
) {
	collided_with_asteroid := false
	for &asteroid in asteroid_list {
		collided_with_asteroid = rl.CheckCollisionCircleRec(
			asteroid.position,
			asteroid.radius,
			alien.hit_box,
		)
		if collided_with_asteroid {
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
