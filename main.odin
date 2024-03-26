package main

import "core:math"
import rl "vendor:raylib"

SCREEN_WIDTH :: 1024
SCREEN_HEIGHT :: 768

main :: proc() {
	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Asteroids")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	player := Space_Ship{{f32(rl.GetScreenWidth() / 2), f32(rl.GetScreenHeight() / 2)}, 0, {0, 1}}
	projectile_list := make([dynamic]Projectile)

	for !rl.WindowShouldClose() {
		check_input(&player, &projectile_list)
		update_projectile_positions(&projectile_list, 5)
		draw_game(&player, &projectile_list)
	}
}

check_input :: proc(player: ^Space_Ship, projectile_list: ^[dynamic]Projectile) {
	dir_angle := player.angle - math.PI * 0.5
	player.direction = rl.Vector2{math.cos(dir_angle), math.sin(dir_angle)}
	if rl.IsKeyDown(.LEFT) {
		player.angle -= rl.DEG2RAD * 5
	}
	if rl.IsKeyDown(.RIGHT) {
		player.angle += rl.DEG2RAD * 5
	}
	if rl.IsKeyDown(.UP) {
		player.position += player.direction * 3
	}
	if rl.IsKeyPressed(.SPACE) {
		spawn_projectile(player, projectile_list)
	}
}

update_projectile_positions :: proc(projectiles: ^[dynamic]Projectile, projectile_speed: f32) {
	for projectile in projectiles {
		projectile.position += projectile_speed * projectile.direction
	}
}

draw_game :: proc(player: ^Space_Ship, projectiles: ^[dynamic]Projectile) {
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(rl.BLACK)
	draw_space_ship(player)
	draw_projectiles(projectiles)
}

Space_Ship :: struct {
	position:  rl.Vector2,
	angle:     f32,
	direction: rl.Vector2,
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
	projectile_position := Projectile {
		{space_ship.position.x, space_ship.position.y},
		space_ship.direction,
	}
	append(projectile_list, projectile_position)
}

draw_projectiles :: proc(projectile_list: ^[dynamic]Projectile) {
	for projectile in projectile_list {
		rl.DrawCircle(cast(i32)projectile.position.x, cast(i32)projectile.position.y, 2, rl.RED)
	}
}
