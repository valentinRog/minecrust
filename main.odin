package main

import rl "vendor:raylib"

atlas_width :: 16
texture_width :: 16

Block :: struct {
	vertices:  [dynamic]f32,
	texcoords: [dynamic]f32,
	indices:   [dynamic]u16,
	p:         [3]i32,
}

Chunk :: struct {
	vertices:  [dynamic]f32,
	texcoords: [dynamic]f32,
	indices:   [dynamic]u16,
	p:         [3]i32,
}

add_block_to_chunk :: proc(chunk: ^Chunk, block: Block) {
	vertex_offset := u16(len(chunk.vertices) / 3)
	append(&chunk.vertices, ..block.vertices[:])
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
		texcoords     = raw_data(chunk.texcoords),
		indices       = raw_data(chunk.indices),
	}
	rl.UploadMesh(&mesh, false)
	return mesh
}


create_chunk :: proc(p: [3]i32) -> Chunk {
	vertices: [dynamic]f32
	texcoords: [dynamic]f32
	indices: [dynamic]u16

	return Chunk{vertices, texcoords, indices, p}
}


create_block :: proc(p: [3]i32, texture_coord: struct {
		top:    [2]i32,
		side:   [2]i32,
		bottom: [2]i32,
	}) -> Block {
	vertices: [dynamic]f32
	texcoords: [dynamic]f32
	indices: [dynamic]u16

	atlas_tiles_x :: 16
	atlas_tiles_y :: 16

	u_min := f32(texture_coord.side[0]) / texture_width
	v_min := f32(texture_coord.side[1]) / f32(texture_width)
	u_max := f32(texture_coord.side[0] + 1) / f32(texture_width)
	v_max := f32(texture_coord.side[1] + 1) / f32(texture_width)
	append(&vertices, ..[]f32{0, 0, 0, 0, 1, 0, 1, 1, 0, 1, 0, 0})
	append(&texcoords, ..[]f32{u_min, v_min, u_min, v_max, u_max, v_max, u_max, v_min})
	append(&indices, ..[]u16{0, 1, 2, 0, 2, 3})
	
	
	u_min = f32(texture_coord.side[0]) / texture_width
	v_min = f32(texture_coord.side[1]) / f32(texture_width)
	u_max = f32(texture_coord.side[0] + 1) / f32(texture_width)
	v_max = f32(texture_coord.side[1] + 1) / f32(texture_width)
	append(&vertices, ..[]f32{0, 0, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1})
	append(&texcoords, ..[]f32{u_min, v_min, u_min, v_max, u_max, v_max, u_max, v_min})
	append(&indices, ..[]u16{0 + 4, 1 + 4, 2 + 4, 0 + 4, 2 + 4, 3 + 4})
	
	u_min = f32(texture_coord.top[0]) / texture_width
	v_min = f32(texture_coord.top[1]) / f32(texture_width)
	u_max = f32(texture_coord.top[0] + 1) / f32(texture_width)
	v_max = f32(texture_coord.top[1] + 1) / f32(texture_width)
	append(&vertices, ..[]f32{0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0})
	append(&texcoords, ..[]f32{u_min, v_min, u_min, v_max, u_max, v_max, u_max, v_min})
	append(&indices, ..[]u16{0 + 8, 1 + 8, 2 + 8, 0 + 8, 2 + 8, 3 + 8})
	
	u_min = f32(texture_coord.side[0]) / texture_width
	v_min = f32(texture_coord.side[1]) / f32(texture_width)
	u_max = f32(texture_coord.side[0] + 1) / f32(texture_width)
	v_max = f32(texture_coord.side[1] + 1) / f32(texture_width)
	append(&vertices, ..[]f32{0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 1, 0})
	append(&texcoords, ..[]f32{u_min, v_min, u_min, v_max, u_max, v_max, u_max, v_min})
	append(&indices, ..[]u16{0 + 12, 1 + 12, 2 + 12, 0 + 12, 2 + 12, 3 + 12})
	
	u_min = f32(texture_coord.side[0]) / texture_width
	v_min = f32(texture_coord.side[1]) / f32(texture_width)
	u_max = f32(texture_coord.side[0] + 1) / f32(texture_width)
	v_max = f32(texture_coord.side[1] + 1) / f32(texture_width)
	append(&vertices, ..[]f32{1, 0, 0, 1, 1, 0, 1, 1, 1, 1, 0, 1})
	append(&texcoords, ..[]f32{u_min, v_min, u_min, v_max, u_max, v_max, u_max, v_min})
	append(&indices, ..[]u16{0 + 16, 1 + 16, 2 + 16, 0 + 16, 2 + 16, 3 + 16})

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

	return Block{vertices, texcoords, indices, p}
}

delete_block :: proc(block: ^Block) {
	delete(block.vertices)
	delete(block.texcoords)
	delete(block.indices)
}

delete_chunk :: proc(chunk: ^Chunk) {
	delete(chunk.vertices)
	delete(chunk.texcoords)
	delete(chunk.indices)
}

main :: proc() {
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
	chunk := create_chunk({0, 0, 0})
	defer delete_chunk(&chunk)

	for x in 0 ..< 10 {
		for z in 0 ..< 10 {
			block := create_block(
				{i32(x), 0, i32(z)},
				{top = {0, 0}, side = {4, 0}, bottom = {0, 0}},
			)
			add_block_to_chunk(&chunk, block)
			delete_block(&block)
		}
	}

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


		rl.DrawMesh(mesh, material, rl.Matrix(1))

		rl.EndMode3D()
		rl.EndDrawing()

	}
}
