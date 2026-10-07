package main

import "core:math/noise"
import rl "vendor:raylib"

ATLAS_WIDTH :: 16
TEXTURE_WIDTH :: 16


BlockType :: enum {
	GRASS,
	DIRT,
	STONE,
	AIR,
}

BlockTextureCoord :: struct {
	top:    [2]i32,
	side:   [2]i32,
	bottom: [2]i32,
}

get_block_texture_coord :: proc(block_type: BlockType) -> BlockTextureCoord {
	#partial switch block_type {
	case .GRASS:
		return {top = {0, 0}, side = {3, 0}, bottom = {2, 0}}
	case .DIRT:
		return {top = {2, 0}, side = {2, 0}, bottom = {2, 0}}
	case .STONE:
		return {top = {1, 0}, side = {1, 0}, bottom = {1, 0}}
	}
	unreachable()
}

CHUNK_WIDTH :: 16

Chunk :: struct {
	vertices:  [dynamic]f32,
	texcoords: [dynamic]f32,
	colors:    [dynamic]u8,
	indices:   [dynamic]u16,
	p:         [2]i32,
	blocks:    [dynamic]BlockType,
}

Face :: struct {
	vertices:   [4 * 3]f32,
	textcoords: [4 * 3]f32,
	colors:     [4 * 4]u8,
	indices:    [2 * 3]i32,
}
chunk_fill_geometry :: proc(chunk: ^Chunk) {
	clear(&chunk.vertices)
	clear(&chunk.texcoords)
	clear(&chunk.colors)
	clear(&chunk.indices)

	EPSILON :: 0.0005

	COLOR_TOP := []u8 {
		255,
		255,
		255,
		255,
		255,
		255,
		255,
		255,
		255,
		255,
		255,
		255,
		255,
		255,
		255,
		255,
	}
	COLOR_SIDE_Z := []u8 {
		204,
		204,
		204,
		255,
		204,
		204,
		204,
		255,
		204,
		204,
		204,
		255,
		204,
		204,
		204,
		255,
	}
	COLOR_SIDE_X := []u8 {
		153,
		153,
		153,
		255,
		153,
		153,
		153,
		255,
		153,
		153,
		153,
		255,
		153,
		153,
		153,
		255,
	}
	COLOR_BOTTOM := []u8 {
		102,
		102,
		102,
		255,
		102,
		102,
		102,
		255,
		102,
		102,
		102,
		255,
		102,
		102,
		102,
		255,
	}

	is_air :: proc(chunk: ^Chunk, pos: [3]i32) -> bool {
		if pos.x < 0 || pos.x >= CHUNK_WIDTH || pos.z < 0 || pos.z >= CHUNK_WIDTH {
			return true
		}
		if pos.y < 0 || pos.y >= 10 {
			return true
		}

		block_type := chunk_get_block(chunk, pos)
		return block_type == .AIR
	}

	quad_count := 0

	for x in 0 ..< CHUNK_WIDTH {
		for z in 0 ..< CHUNK_WIDTH {
			for y in 0 ..< 10 {
				block_pos := [3]i32{i32(x), i32(y), i32(z)}
				block_type := chunk_get_block(chunk, block_pos)

				if block_type == .AIR do continue

				texture_coord := get_block_texture_coord(block_type)
				fx, fy, fz := f32(x), f32(y), f32(z)

				// --- FACE HAUT (Y + 1) ---
				if is_air(chunk, {i32(x), i32(y) + 1, i32(z)}) {
					u_min := f32(texture_coord.top[0]) / ATLAS_WIDTH + EPSILON
					v_min := f32(texture_coord.top[1]) / ATLAS_WIDTH + EPSILON
					u_max := f32(texture_coord.top[0] + 1) / ATLAS_WIDTH - EPSILON
					v_max := f32(texture_coord.top[1] + 1) / ATLAS_WIDTH - EPSILON

					append(
						&chunk.vertices,
						..[]f32 {
							fx + 0,
							fy + 1,
							fz + 0,
							fx + 0,
							fy + 1,
							fz + 1,
							fx + 1,
							fy + 1,
							fz + 1,
							fx + 1,
							fy + 1,
							fz + 0,
						},
					)
					append(
						&chunk.texcoords,
						..[]f32{u_min, v_min, u_min, v_max, u_max, v_max, u_max, v_min},
					)
					append(&chunk.colors, ..COLOR_TOP)
					quad_count += 1
				}

				// --- FACE NORD (Z - 1) ---
				if is_air(chunk, {i32(x), i32(y), i32(z) - 1}) {
					u_min := f32(texture_coord.side[0]) / ATLAS_WIDTH + EPSILON
					v_min := f32(texture_coord.side[1]) / ATLAS_WIDTH + EPSILON
					u_max := f32(texture_coord.side[0] + 1) / ATLAS_WIDTH - EPSILON
					v_max := f32(texture_coord.side[1] + 1) / ATLAS_WIDTH - EPSILON

					append(
						&chunk.vertices,
						..[]f32 {
							fx + 0,
							fy + 0,
							fz + 0,
							fx + 0,
							fy + 1,
							fz + 0,
							fx + 1,
							fy + 1,
							fz + 0,
							fx + 1,
							fy + 0,
							fz + 0,
						},
					)
					append(
						&chunk.texcoords,
						..[]f32{u_max, v_max, u_max, v_min, u_min, v_min, u_min, v_max},
					)
					append(&chunk.colors, ..COLOR_SIDE_Z)
					quad_count += 1
				}

				// --- FACE SUD (Z + 1) ---
				if is_air(chunk, {i32(x), i32(y), i32(z) + 1}) {
					u_min := f32(texture_coord.side[0]) / ATLAS_WIDTH + EPSILON
					v_min := f32(texture_coord.side[1]) / ATLAS_WIDTH + EPSILON
					u_max := f32(texture_coord.side[0] + 1) / ATLAS_WIDTH - EPSILON
					v_max := f32(texture_coord.side[1] + 1) / ATLAS_WIDTH - EPSILON

					append(
						&chunk.vertices,
						..[]f32 {
							fx + 0,
							fy + 0,
							fz + 1,
							fx + 1,
							fy + 0,
							fz + 1,
							fx + 1,
							fy + 1,
							fz + 1,
							fx + 0,
							fy + 1,
							fz + 1,
						},
					)
					append(
						&chunk.texcoords,
						..[]f32{u_min, v_max, u_max, v_max, u_max, v_min, u_min, v_min},
					)
					append(&chunk.colors, ..COLOR_SIDE_Z)
					quad_count += 1
				}

				// --- FACE OUEST (X - 1) ---
				if is_air(chunk, {i32(x) - 1, i32(y), i32(z)}) {
					u_min := f32(texture_coord.side[0]) / ATLAS_WIDTH + EPSILON
					v_min := f32(texture_coord.side[1]) / ATLAS_WIDTH + EPSILON
					u_max := f32(texture_coord.side[0] + 1) / ATLAS_WIDTH - EPSILON
					v_max := f32(texture_coord.side[1] + 1) / ATLAS_WIDTH - EPSILON

					append(
						&chunk.vertices,
						..[]f32 {
							fx + 0,
							fy + 0,
							fz + 0,
							fx + 0,
							fy + 0,
							fz + 1,
							fx + 0,
							fy + 1,
							fz + 1,
							fx + 0,
							fy + 1,
							fz + 0,
						},
					)
					append(
						&chunk.texcoords,
						..[]f32{u_min, v_max, u_max, v_max, u_max, v_min, u_min, v_min},
					)
					append(&chunk.colors, ..COLOR_SIDE_X)
					quad_count += 1
				}

				// --- FACE EST (X + 1) ---
				if is_air(chunk, {i32(x) + 1, i32(y), i32(z)}) {
					u_min := f32(texture_coord.side[0]) / ATLAS_WIDTH + EPSILON
					v_min := f32(texture_coord.side[1]) / ATLAS_WIDTH + EPSILON
					u_max := f32(texture_coord.side[0] + 1) / ATLAS_WIDTH - EPSILON
					v_max := f32(texture_coord.side[1] + 1) / ATLAS_WIDTH - EPSILON

					append(
						&chunk.vertices,
						..[]f32 {
							fx + 1,
							fy + 0,
							fz + 0,
							fx + 1,
							fy + 1,
							fz + 0,
							fx + 1,
							fy + 1,
							fz + 1,
							fx + 1,
							fy + 0,
							fz + 1,
						},
					)
					append(
						&chunk.texcoords,
						..[]f32{u_max, v_max, u_max, v_min, u_min, v_min, u_min, v_max},
					)
					append(&chunk.colors, ..COLOR_SIDE_X)
					quad_count += 1
				}

				// --- FACE BAS (Y - 1) ---
				if is_air(chunk, {i32(x), i32(y) - 1, i32(z)}) {
					u_min := f32(texture_coord.bottom[0]) / ATLAS_WIDTH + EPSILON
					v_min := f32(texture_coord.bottom[1]) / ATLAS_WIDTH + EPSILON
					u_max := f32(texture_coord.bottom[0] + 1) / ATLAS_WIDTH - EPSILON
					v_max := f32(texture_coord.bottom[1] + 1) / ATLAS_WIDTH - EPSILON

					append(
						&chunk.vertices,
						..[]f32 {
							fx + 0,
							fy + 0,
							fz + 0,
							fx + 1,
							fy + 0,
							fz + 0,
							fx + 1,
							fy + 0,
							fz + 1,
							fx + 0,
							fy + 0,
							fz + 1,
						},
					)
					append(
						&chunk.texcoords,
						..[]f32{u_min, v_min, u_max, v_min, u_max, v_max, u_min, v_max},
					)
					append(&chunk.colors, ..COLOR_BOTTOM)
					quad_count += 1
				}
			}
		}
	}

	for i in 0 ..< quad_count {
		v := u16(i * 4)
		append(&chunk.indices, v + 0, v + 1, v + 2, v + 0, v + 2, v + 3)
	}
}

