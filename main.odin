package main

import "core:fmt"
import "core:math"
import "core:math/noise"
import "core:mem"
import "core:os"
import "core:sync"
import "core:thread"
import "core:time"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

ATLAS_WIDTH :: 16
TEXTURE_WIDTH :: 16

RENDER_DISTANCE :: 16

WATER_LEVEL :: 12

BlockType :: enum {
	GRASS,
	DIRT,
	SAND,
	STONE,
	COBBLE_STONE,
	WATER,
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
	case .SAND:
		return {top = {0, 11}, side = {0, 11}, bottom = {0, 11}}
	case .STONE:
		return {top = {1, 0}, side = {1, 0}, bottom = {1, 0}}
	case .COBBLE_STONE:
		return {top = {0, 1}, side = {0, 1}, bottom = {0, 1}}
	case .WATER:
		return {top = {13, 12}, side = {13, 12}, bottom = {13, 12}}
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

ChunkState :: enum {
	CREATING,
	POPULATING,
	UPLOADING,
	READY,
}

Chunk :: struct {
	vertices:        [dynamic]f32,
	texcoords:       [dynamic]f32,
	colors:          [dynamic]u8,
	indices:         [dynamic]u16,
	water_vertices:  [dynamic]f32,
	water_texcoords: [dynamic]f32,
	water_colors:    [dynamic]u8,
	water_indices:   [dynamic]u16,
	p:               [2]i32,
	blocks:          [dynamic]BlockType,
	mesh:            rl.Mesh,
	water_mesh:      rl.Mesh,
	state:           ChunkState,
	claimed:         bool,
}

Chunks :: struct {
	chunks:     map[[2]i32]^Chunk,
	mutex:      sync.Mutex,
	is_running: bool,
}

get_grayscale_array :: proc(percent: f32) -> [16]u8 {
	p := math.clamp(percent, 0.0, 100.0)
	v := u8(p / 100.0 * 255.0)
	return [16]u8{v, v, v, 255, v, v, v, 255, v, v, v, 255, v, v, v, 255}
}

build_mesh :: proc(mesh: ^rl.Mesh, verts: []f32, texs: []f32, cols: []u8, idxs: []u16) {
	rl.UnloadMesh(mesh^)
	mesh^ = {}

	vertex_count := len(verts)
	if vertex_count == 0 do return

	texcoord_count := len(texs)
	color_count := len(cols)
	index_count := len(idxs)

	mesh.vertexCount = i32(vertex_count / 3)
	mesh.triangleCount = i32(index_count / 3)

	size := vertex_count * size_of(f32)
	mesh.vertices = ([^]f32)(rl.MemAlloc(u32(size)))
	mem.copy(mesh.vertices, raw_data(verts), size)

	if texcoord_count > 0 {
		size = texcoord_count * size_of(f32)
		mesh.texcoords = ([^]f32)(rl.MemAlloc(u32(size)))
		mem.copy(mesh.texcoords, raw_data(texs), size)
	}
	if color_count > 0 {
		size = color_count * size_of(u8)
		mesh.colors = ([^]u8)(rl.MemAlloc(u32(size)))
		mem.copy(mesh.colors, raw_data(cols), size)
	}
	if index_count > 0 {
		size = index_count * size_of(u16)
		mesh.indices = ([^]u16)(rl.MemAlloc(u32(size)))
		mem.copy(mesh.indices, raw_data(idxs), size)
	}
}

chunk_fill_geometry :: proc(chunk: ^Chunk) {
	clear(&chunk.vertices)
	clear(&chunk.texcoords)
	clear(&chunk.colors)
	clear(&chunk.indices)

	clear(&chunk.water_vertices)
	clear(&chunk.water_texcoords)
	clear(&chunk.water_colors)
	clear(&chunk.water_indices)

	EPSILON :: 0.005

	COLOR_TOP := get_grayscale_array(100)
	COLOR_SIDE_Z := get_grayscale_array(80)
	COLOR_SIDE_X := get_grayscale_array(60)
	COLOR_BOTTOM := get_grayscale_array(40)

	should_draw_face :: proc(chunk: ^Chunk, current: BlockType, npos: [3]i32) -> bool {
		if npos.x < 0 ||
		   npos.x >= CHUNK_WIDTH ||
		   npos.z < 0 ||
		   npos.z >= CHUNK_WIDTH ||
		   npos.y < 0 ||
		   npos.y >= CHUNK_HEIGHT {
			return true
		}
		neighbor := chunk_get_block(chunk, npos)
		if current == .WATER do return neighbor == .AIR
		return neighbor == .AIR || neighbor == .WATER
	}

	quad_count := 0
	water_quad_count := 0

	for x in 0 ..< CHUNK_WIDTH {
		for z in 0 ..< CHUNK_WIDTH {
			for y in 0 ..< CHUNK_HEIGHT {
				block_pos := [3]i32{i32(x), i32(y), i32(z)}
				block_type := chunk_get_block(chunk, block_pos)

				if block_type == .AIR do continue

				is_water := block_type == .WATER

				vertices: ^[dynamic]f32
				texcoords: ^[dynamic]f32
				colors: ^[dynamic]u8
				quad_counter: ^int

				if is_water {
					vertices = &chunk.water_vertices
					texcoords = &chunk.water_texcoords
					colors = &chunk.water_colors
					quad_counter = &water_quad_count
				} else {
					vertices = &chunk.vertices
					texcoords = &chunk.texcoords
					colors = &chunk.colors
					quad_counter = &quad_count
				}

				texture_coord := get_block_texture_coord(block_type)
				x, y, z := f32(x), f32(y), f32(z)

				Face :: struct {
					vertices: [4][3]f32,
					uv:       [4][2]f32,
					tex:      enum {
						TOP,
						SIDE,
						BOTTOM,
					},
					dir:      [3]i32,
				}

				faces := []Face {
					// Y = 1 (top)
					{
						vertices = {{0, 1, 0}, {0, 1, 1}, {1, 1, 1}, {1, 1, 0}},
						uv = {{0, 0}, {0, 1}, {1, 1}, {1, 0}},
						tex = .TOP,
						dir = {0, 1, 0},
					},
					// Y = 0 (bottom)
					{
						vertices = {{0, 0, 0}, {1, 0, 0}, {1, 0, 1}, {0, 0, 1}},
						uv = {{0, 0}, {1, 0}, {1, 1}, {0, 1}},
						tex = .BOTTOM,
						dir = {0, -1, 0},
					},
					// Z = 0
					{
						vertices = {{0, 0, 0}, {0, 1, 0}, {1, 1, 0}, {1, 0, 0}},
						uv = {{1, 1}, {1, 0}, {0, 0}, {0, 1}},
						tex = .SIDE,
						dir = {0, 0, -1},
					},
					// Z = 1
					{
						vertices = {{0, 0, 1}, {1, 0, 1}, {1, 1, 1}, {0, 1, 1}},
						uv = {{0, 1}, {1, 1}, {1, 0}, {0, 0}},
						tex = .SIDE,
						dir = {0, 0, 1},
					},
					// X = 0
					{
						vertices = {{0, 0, 0}, {0, 0, 1}, {0, 1, 1}, {0, 1, 0}},
						uv = {{0, 1}, {1, 1}, {1, 0}, {0, 0}},
						tex = .SIDE,
						dir = {-1, 0, 0},
					},
					// X = 1
					{
						vertices = {{1, 0, 0}, {1, 1, 0}, {1, 1, 1}, {1, 0, 1}},
						uv = {{1, 1}, {1, 0}, {0, 0}, {0, 1}},
						tex = .SIDE,
						dir = {1, 0, 0},
					},
				}

				for face in faces {
					npos := block_pos + face.dir
					if !should_draw_face(chunk, block_type, npos) do continue
					tex_coord: [2]i32
					switch face.tex {
					case .TOP:
						tex_coord = texture_coord.top
					case .SIDE:
						tex_coord = texture_coord.side
					case .BOTTOM:
						tex_coord = texture_coord.bottom
					}
					if face.tex != .TOP && block_type == .WATER do continue
					u_min := f32(tex_coord[0]) / ATLAS_WIDTH + EPSILON
					v_min := f32(tex_coord[1]) / ATLAS_WIDTH + EPSILON
					u_max := f32(tex_coord[0] + 1) / ATLAS_WIDTH - EPSILON
					v_max := f32(tex_coord[1] + 1) / ATLAS_WIDTH - EPSILON
					for v, i in face.vertices {
						append(vertices, x + v[0], y + v[1], z + v[2])
						u := u_min + face.uv[i][0] * (u_max - u_min)
						w := v_min + face.uv[i][1] * (v_max - v_min)
						append(texcoords, u, w)
					}
					color: [16]u8
					switch face.tex {
					case .TOP:
						color = COLOR_TOP
					case .BOTTOM:
						color = COLOR_BOTTOM
					case .SIDE:
						if face.dir[0] != 0 {
							color = COLOR_SIDE_X
						} else {
							color = COLOR_SIDE_Z
						}
					}
					append(colors, ..color[:])

					quad_counter^ += 1
				}
			}
		}
	}

	for i in 0 ..< quad_count {
		v := u16(i * 4)
		append(&chunk.indices, v + 0, v + 1, v + 2, v + 0, v + 2, v + 3)
	}
	for i in 0 ..< water_quad_count {
		v := u16(i * 4)
		append(&chunk.water_indices, v + 0, v + 1, v + 2, v + 0, v + 2, v + 3)
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

create_chunk :: proc(chunk: ^Chunk) {
	chunk.blocks = make([dynamic]BlockType, CHUNK_WIDTH * CHUNK_WIDTH * CHUNK_HEIGHT)
	for i in 0 ..< len(chunk.blocks) {
		chunk.blocks[i] = .AIR
	}
}

chunk_populate :: proc(chunk: ^Chunk) {
	for x in 0 ..< CHUNK_WIDTH {
		for z in 0 ..< CHUNK_WIDTH {
			world_x := i32(x) + chunk.p[0] * CHUNK_WIDTH
			world_z := i32(z) + chunk.p[1] * CHUNK_WIDTH
			val_2d := my_noise(f64(world_x), f64(world_z))
			max_height := i32(f64((val_2d + 1) * 0.5) * f64(CHUNK_HEIGHT - 1))
			for y in 0 ..= max_height {
				block := BlockType.GRASS
				if y <= WATER_LEVEL do block = .SAND
				chunk_set_block(chunk, {i32(x), i32(y), i32(z)}, block)
			}
			for y in max_height + 1 ..< WATER_LEVEL {
				chunk_set_block(chunk, {i32(x), i32(y), i32(z)}, .WATER)
			}
		}
	}
}

delete_chunk :: proc(chunk: ^Chunk) {
	rl.UnloadMesh(chunk.mesh)
	rl.UnloadMesh(chunk.water_mesh)
	delete(chunk.vertices)
	delete(chunk.texcoords)
	delete(chunk.colors)
	delete(chunk.indices)
	delete(chunk.water_vertices)
	delete(chunk.water_texcoords)
	delete(chunk.water_colors)
	delete(chunk.water_indices)
	delete(chunk.blocks)
	free(chunk)
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
	for k, chunk in chunks.chunks {
		if distance_chebyshev(k, player_chunk) > RENDER_DISTANCE {
			if !chunk.claimed {
				append(&to_remove, k)
			}
		}
	}
	sync.unlock(&chunks.mutex)

	if len(to_remove) > 0 {
		sync.lock(&chunks.mutex)
		for k in to_remove {
			if chunk, ok := chunks.chunks[k]; ok {
				if chunk.claimed do continue
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
			if chunk, ok := chunks.chunks[chunk_coord]; ok {
				if chunk.state == .UPLOADING && !chunk.claimed {
					chunk.claimed = true
					sync.unlock(&chunks.mutex)

					build_mesh(
						&chunk.mesh,
						chunk.vertices[:],
						chunk.texcoords[:],
						chunk.colors[:],
						chunk.indices[:],
					)
					build_mesh(
						&chunk.water_mesh,
						chunk.water_vertices[:],
						chunk.water_texcoords[:],
						chunk.water_colors[:],
						chunk.water_indices[:],
					)
					rl.UploadMesh(&chunk.mesh, false)
					rl.UploadMesh(&chunk.water_mesh, false)

					sync.lock(&chunks.mutex)
					chunk.state = .READY
					chunk.claimed = false
				}
				sync.unlock(&chunks.mutex)
				continue
			}

			chunk := new(Chunk)
			chunk^ = Chunk {
				p     = chunk_coord,
				state = .CREATING,
			}
			chunks.chunks[chunk_coord] = chunk
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
		sync.lock(&data.mutex)
		if !data.is_running {
			sync.unlock(&data.mutex)
			break
		}

		target: ^Chunk = nil
		action: enum {
			NONE,
			CREATE,
			POPULATE,
		}

		for _, chunk in data.chunks {
			#partial switch chunk.state {
			case .CREATING:
				target = chunk
				action = .CREATE
			case .POPULATING:
				target = chunk
				action = .POPULATE
			}
			if target != nil do break
		}

		if target != nil do target.claimed = true

		sync.unlock(&data.mutex)

		if target == nil {
			time.sleep(2 * time.Millisecond)
			continue
		}

		switch action {
		case .CREATE:
			create_chunk(target)
		case .POPULATE:
			chunk_populate(target)
			chunk_fill_geometry(target)
		case .NONE:
		}

		sync.lock(&data.mutex)
		switch action {
		case .CREATE:
			target.state = .POPULATING
		case .POPULATE:
			target.state = .UPLOADING
		case .NONE:
		}
		target.claimed = false
		sync.unlock(&data.mutex)
	}
}

main :: proc() {
	os.set_env("LP_NUM_THREADS", "0")
	rl.SetConfigFlags({.MSAA_4X_HINT})
	rl.InitWindow(1600, 900, "minecrust")
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
	default_texture := material.maps[0].texture
	material.maps[0].texture = texture
	defer {
		material.maps[0].texture = default_texture
		rl.UnloadMaterial(material)
	}

	chunks: Chunks
	chunks.is_running = true

	up := false
	down := false
	vertical_velocity: f32 = 10.0

	routine_data := RoutineData {
		chunks = &chunks,
	}
	t := thread.create(update_chunks_routine)
	t.data = &routine_data
	thread.start(t)
	defer {
		sync.lock(&chunks.mutex)
		chunks.is_running = false
		sync.unlock(&chunks.mutex)

		thread.join(t)
		thread.destroy(t)

		sync.lock(&chunks.mutex)
		for _, chunk in chunks.chunks {
			delete_chunk(chunk)
		}
		delete(chunks.chunks)
		sync.unlock(&chunks.mutex)
	}

	for !rl.WindowShouldClose() {
		delta := rl.GetFrameTime()

		update_chunks({cam.position.x, cam.position.z}, &chunks)

		if rl.IsKeyDown(.SPACE) do up = true
		if rl.IsKeyReleased(.SPACE) do up = false
		if rl.IsKeyDown(.LEFT_SHIFT) do down = true
		if rl.IsKeyReleased(.LEFT_SHIFT) do down = false

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

		sync.lock(&chunks.mutex)
		for _, chunk in chunks.chunks {
			if chunk.state != .READY do continue
			chunk_pos := rl.Vector3 {
				f32(chunk.p[0] * CHUNK_WIDTH),
				0,
				f32(chunk.p[1] * CHUNK_WIDTH),
			}
			transform := rl.MatrixTranslate(chunk_pos.x, chunk_pos.y, chunk_pos.z)
			rl.DrawMesh(chunk.mesh, material, transform)
		}
		sync.unlock(&chunks.mutex)

		rlgl.DisableDepthMask()
		sync.lock(&chunks.mutex)
		for _, chunk in chunks.chunks {
			if chunk.state != .READY do continue
			chunk_pos := rl.Vector3 {
				f32(chunk.p[0] * CHUNK_WIDTH),
				0,
				f32(chunk.p[1] * CHUNK_WIDTH),
			}
			transform := rl.MatrixTranslate(chunk_pos.x, chunk_pos.y, chunk_pos.z)
			rl.DrawMesh(chunk.water_mesh, material, transform)
		}
		sync.unlock(&chunks.mutex)
		rlgl.EnableDepthMask()

		rl.EndMode3D()
		rl.DrawText(fmt.ctprintf("FPS: %d", rl.GetFPS()), 10, 10, 20, rl.WHITE)
		free_all(context.temp_allocator)
		rl.EndDrawing()
	}
}
