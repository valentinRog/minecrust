package main

import "core:math/rand"
import rl "vendor:raylib"

ATLAS_WIDTH :: 16
TEXTURE_WIDTH :: 16


BlockType :: enum {
	GRASS,
	DIRT,
	STONE,
}

BlockTextureCoord :: struct {
	top:    [2]i32,
	side:   [2]i32,
	bottom: [2]i32,
}

get_block_texture_coord :: proc(block_type: BlockType) -> BlockTextureCoord {
	switch block_type {
	case .GRASS:
		return {top = {0, 0}, side = {3, 0}, bottom = {2, 0}}
	case .DIRT:
		return {top = {2, 0}, side = {2, 0}, bottom = {2, 0}}
	case .STONE:
		return {top = {1, 0}, side = {1, 0}, bottom = {1, 0}}
	}
	unreachable()
}

Block :: struct {
	type:      BlockType,
	vertices:  [dynamic]f32,
	texcoords: [dynamic]f32,
	colors:    [dynamic]u8,
	indices:   [dynamic]u16,
	p:         [3]i32,
}

CHUNK_WIDTH := 16

Chunk :: struct {
	vertices:  [dynamic]f32,
	texcoords: [dynamic]f32,
	colors:    [dynamic]u8,
	indices:   [dynamic]u16,
	p:         [2]i32,
}

add_block_to_chunk :: proc(chunk: ^Chunk, block: Block) {
	vertex_offset := u16(len(chunk.vertices) / 3)
	append(&chunk.vertices, ..block.vertices[:])
	append(&chunk.colors, ..block.colors[:])
	append(&chunk.texcoords, ..block.texcoords[:])
	for i in block.indices {
		append(&chunk.indices, i + vertex_offset)
	}
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
	return Chunk{p = p}
}