chunk_set_block :: proc(chunk: ^Chunk, p: [3]i32, block_type: BlockType) {
	x := p[0]
	y := p[1]
	z := p[2]
	i := x + CHUNK_WIDTH * z + CHUNK_WIDTH * CHUNK_WIDTH * y
	chunk.blocks[i] = block_type
}

chunk_get_block :: proc(chunk: ^Chunk, p: [3]i32) -> BlockType {
	x := p[0]
	y := p[1]
	z := p[2]
	return chunk.blocks[x + CHUNK_WIDTH * z + CHUNK_WIDTH * CHUNK_WIDTH * y]
}

create_chunk_mesh :: proc(chunk: ^Chunk) -> rl.Mesh {
	mesh := rl.Mesh {
		vertexCount   = i32(len(chunk.vertices) / 3),
		triangleCount = i32(len(chunk.indices) / 3),
		vertices      = raw_data(chunk.vertices),
		colors        = raw_data(chunk.colors),
		texcoords     = raw_data(chunk.texcoords),
		indices       = raw_data(chunk.indices),
	}
	rl.UploadMesh(&mesh, false)
	return mesh
}


create_chunk :: proc(p: [2]i32) -> Chunk {
	chunk := Chunk {
		p = p,
	}
	for x in 0 ..< CHUNK_WIDTH {
		for z in 0 ..< CHUNK_WIDTH {
			for y in 0 ..< 10 {
				append(&chunk.blocks, BlockType.AIR)
			}
		}
	}
	return chunk
}

