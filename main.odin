package main

import rl "vendor:raylib"

SCREEN_WIDTH :: 1024
SCREEN_HEIGHT :: 768

main :: proc() {
	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Asteroids")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	player := Space_Ship{{{300, 300}, {325, 300}, {312.5, 270}}}
	projectile_list := make([dynamic]Projectile)

	for !rl.WindowShouldClose() {
		check_input(&player, &projectile_list)
		update_projectile_positions(&projectile_list, 3)
		draw_game(&player, &projectile_list)
	}
}

check_input :: proc(player: ^Space_Ship, projectile_list: ^[dynamic]Projectile) {
	if rl.IsKeyDown(.LEFT) {
		player.position[0].x -= 5
		player.position[1].x -= 5
		player.position[2].x -= 5
	}
	if rl.IsKeyDown(.RIGHT) {
		player.position[0].x += 5
		player.position[1].x += 5
		player.position[2].x += 5
	}
	if rl.IsKeyDown(.DOWN) {
		player.position[0].y += 5
		player.position[1].y += 5
		player.position[2].y += 5
	}
	if rl.IsKeyDown(.UP) {
		player.position[0].y -= 5
		player.position[1].y -= 5
		player.position[2].y -= 5
	}
	if rl.IsKeyPressed(.SPACE) {
		spawn_projectile(player, projectile_list)
	}
}

update_projectile_positions :: proc(projectiles: ^[dynamic]Projectile, projectile_speed: i32) {
	for projectile in projectiles {
		projectile.position.y -= projectile_speed
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
	position: [3]rl.Vector2,
}

draw_space_ship :: proc(space_ship: ^Space_Ship) {
	rl.DrawTriangleLines(
		space_ship.position[0],
		space_ship.position[1],
		space_ship.position[2],
		rl.WHITE,
	)
}

Projectile :: struct {
	position: [2]i32,
}

spawn_projectile :: proc(space_ship: ^Space_Ship, projectile_list: ^[dynamic]Projectile) {
	projectile_position := Projectile {
		{cast(i32)space_ship.position[2].x, cast(i32)space_ship.position[2].y},
	}
	append(projectile_list, projectile_position)
}

draw_projectiles :: proc(projectile_list: ^[dynamic]Projectile) {
	for projectile in projectile_list {
		rl.DrawCircle(projectile.position.x, projectile.position.y, 2, rl.RED)
	}
}
