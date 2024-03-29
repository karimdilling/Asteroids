package main

import "core:math"
import rl "vendor:raylib"

SCREEN_WIDTH :: 1024
SCREEN_HEIGHT :: 768
GAME_OVER := false

main :: proc() {
	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Asteroids")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	player := Space_Ship {
		{f32(rl.GetScreenWidth() / 2), f32(rl.GetScreenHeight() / 2)},
		0,
		{0, 1},
		{0, 0},
		0,
	}
	projectile_list := make([dynamic]Projectile)
	defer delete(projectile_list)
	asteroid_list := make([dynamic]Asteroid)
	defer delete(asteroid_list)

	generate_asteroids(&asteroid_list)

	for !rl.WindowShouldClose() {
		update_game(&player, &projectile_list, &asteroid_list)
		draw_game(&player, &projectile_list, &asteroid_list)
	}
}

handle_game_over :: proc(
	player: ^Space_Ship,
	projectile_list: ^[dynamic]Projectile,
	asteroid_list: ^[dynamic]Asteroid,
) {
	font_size: i32 = 50
	text: cstring = "Game Over"
	rl.DrawText(
		text,
		rl.GetScreenWidth() / 2 - rl.MeasureText(text, font_size) / 2,
		rl.GetScreenHeight() / 2 - font_size / 2,
		font_size,
		rl.RED,
	)

	if player.death_time != 0.0 && rl.GetTime() - player.death_time > 3.0 {
		clear(projectile_list)
		clear(asteroid_list)
		player^ =  {
			{f32(rl.GetScreenWidth() / 2), f32(rl.GetScreenHeight() / 2)},
			0,
			{0, 1},
			{0, 0},
			0,
		}
		generate_asteroids(asteroid_list)
		player.death_time = 0
		GAME_OVER = false
	}
}

update_game :: proc(
	player: ^Space_Ship,
	projectile_list: ^[dynamic]Projectile,
	asteroid_list: ^[dynamic]Asteroid,
) {
	if len(asteroid_list) == 0 {
		generate_asteroids(asteroid_list)
	}

	handle_out_of_screen(player)

	dir_angle := player.angle - math.PI * 0.5
	player.direction = rl.Vector2{math.cos(dir_angle), math.sin(dir_angle)}

	DRAG :: 0.03
	player.velocity *= (1 - DRAG)
	player.position += player.velocity

	update_projectile_positions(projectile_list, 10)
	update_asteroids(asteroid_list, projectile_list)

	if !GAME_OVER do check_space_ship_collision(player, asteroid_list)

	if !GAME_OVER {
		if rl.IsKeyDown(.LEFT) {
			player.angle -= rl.DEG2RAD * 5
		}
		if rl.IsKeyDown(.RIGHT) {
			player.angle += rl.DEG2RAD * 5
		}
		if rl.IsKeyDown(.UP) {
			player.velocity += player.direction * 0.5
		}
		if rl.IsKeyPressed(.SPACE) {
			spawn_projectile(player, projectile_list)
		}
	}

	if GAME_OVER {
		handle_game_over(player, projectile_list, asteroid_list)
	}
}

update_projectile_positions :: proc(projectiles: ^[dynamic]Projectile, projectile_speed: f32) {
	for &projectile in projectiles {
		projectile.position += projectile_speed * projectile.direction
	}
}

draw_game :: proc(
	player: ^Space_Ship,
	projectiles: ^[dynamic]Projectile,
	asteroids: ^[dynamic]Asteroid,
) {
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(rl.BLACK)
	if !GAME_OVER do draw_space_ship(player)
	draw_projectiles(projectiles)
	draw_asteroids(asteroids)
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
}

check_space_ship_collision :: proc(space_ship: ^Space_Ship, asteroid_list: ^[dynamic]Asteroid) {
	for &asteroid in asteroid_list {
		collided := rl.CheckCollisionCircles(
			space_ship.position,
			5,
			asteroid.position,
			asteroid.radius,
		)
		if collided {
			GAME_OVER = true
			space_ship.death_time = rl.GetTime()
		}
	}
}