chunk_populate :: proc(chunk: ^Chunk) {
	for x in 0 ..< 16 {
		for z in 0 ..< 16 {
			frequency := 0.03
			world_x := i32(x) + chunk.p[0] * CHUNK_WIDTH
			world_z := i32(z) + chunk.p[1] * CHUNK_WIDTH
			val_2d := noise.noise_2d(50, {f64(world_x) * frequency, f64(world_z) * frequency})
			y := (val_2d + 1) * 0.5 * 9
			for y in 0 ..= y {
				chunk_set_block(
					chunk,
					{i32(x), i32(y), i32(z)},
					.STONE
				)
			}
		}
	}
}


delete_chunk :: proc(chunk: ^Chunk) {
	delete(chunk.vertices)
	delete(chunk.texcoords)
	delete(chunk.colors)
	delete(chunk.indices)
	delete(chunk.blocks)
}

main :: proc() {
	rl.SetConfigFlags({.MSAA_4X_HINT})
	rl.InitWindow(1280, 720, "minecrust")
	defer rl.CloseWindow()
	rl.DisableCursor()

	cam := rl.Camera3D {
		position   = {4, 3, 4},
		target     = {0, 0, 0},
		up         = {0, 1, 0},
		fovy       = 45,
		projection = .PERSPECTIVE,
	}

	texture := rl.LoadTexture("assets/atlas.png")
	rl.SetTextureFilter(texture, .POINT)
	material := rl.LoadMaterialDefault()
	material.maps[0].texture = texture
	chunks: [dynamic]Chunk
	for x in -5 ..< 5 {
		for z in -5 ..< 5 {
			append(&chunks, create_chunk({i32(x), i32(z)}))
			chunk_populate(&chunks[len(chunks) - 1])
			chunk_fill_geometry(&chunks[len(chunks) - 1])
		}
	}
	defer {
		for &chunk in chunks {
			delete_chunk(&chunk)
		}
	}

	up := false
	down := false

	vertical_velocity: f32 = 5.0
	meshs: [dynamic]rl.Mesh
	for &chunk in chunks {
		append(&meshs, create_chunk_mesh(&chunk))
	}

	defer {
		for mesh in meshs {
			rl.UnloadMesh(mesh)
		}
	}

	for !rl.WindowShouldClose() {

		delta := rl.GetFrameTime()

		if rl.IsKeyDown(.SPACE) {
			up = true
		}
		if rl.IsKeyReleased(.SPACE) {
			up = false
		}
		if rl.IsKeyDown(.LEFT_SHIFT) {
			down = true
		}
		if rl.IsKeyReleased(.LEFT_SHIFT) {
			down = false
		}
		rl.UpdateCamera(&cam, .FIRST_PERSON)

		if up {
			cam.target.y += vertical_velocity * delta
			cam.position.y += vertical_velocity * delta
		}
		if down {
			cam.target.y -= vertical_velocity * delta
			cam.position.y -= vertical_velocity * delta
		}


		rl.BeginDrawing()
		rl.ClearBackground(rl.SKYBLUE)
		rl.BeginMode3D(cam)
		rl.DrawGrid(10, 1)


		for i in 0 ..< len(chunks) {
			chunk_pos := rl.Vector3 {
				f32(chunks[i].p[0] * i32(CHUNK_WIDTH)),
				0,
				f32(chunks[i].p[1] * i32(CHUNK_WIDTH)),
			}
			transform := rl.MatrixTranslate(chunk_pos.x, chunk_pos.y, chunk_pos.z)
			rl.DrawMesh(meshs[i], material, transform)
		}

		rl.EndMode3D()
		rl.EndDrawing()
	}
}
