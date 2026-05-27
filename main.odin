package odin_test;

import "core:math"
import "core:math/rand"
import "core:fmt"
import "core:mem"

import openGL "vendor:OpenGL"
import glfw "vendor:glfw" 
import stbImage "vendor:stb/image"
import raylib "vendor:raylib"

Color :: struct { r, g, b: u8 }

State :: struct
{
	mouseX, mouseY: f32,
	width, height: i32,
	aspect: f32
}

VERTEX_SHADER :: `
#version 460 core
out vec2 uv;
void main() 
{
	vec2 positions[3] = vec2[3](
		vec2(-1.0, -1.0),
		vec2(3.0, -1.0),
		vec2(-1.0, 3.0)
	);

	gl_Position = vec4(positions[gl_VertexID], 0.0, 1.0);
	uv = positions[gl_VertexID] * 0.5 + 0.5;
}
`
FRAGMENT_SHADER :: `
#version 460 core
in vec2 uv;
out vec4 FragColor;
uniform sampler2D tex;

void main()
{
	FragColor = texture(tex, uv);
}
`

RawDataToColorArray :: proc(rawData: [^]u8, width: u32, height: u32) -> [dynamic]Color
{
	colors: [dynamic]Color;

	for i: u32 = 0; i < (width * height * 3); i += 3
	{
		color: Color = { rawData[i], rawData[i + 1], rawData[i + 2] };
		append(&colors, color);
	}

	return colors;
}

OnCursorPosChange :: proc "c" (window: glfw.WindowHandle, x, y: f64)
{
	state := cast(^State)glfw.GetWindowUserPointer(window);

	state.mouseX = (f32(x) / f32(state.width) * 2.0 - 1.0) * state.aspect;
	state.mouseY = 1.0 - f32(y) / f32(state.height) * 2.0;
}

CreateTexture :: proc(data: [dynamic]Color, width, height: i32) -> u32
{
	texture: u32;
	
	openGL.GenTextures(1, &texture);
	openGL.BindTexture(openGL.TEXTURE_2D, texture);
	openGL.TexParameteri(openGL.TEXTURE_2D, openGL.TEXTURE_MIN_FILTER, openGL.LINEAR);
	openGL.TexParameteri(openGL.TEXTURE_2D, openGL.TEXTURE_MAG_FILTER, openGL.LINEAR);

	openGL.TexImage2D(openGL.TEXTURE_2D, 0, openGL.RGB, width, height,
		0, openGL.RGB, openGL.UNSIGNED_BYTE, mem.raw_data(data));

	return texture;
}

CompileShader :: proc(source: string, shaderType: u32) -> u32
{
	shader := openGL.CreateShader(shaderType);
	src := cstring(raw_data(source));
	openGL.ShaderSource(shader, 1, &src, nil);
	openGL.CompileShader(shader);

	return shader;
}

CreateProgram :: proc() -> u32
{
	vert := CompileShader(VERTEX_SHADER, openGL.VERTEX_SHADER);
	frag := CompileShader(FRAGMENT_SHADER, openGL.FRAGMENT_SHADER);
	program := openGL.CreateProgram();
	openGL.AttachShader(program, vert);
	openGL.AttachShader(program, frag);
	openGL.LinkProgram(program);
	openGL.DeleteShader(vert);
	openGL.DeleteShader(frag);

	return program;
}

GetZ :: proc(x, y, radius: f32) -> f32
{
	return math.sqrt(radius * radius - x * x - y * y);
}

DerX :: proc(x, y, radius: f32) -> f32
{
	return -x / math.sqrt(radius * radius - x * x - y * y);
}

DerY :: proc(x, y, radius: f32) -> f32
{
	return -y / math.sqrt(radius * radius - x * x - y * y);
}