draw_space_ship :: proc(space_ship: ^Space_Ship) {
	points: [3]rl.Vector2 = {{-1, 1}, {1, 1}, {0, -1}}
	scale: f32 = 10
	point1 := space_ship.position + rl.Vector2Rotate(points[0] * scale, space_ship.angle)
	point2 := space_ship.position + rl.Vector2Rotate(points[1] * scale, space_ship.angle)
	point3 := space_ship.position + rl.Vector2Rotate(points[2] * scale, space_ship.angle)
	rl.DrawTriangleLines(point1, point2, point3, rl.WHITE)
}

Projectile :: struct {
	position:  rl.Vector2,
	direction: rl.Vector2,
}

spawn_projectile :: proc(space_ship: ^Space_Ship, projectile_list: ^[dynamic]Projectile) {
	projectile := Projectile{{space_ship.position.x, space_ship.position.y}, space_ship.direction}
	append(projectile_list, projectile)
}

draw_projectiles :: proc(projectile_list: ^[dynamic]Projectile) {
	for projectile in projectile_list {
		rl.DrawCircle(cast(i32)projectile.position.x, cast(i32)projectile.position.y, 2, rl.RED)
	}
}

Asteroid :: struct {
	position: rl.Vector2,
	velocity: rl.Vector2,
	type:     Asteroid_Size,
	radius:   f32,
	sides:    i32,
	angle:    f32,
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
	angle := f32(rl.GetRandomValue(0, 360))
	sides := rl.GetRandomValue(5, 10)
	radius: f32

	switch type {
	case .big:
		position =  {
			f32(rl.GetRandomValue(0, rl.GetScreenWidth())),
			f32(rl.GetRandomValue(0, rl.GetScreenHeight())),
		}
		velocity = {f32(rl.GetRandomValue(-2, 2)), f32(rl.GetRandomValue(-2, 2))}
		radius = f32(rl.GetRandomValue(30, 50))
	case .medium:
		velocity = {f32(rl.GetRandomValue(-3, 3)), f32(rl.GetRandomValue(-3, 3))}
		radius = f32(rl.GetRandomValue(20, 25))
	case .small:
		velocity = {f32(rl.GetRandomValue(-4, 4)), f32(rl.GetRandomValue(-4, 4))}
		radius = f32(rl.GetRandomValue(10, 15))
	}

	if velocity.x == 0 do velocity.x = 1
	if velocity.y == 0 do velocity.y = 1

	return Asteroid{position, velocity, type, radius, sides, angle}
}


update_asteroids :: proc(
	asteroid_list: ^[dynamic]Asteroid,
	projectile_list: ^[dynamic]Projectile,
) {
	for &asteroid in asteroid_list {
		asteroid.angle += 1
		asteroid.position += asteroid.velocity
		handle_out_of_screen_asteroids(&asteroid)
	}
	check_laser_collision(projectile_list, asteroid_list)
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
		rl.DrawPolyLinesEx(
			asteroid.position,
			asteroid.sides,
			asteroid.radius,
			asteroid.angle,
			asteroid.type == .big ? 3 : asteroid.type == .medium ? 2 : 1,
			rl.WHITE,
		)
	}
}

check_laser_collision :: proc(projectiles: ^[dynamic]Projectile, asteroids: ^[dynamic]Asteroid) {
	for &projectile, i in projectiles {
		for &asteroid, j in asteroids {
			collided := rl.CheckCollisionPointCircle(
				projectile.position,
				asteroid.position,
				asteroid.radius,
			)
			if collided {
				#partial switch asteroid.type {
				case .big:
					asteroid1 := generate_single_asteroid(Asteroid_Size.medium, asteroid.position)
					asteroid2 := generate_single_asteroid(Asteroid_Size.medium, asteroid.position)
					append(asteroids, asteroid1, asteroid2)
				case .medium:
					asteroid1 := generate_single_asteroid(Asteroid_Size.small, asteroid.position)
					asteroid2 := generate_single_asteroid(Asteroid_Size.small, asteroid.position)
					append(asteroids, asteroid1, asteroid2)
				}

				unordered_remove(projectiles, i)
				unordered_remove(asteroids, j)

				return
			}
		}
	}
}
