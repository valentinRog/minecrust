package main

import "core:fmt"
import "core:math"
import "core:math/noise"
import "core:mem"
import "core:sync"
import "core:thread"
import "core:time"
import rl "vendor:raylib"

ATLAS_WIDTH :: 16
TEXTURE_WIDTH :: 16

RENDER_DISTANCE :: 10

BlockType :: enum {
	GRASS,
	DIRT,
	STONE,
	COBBLE_STONE,
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
	case .COBBLE_STONE:
		return {top = {0, 1}, side = {0, 1}, bottom = {0, 1}}
	}
	unreachable()
}

my_noise :: proc(x, z: f64) -> f64 {
	octaves := 4
	persistence := 0.5
	lacunarity := 2.0
	base_frequency := 0.008
	total: f64 = 0.0
	frequency := base_frequency
	amplitude: f64 = 1.0
	max_value: f64 = 0.0
	for i in 0 ..< octaves {
		val := noise.noise_2d(50, {x * frequency, z * frequency})
		total += f64(val) * amplitude

		max_value += amplitude
		amplitude *= persistence
		frequency *= lacunarity
	}

	return total / max_value
}

CHUNK_WIDTH :: 16
CHUNK_HEIGHT :: 30

Chunk :: struct {
	vertices:  [dynamic]f32,
	texcoords: [dynamic]f32,
	colors:    [dynamic]u8,
	indices:   [dynamic]u16,
	p:         [2]i32,
	blocks:    [dynamic]BlockType,
	mesh:      rl.Mesh,
	state:     enum {
		CREATING,
		POPULATING,
		FILLING_GEOMETRY,
		READY,
	},
}