main :: proc()
{
	state: State;
	channels: i32;
	
	stbImage.set_flip_vertically_on_load(1);
	rawData := stbImage.load("city.jpg", &state.width, &state.height, &channels, 3);

	if rawData == nil
	{
		fmt.println("Image failed to load:", stbImage.failure_reason());
		return;
	}

	data := RawDataToColorArray(rawData, auto_cast(state.width), auto_cast(state.height));
	state.aspect = f32(state.width) / f32(state.height);
	
	if !glfw.Init()
	{
		fmt.println("GLFW failed to initialize.");
		return;
	}
	defer glfw.Terminate();

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4);
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 6);
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE);
	glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE);

	window := glfw.CreateWindow(state.width, state.height, "Odin Test", nil, nil);
	defer glfw.DestroyWindow(window);

	glfw.MakeContextCurrent(window);
	glfw.SwapInterval(1);
	glfw.SetWindowUserPointer(window, &state);
	glfw.SetCursorPosCallback(window, OnCursorPosChange);

	openGL.load_up_to(4, 6, glfw.gl_set_proc_address);
	openGL.Viewport(0, 0, state.width, state.height);
	openGL.ClearColor(0, 0, 0, 1);

	texture := CreateTexture(data, state.width, state.height);
	program := CreateProgram();
	
	vao: u32;
	openGL.GenVertexArrays(1, &vao);
	openGL.BindVertexArray(vao);
	openGL.UseProgram(program);
	openGL.Uniform1i(openGL.GetUniformLocation(program, "tex"), 0);

	RADIUS :: f32(0.5);
	IN_OF_REF :: f32(1.5);
	MU :: 1.0 / IN_OF_REF;

	for !glfw.WindowShouldClose(window)
	{
		glfw.PollEvents();
		
		mem.copy(mem.raw_data(data), rawData, auto_cast(state.width * state.height * 3));

		for y: u32 = 0; y < u32(state.height); y += 1
		{
			for x: u32 = 0; x < u32(state.width); x += 1
			{
				index := y * u32(state.width) + x;
				normX := (f32(x) / f32(state.width) * 2.0 - 1.0) * state.aspect;
				normY := f32(y) / f32(state.height) * 2.0 - 1.0;

				if (normX - state.mouseX) * (normX - state.mouseX) +
					(normY - state.mouseY) * (normY - state.mouseY) <= RADIUS * RADIUS
				{
					lx := normX - state.mouseX;
					ly := normY - state.mouseY;

					z := GetZ(lx, ly, RADIUS);

					i := raylib.Vector3 { 0.0, 0.0, -1.0 };
					n := raylib.Vector3Normalize(raylib.Vector3CrossProduct(
						raylib.Vector3{ 0.0, 1.0, DerY(lx, ly, RADIUS)},
						raylib.Vector3{ 1.0, 0.0, DerX(lx, ly, RADIUS)}));
				
					dotNI := raylib.Vector3DotProduct(n, i);

					tr := math.sqrt(1.0 - MU * MU * (1.0 - dotNI * dotNI)) * n + MU * (i - dotNI * n);
					t := -z / tr.z;
					
					hitX := lx + state.mouseX + t * tr.x;
					hitY := ly + state.mouseY + t * tr.y;

					px := u32(((hitX / state.aspect) + 1.0) * 0.5 * f32(state.width));
					py := u32((hitY + 1.0) * 0.5 * f32(state.height));

					srcIndex := py * u32(state.width) + px;
					r := rawData[srcIndex * 3];
					g := rawData[srcIndex * 3 + 1];
					b := rawData[srcIndex * 3 + 2];

					data[index] = { r, g, b };
				}
			}
		}

		openGL.Clear(openGL.COLOR_BUFFER_BIT);
		openGL.TexSubImage2D(openGL.TEXTURE_2D, 0, 0, 0, state.width, state.height,
			openGL.RGB, openGL.UNSIGNED_BYTE, mem.raw_data(data));

		openGL.ActiveTexture(openGL.TEXTURE0);
		openGL.BindTexture(openGL.TEXTURE_2D, texture);
		openGL.DrawArrays(openGL.TRIANGLES, 0, 3);

		glfw.SwapBuffers(window);
	}
}