create_block :: proc(p: [3]i32, block_type: BlockType) -> Block {
	vertices: [dynamic]f32
	texcoords: [dynamic]f32
	colors: [dynamic]u8
	indices: [dynamic]u16

	EPSILON :: 0.001

	texture_coord := get_block_texture_coord(block_type)

	// y = 1
	u_min := f32(texture_coord.top[0]) / ATLAS_WIDTH + EPSILON
	v_min := f32(texture_coord.top[1]) / ATLAS_WIDTH + EPSILON
	u_max := f32(texture_coord.top[0] + 1) / ATLAS_WIDTH - EPSILON
	v_max := f32(texture_coord.top[1] + 1) / ATLAS_WIDTH - EPSILON

	append(&vertices, ..[]f32{0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0})
	append(&texcoords, ..[]f32{u_min, v_min, u_min, v_max, u_max, v_max, u_max, v_min})
	append(
		&colors,
		..[]u8{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
	)
	append(&indices, ..[]u16{0, 1, 2, 0, 2, 3})

	u_min = f32(texture_coord.side[0]) / ATLAS_WIDTH + EPSILON
	v_min = f32(texture_coord.side[1]) / ATLAS_WIDTH + EPSILON
	u_max = f32(texture_coord.side[0] + 1) / ATLAS_WIDTH - EPSILON
	v_max = f32(texture_coord.side[1] + 1) / ATLAS_WIDTH - EPSILON

	// Z = 0
	append(&vertices, ..[]f32{0, 0, 0, 0, 1, 0, 1, 1, 0, 1, 0, 0})
	append(&texcoords, ..[]f32{u_max, v_max, u_max, v_min, u_min, v_min, u_min, v_max})
	append(
		&colors,
		..[]u8{204, 204, 204, 255, 204, 204, 204, 255, 204, 204, 204, 255, 204, 204, 204, 255},
	)
	append(&indices, ..[]u16{4, 5, 6, 4, 6, 7})

	// Z = 1
	append(&vertices, ..[]f32{0, 0, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1})
	append(&texcoords, ..[]f32{u_min, v_max, u_max, v_max, u_max, v_min, u_min, v_min})
	append(
		&colors,
		..[]u8{204, 204, 204, 255, 204, 204, 204, 255, 204, 204, 204, 255, 204, 204, 204, 255},
	)
	append(&indices, ..[]u16{8, 9, 10, 8, 10, 11})

	// X = 0
	append(&vertices, ..[]f32{0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 1, 0})
	append(&texcoords, ..[]f32{u_min, v_max, u_max, v_max, u_max, v_min, u_min, v_min})
	append(
		&colors,
		..[]u8{153, 153, 153, 255, 153, 153, 153, 255, 153, 153, 153, 255, 153, 153, 153, 255},
	)
	append(&indices, ..[]u16{12, 13, 14, 12, 14, 15})

	// X = 1
	append(&vertices, ..[]f32{1, 0, 0, 1, 1, 0, 1, 1, 1, 1, 0, 1})
	append(&texcoords, ..[]f32{u_max, v_max, u_max, v_min, u_min, v_min, u_min, v_max})
	append(
		&colors,
		..[]u8{153, 153, 153, 255, 153, 153, 153, 255, 153, 153, 153, 255, 153, 153, 153, 255},
	)
	append(&indices, ..[]u16{16, 17, 18, 16, 18, 19})

	// Y = 0
	u_min = f32(texture_coord.bottom[0]) / ATLAS_WIDTH + EPSILON
	v_min = f32(texture_coord.bottom[1]) / ATLAS_WIDTH + EPSILON
	u_max = f32(texture_coord.bottom[0] + 1) / ATLAS_WIDTH - EPSILON
	v_max = f32(texture_coord.bottom[1] + 1) / ATLAS_WIDTH - EPSILON

	append(&vertices, ..[]f32{0, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1})
	append(&texcoords, ..[]f32{u_min, v_min, u_max, v_min, u_max, v_max, u_min, v_max})
	append(
		&colors,
		..[]u8{102, 102, 102, 255, 102, 102, 102, 255, 102, 102, 102, 255, 102, 102, 102, 255},
	)
	append(&indices, ..[]u16{20, 21, 22, 20, 22, 23})

	x := p[0]
	y := p[1]
	z := p[2]
	for i in 0 ..< len(vertices) {
		if (i % 3 == 0) {
			vertices[i] += f32(x)
		} else if (i % 3 == 1) {
			vertices[i] += f32(y)
		} else if (i % 3 == 2) {
			vertices[i] += f32(z)
		}
	}

	return Block{BlockType.DIRT, vertices, texcoords, colors, indices, p}
}

delete_block :: proc(block: ^Block) {
	delete(block.vertices)
	delete(block.texcoords)
	delete(block.colors)
	delete(block.indices)
}

delete_chunk :: proc(chunk: ^Chunk) {
	delete(chunk.vertices)
	delete(chunk.texcoords)
	delete(chunk.colors)
	delete(chunk.indices)
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
	chunk := create_chunk({0, 0})
	defer delete_chunk(&chunk)

	for x in -10 ..= 10 {
		for z in -10 ..= 10 {
			y := rand.uint32() % 4
			for y in 0 ..= y {
				block := create_block({i32(x), i32(y), i32(z)}, .STONE)
				add_block_to_chunk(&chunk, block)
				delete_block(&block)
			}
		}
	}

	block := create_block({0, 1, 0}, .GRASS)
	add_block_to_chunk(&chunk, block)

	up := false
	down := false

	vertical_velocity: f32 = 5.0
	mesh := create_chunk_mesh(&chunk)
	defer rl.UnloadMesh(mesh)

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


		chunk_pos := rl.Vector3 {
			f32(chunk.p[0] * i32(CHUNK_WIDTH)),
			f32(chunk.p[1] * i32(CHUNK_WIDTH)),
			0,
		}
		transform := rl.MatrixTranslate(chunk_pos.x, chunk_pos.y, chunk_pos.z)
		rl.DrawMesh(mesh, material, transform)

		rl.EndMode3D()
		rl.EndDrawing()

	}
}