Chunks :: struct {
	chunks:     map[[2]i32]Chunk,
	mutex:      sync.Mutex,
	is_running: bool,
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
		if pos.y < 0 || pos.y >= CHUNK_HEIGHT {
			return true
		}

		block_type := chunk_get_block(chunk, pos)
		return block_type == .AIR
	}

	quad_count := 0

	for x in 0 ..< CHUNK_WIDTH {
		for z in 0 ..< CHUNK_WIDTH {
			for y in 0 ..< CHUNK_HEIGHT {
				block_pos := [3]i32{i32(x), i32(y), i32(z)}
				block_type := chunk_get_block(chunk, block_pos)

				if block_type == .AIR do continue

				texture_coord := get_block_texture_coord(block_type)
				x, y, z := f32(x), f32(y), f32(z)

				// Y = 1
				if is_air(chunk, {i32(x), i32(y) + 1, i32(z)}) {
					u_min := f32(texture_coord.top[0]) / ATLAS_WIDTH + EPSILON
					v_min := f32(texture_coord.top[1]) / ATLAS_WIDTH + EPSILON
					u_max := f32(texture_coord.top[0] + 1) / ATLAS_WIDTH - EPSILON
					v_max := f32(texture_coord.top[1] + 1) / ATLAS_WIDTH - EPSILON

					append(
						&chunk.vertices,
						..[]f32 {
							x + 0,
							y + 1,
							z + 0,
							x + 0,
							y + 1,
							z + 1,
							x + 1,
							y + 1,
							z + 1,
							x + 1,
							y + 1,
							z + 0,
						},
					)
					append(
						&chunk.texcoords,
						..[]f32{u_min, v_min, u_min, v_max, u_max, v_max, u_max, v_min},
					)
					append(&chunk.colors, ..COLOR_TOP)
					quad_count += 1
				}

				// Z = 0
				if is_air(chunk, {i32(x), i32(y), i32(z) - 1}) {
					u_min := f32(texture_coord.side[0]) / ATLAS_WIDTH + EPSILON
					v_min := f32(texture_coord.side[1]) / ATLAS_WIDTH + EPSILON
					u_max := f32(texture_coord.side[0] + 1) / ATLAS_WIDTH - EPSILON
					v_max := f32(texture_coord.side[1] + 1) / ATLAS_WIDTH - EPSILON

					append(
						&chunk.vertices,
						..[]f32 {
							x + 0,
							y + 0,
							z + 0,
							x + 0,
							y + 1,
							z + 0,
							x + 1,
							y + 1,
							z + 0,
							x + 1,
							y + 0,
							z + 0,
						},
					)
					append(
						&chunk.texcoords,
						..[]f32{u_max, v_max, u_max, v_min, u_min, v_min, u_min, v_max},
					)
					append(&chunk.colors, ..COLOR_SIDE_Z)
					quad_count += 1
				}

				// Z = 1
				if is_air(chunk, {i32(x), i32(y), i32(z) + 1}) {
					u_min := f32(texture_coord.side[0]) / ATLAS_WIDTH + EPSILON
					v_min := f32(texture_coord.side[1]) / ATLAS_WIDTH + EPSILON
					u_max := f32(texture_coord.side[0] + 1) / ATLAS_WIDTH - EPSILON
					v_max := f32(texture_coord.side[1] + 1) / ATLAS_WIDTH - EPSILON

					append(
						&chunk.vertices,
						..[]f32 {
							x + 0,
							y + 0,
							z + 1,
							x + 1,
							y + 0,
							z + 1,
							x + 1,
							y + 1,
							z + 1,
							x + 0,
							y + 1,
							z + 1,
						},
					)
					append(
						&chunk.texcoords,
						..[]f32{u_min, v_max, u_max, v_max, u_max, v_min, u_min, v_min},
					)
					append(&chunk.colors, ..COLOR_SIDE_Z)
					quad_count += 1
				}

				// X = 0
				if is_air(chunk, {i32(x) - 1, i32(y), i32(z)}) {
					u_min := f32(texture_coord.side[0]) / ATLAS_WIDTH + EPSILON
					v_min := f32(texture_coord.side[1]) / ATLAS_WIDTH + EPSILON
					u_max := f32(texture_coord.side[0] + 1) / ATLAS_WIDTH - EPSILON
					v_max := f32(texture_coord.side[1] + 1) / ATLAS_WIDTH - EPSILON

					append(
						&chunk.vertices,
						..[]f32 {
							x + 0,
							y + 0,
							z + 0,
							x + 0,
							y + 0,
							z + 1,
							x + 0,
							y + 1,
							z + 1,
							x + 0,
							y + 1,
							z + 0,
						},
					)
					append(
						&chunk.texcoords,
						..[]f32{u_min, v_max, u_max, v_max, u_max, v_min, u_min, v_min},
					)
					append(&chunk.colors, ..COLOR_SIDE_X)
					quad_count += 1
				}

				// X = 1
				if is_air(chunk, {i32(x) + 1, i32(y), i32(z)}) {
					u_min := f32(texture_coord.side[0]) / ATLAS_WIDTH + EPSILON
					v_min := f32(texture_coord.side[1]) / ATLAS_WIDTH + EPSILON
					u_max := f32(texture_coord.side[0] + 1) / ATLAS_WIDTH - EPSILON
					v_max := f32(texture_coord.side[1] + 1) / ATLAS_WIDTH - EPSILON

					append(
						&chunk.vertices,
						..[]f32 {
							x + 1,
							y + 0,
							z + 0,
							x + 1,
							y + 1,
							z + 0,
							x + 1,
							y + 1,
							z + 1,
							x + 1,
							y + 0,
							z + 1,
						},
					)
					append(
						&chunk.texcoords,
						..[]f32{u_max, v_max, u_max, v_min, u_min, v_min, u_min, v_max},
					)
					append(&chunk.colors, ..COLOR_SIDE_X)
					quad_count += 1
				}

				// Y = 0
				if is_air(chunk, {i32(x), i32(y) - 1, i32(z)}) {
					u_min := f32(texture_coord.bottom[0]) / ATLAS_WIDTH + EPSILON
					v_min := f32(texture_coord.bottom[1]) / ATLAS_WIDTH + EPSILON
					u_max := f32(texture_coord.bottom[0] + 1) / ATLAS_WIDTH - EPSILON
					v_max := f32(texture_coord.bottom[1] + 1) / ATLAS_WIDTH - EPSILON

					append(
						&chunk.vertices,
						..[]f32 {
							x + 0,
							y + 0,
							z + 0,
							x + 1,
							y + 0,
							z + 0,
							x + 1,
							y + 0,
							z + 1,
							x + 0,
							y + 0,
							z + 1,
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

	if chunk.mesh.vaoId != 0 {
		rl.UnloadMesh(chunk.mesh)
	}

	vertex_count := len(chunk.vertices)
	texcoord_count := len(chunk.texcoords)
	color_count := len(chunk.colors)
	index_count := len(chunk.indices)

	chunk.mesh = {
		vertexCount   = i32(vertex_count / 3),
		triangleCount = i32(index_count / 3),
	}
	if vertex_count > 0 {
		size := vertex_count * size_of(f32)
		chunk.mesh.vertices = ([^]f32)(rl.MemAlloc(u32(size)))
		mem.copy(chunk.mesh.vertices, raw_data(chunk.vertices), size)
	}
	if texcoord_count > 0 {
		size := texcoord_count * size_of(f32)
		chunk.mesh.texcoords = ([^]f32)(rl.MemAlloc(u32(size)))
		mem.copy(chunk.mesh.texcoords, raw_data(chunk.texcoords), size)
	}
	if color_count > 0 {
		size := color_count * size_of(u8)
		chunk.mesh.colors = ([^]u8)(rl.MemAlloc(u32(size)))
		mem.copy(chunk.mesh.colors, raw_data(chunk.colors), size)
	}
	if index_count > 0 {
		size := index_count * size_of(u16)
		chunk.mesh.indices = ([^]u16)(rl.MemAlloc(u32(size)))
		mem.copy(chunk.mesh.indices, raw_data(chunk.indices), size)
	}

	rl.UploadMesh(&chunk.mesh, false)
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

create_chunk :: proc(chunk: ^Chunk) {
	chunk.blocks = make([dynamic]BlockType, CHUNK_WIDTH * CHUNK_WIDTH * CHUNK_HEIGHT)
	for i in 0 ..< len(chunk.blocks) {
		chunk.blocks[i] = .AIR
	}
}

chunk_populate :: proc(chunk: ^Chunk) {
	for x in 0 ..< CHUNK_WIDTH {
		for z in 0 ..< CHUNK_WIDTH {
			frequency := 0.015
			world_x := i32(x) + chunk.p[0] * CHUNK_WIDTH
			world_z := i32(z) + chunk.p[1] * CHUNK_WIDTH
			val_2d := my_noise(f64(world_x), f64(world_z))
			max_height := i32(f64((val_2d + 1) * 0.5) * f64(CHUNK_HEIGHT - 1))
			for y in 0 ..= max_height {
				chunk_set_block(chunk, {i32(x), i32(y), i32(z)}, .GRASS)
			}
		}
	}
}

delete_chunk :: proc(chunk: ^Chunk) {
	rl.UnloadMesh(chunk.mesh)
	delete(chunk.vertices)
	delete(chunk.texcoords)
	delete(chunk.colors)
	delete(chunk.indices)
	delete(chunk.blocks)
}

update_chunks :: proc(p: [2]f32, chunks: ^Chunks) {
	player_chunk := [2]i32 {
		i32(math.floor(p.x / f32(CHUNK_WIDTH))),
		i32(math.floor(p.y / f32(CHUNK_WIDTH))),
	}

	to_remove: [dynamic][2]i32
	defer delete(to_remove)

	distance_chebyshev :: proc(p1: [2]i32, p2: [2]i32) -> i32 {
		return max(abs(p1.x - p2.x), abs(p1.y - p2.y))
	}

	sync.lock(&chunks.mutex)
	for k, _ in chunks.chunks {
		if distance_chebyshev(k, player_chunk) > RENDER_DISTANCE {
			append(&to_remove, k)
		}
	}
	sync.unlock(&chunks.mutex)

	if len(to_remove) > 0 {
		sync.lock(&chunks.mutex)
		for k in to_remove {
			if k in chunks.chunks {
				chunk := &chunks.chunks[k]
				delete_chunk(chunk)
				delete_key(&chunks.chunks, k)
			}
		}
		sync.unlock(&chunks.mutex)
	}

	for x in -RENDER_DISTANCE ..= RENDER_DISTANCE {
		for z in -RENDER_DISTANCE ..= RENDER_DISTANCE {
			chunk_coord := [2]i32{player_chunk.x + i32(x), player_chunk.y + i32(z)}

			sync.lock(&chunks.mutex)
			if chunk, ok := &chunks.chunks[chunk_coord]; ok {
				// Si le thread secondaire a fini le CPU, on upload sur le GPU ici (Main Thread)
				if chunk.state == .FILLING_GEOMETRY {
					chunk_fill_geometry(chunk)
					chunk.state = .READY
				}
				sync.unlock(&chunks.mutex)
				continue
			}
			sync.unlock(&chunks.mutex)

			// Le chunk n'existe pas encore, on le crée avec sa position MONDIALE (chunk_coord)
			sync.lock(&chunks.mutex)
			chunks.chunks[chunk_coord] = Chunk {
				p     = chunk_coord, // <-- CORRIGÉ ICI (et non pas x, z relatifs)
				state = .CREATING,
			}
			sync.unlock(&chunks.mutex)
		}
	}
}

RoutineData :: struct {
	chunks: ^Chunks,
}

update_chunks_routine :: proc(t: ^thread.Thread) {
	data := (^RoutineData)(t.data).chunks
	for {
		time.sleep(5 * time.Millisecond)

		sync.lock(&data.mutex)
		// On vérifie si le jeu a demandé l'arrêt
		if !data.is_running {
			sync.unlock(&data.mutex)
			break // On sort de la boucle proprement !
		}

		for _, &chunk in data.chunks {
			#partial switch chunk.state {
			case .CREATING:
				create_chunk(&chunk)
				chunk.state = .POPULATING
			case .POPULATING:
				chunk_populate(&chunk)
				chunk.state = .FILLING_GEOMETRY
			}
		}
		sync.unlock(&data.mutex)
	}
}

main :: proc() {
	rl.SetConfigFlags({.MSAA_4X_HINT})
	rl.InitWindow(1280, 720, "minecrust")
	defer rl.CloseWindow()
	rl.DisableCursor()

	cam := rl.Camera3D {
		position   = {4, 15, 4},
		target     = {0, 0, 0},
		up         = {0, 1, 0},
		fovy       = 45,
		projection = .PERSPECTIVE,
	}

	texture := rl.LoadTexture("assets/atlas.png")
	defer rl.UnloadTexture(texture)
	rl.SetTextureFilter(texture, .POINT)

	material := rl.LoadMaterialDefault()
	material.maps[0].texture = texture

	chunks: Chunks
	chunks.is_running = true
	defer {
		sync.lock(&chunks.mutex)
		for _, &chunk in chunks.chunks {
			delete_chunk(&chunk)
		}
		delete(chunks.chunks)
		sync.unlock(&chunks.mutex)
	}

	up := false
	down := false
	vertical_velocity: f32 = 10.0

	routine_data := RoutineData {
		chunks = &chunks,
	}
	t := thread.create(update_chunks_routine)
	t.data = &routine_data // Utilisation correcte de user_data
	thread.start(t)
	defer {
		sync.lock(&chunks.mutex)
		chunks.is_running = false
		sync.unlock(&chunks.mutex)

		thread.join(t)
		thread.destroy(t)

		sync.lock(&chunks.mutex)
		for _, &chunk in chunks.chunks {
			delete_chunk(&chunk)
		}
		delete(chunks.chunks)
		sync.unlock(&chunks.mutex)
	}

	for !rl.WindowShouldClose() {
		delta := rl.GetFrameTime()

		update_chunks({cam.position.x, cam.position.z}, &chunks)

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

		// Lecture sécurisée des meshes pour le dessin
		sync.lock(&chunks.mutex)
		for _, chunk in chunks.chunks {
			if chunk.state == .READY {
				chunk_pos := rl.Vector3 {
					f32(chunk.p[0] * CHUNK_WIDTH),
					0,
					f32(chunk.p[1] * CHUNK_WIDTH),
				}
				transform := rl.MatrixTranslate(chunk_pos.x, chunk_pos.y, chunk_pos.z)
				rl.DrawMesh(chunk.mesh, material, transform)
			}
		}
		sync.unlock(&chunks.mutex)

		rl.EndMode3D()
		rl.DrawText(fmt.ctprintf("FPS: %d", rl.GetFPS()), 10, 10, 20, rl.WHITE)
		free_all(context.temp_allocator)
		rl.EndDrawing()
	}
}
