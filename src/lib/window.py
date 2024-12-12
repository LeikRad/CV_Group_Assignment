import pygame as pg
from pygame.locals import *
import numpy as np
from OpenGL.GL import *
from OpenGL.GL.shaders import compileProgram, compileShader

from .shape import Shape

WEBSOCKET_HOST = "localhost"
WEBSOCKET_PORT = 8765

# Define the red sphere properties
shapes = [
    Shape(
        position=np.array([0.0, 0.0, 0.0], dtype=np.float32),
        size=np.array([1.0, 1.0, 1.0], dtype=np.float32),
        colour=np.array([1.0, 0.0, 0.0], dtype=np.float32),
        shapeType=0,
        operation=0,
        blendStrength=1.0,
        numChildren=0,
    )
    for _ in range(10)
]

shapes_block = np.array(
    [
        (
            shape.position,
            0.0,  # Padding to align to 16 bytes
            shape.size,
            0.0,  # Padding to align to 16 bytes
            shape.colour,
            0.0,  # Padding to align to 16 bytes
            shape.shapeType,
            shape.operation,
            shape.blendStrength,
            shape.numChildren,
        )
        for shape in shapes
    ],
    dtype=[
        ("position", np.float32, 3),
        ("_pad1", np.float32),  # Padding to align to 16 bytes
        ("size", np.float32, 3),
        ("_pad2", np.float32),  # Padding to align to 16 bytes
        ("colour", np.float32, 3),
        ("_pad3", np.float32),  # Padding to align to 16 bytes
        ("shapeType", np.int32),
        ("operation", np.int32),
        ("blendStrength", np.float32),
        ("numChildren", np.int32),
    ],
)


class Window:

    def __init__(
        self, width: int = 1280, height: int = 800, fps: int = 60, renderer: int = 0
    ) -> None:
        self.width = width
        self.height = height
        self.screen = None
        self.max_fps = fps
        self.running = False
        self.renderer = renderer
        self.clock = pg.time.Clock()
        self.program = None

        # Shader stuff
        self.resolution_location = None
        self.numShapes = 0
        self.shapesNumber_location = None

        # Camera stuff
        self.camera_position = [0.0, 1.0, 0.0]  # Posição inicial da câmera
        self.camera_rotation = [0.0, 0.0]  # [pitch, yaw]
        self.mouse_sensitivity = 0.005
        self.center_mouse = True

        # Blending strength (thread-safe)
        self.blend_strength = 2.0

    def create_window(self) -> None:
        pg.init()
        pg.display.gl_set_attribute(pg.GL_CONTEXT_MAJOR_VERSION, 3)
        pg.display.gl_set_attribute(pg.GL_CONTEXT_MINOR_VERSION, 3)
        pg.display.gl_set_attribute(
            pg.GL_CONTEXT_PROFILE_MASK, pg.GL_CONTEXT_PROFILE_CORE
        )

        self.screen = pg.display.set_mode(
            (self.width, self.height), OPENGL | DOUBLEBUF | RESIZABLE
        )
        self._shader_init()
        pg.mouse.set_visible(False)

        pg.event.set_grab(True)
        pg.mouse.set_visible(False)
        pg.mouse.get_rel()  # Reseta o deslocamento inicial

    def _shader_init(self):
        # Locations
        vertex_shader_source = self._read_shader("glsl/vertex_shader.glsl")
        fragment_shader_source = self._read_shader("glsl/fragment_shader.glsl")

        # Compile shaders
        vertex_shader = compileShader(vertex_shader_source, GL_VERTEX_SHADER)
        fragment_shader = compileShader(fragment_shader_source, GL_FRAGMENT_SHADER)

        # Create and bind a VAO for validation
        VAO = glGenVertexArrays(1)
        glBindVertexArray(VAO)

        # Compile the shader program
        self.program = compileProgram(vertex_shader, fragment_shader)

        # Unbind the VAO after validation
        glBindVertexArray(0)

        glUseProgram(self.program)

        # Variable locations and first-time setting
        self.resolution_location = glGetUniformLocation(self.program, "u_resolution")
        glUniform2f(self.resolution_location, self.width, self.height)
        self.camera_position_location = glGetUniformLocation(
            self.program, "u_camera_position"
        )
        glUniform3f(self.camera_position_location, *self.camera_position)
        self.camera_rotation_location = glGetUniformLocation(
            self.program, "u_camera_rotation"
        )
        glUniform2f(self.camera_rotation_location, *self.camera_rotation)
        self.time_location = glGetUniformLocation(self.program, "u_time")
        self.blend_strength_location = glGetUniformLocation(
            self.program, "u_blend_strength"
        )

        self.shapesNumber_location = glGetUniformLocation(self.program, "numShapes")
        self.numShapes = 10

        ubo = glGenBuffers(1)
        glBindBuffer(GL_UNIFORM_BUFFER, ubo)
        glBufferData(
            GL_UNIFORM_BUFFER, shapes_block.nbytes, shapes_block, GL_STATIC_DRAW
        )
        glBindBufferBase(GL_UNIFORM_BUFFER, 0, ubo)

        block_index = glGetUniformBlockIndex(self.program, "ShapesBlock")
        glUniformBlockBinding(self.program, block_index, 0)

        glUniform1i(self.shapesNumber_location, self.numShapes)
        glUniform1f(self.blend_strength_location, self.blend_strength)

    def _read_shader(self, path: str) -> str:
        with open(path, "r") as file:
            return file.read()

    def _process_keys(self) -> None:
        """Processa as teclas pressionadas para mover a câmera."""
        keys = pg.key.get_pressed()
        speed = 0.1  # Velocidade de movimento

        # Calcula o vetor de direção com base nos ângulos de rotação
        yaw, pitch = self.camera_rotation[1], self.camera_rotation[0]
        forward = np.array(
            [np.cos(pitch) * np.sin(yaw), -np.sin(pitch), np.cos(pitch) * np.cos(yaw)]
        )
        right = np.array([np.cos(yaw), 0, -np.sin(yaw)])
        up = np.array([0, 1, 0])

        # Movimentos
        if keys[pg.K_w]:  # Move para frente
            self.camera_position += forward * speed
        if keys[pg.K_s]:  # Move para trás
            self.camera_position -= forward * speed
        if keys[pg.K_a]:  # Move para a esquerda
            self.camera_position -= right * speed
        if keys[pg.K_d]:  # Move para a direita
            self.camera_position += right * speed
        if keys[pg.K_q]:  # Move para baixo
            self.camera_position -= up * speed
        if keys[pg.K_e]:  # Move para cima
            self.camera_position += up * speed

        # Atualiza a posição da câmera no shader
        glUniform3f(self.camera_position_location, *self.camera_position)

    def _process_events(self) -> None:
        for event in pg.event.get():
            if event.type == pg.QUIT:
                self.running = False
            if event.type == pg.VIDEORESIZE:
                self.width = event.w
                self.height = event.h
                self.screen = pg.display.set_mode(
                    (self.width, self.height), OPENGL | DOUBLEBUF | RESIZABLE
                )
                glUniform2f(self.resolution_location, self.width, self.height)
            if event.type == pg.KEYDOWN and event.key == pg.K_ESCAPE:
                self.center_mouse = not self.center_mouse
                pg.event.set_grab(self.center_mouse)
                pg.mouse.set_visible(not self.center_mouse)
            if self.center_mouse:
                mouse_dx, mouse_dy = pg.mouse.get_rel()
                self.camera_rotation[1] += mouse_dx * self.mouse_sensitivity
                self.camera_rotation[0] += mouse_dy * self.mouse_sensitivity

                # Limita o pitch para evitar inversão
                self.camera_rotation[0] = np.clip(
                    self.camera_rotation[0], -np.pi / 2, np.pi / 2
                )

                # Atualiza no shader
                glUniform2f(self.camera_rotation_location, *self.camera_rotation)

    def render_loop(self) -> None:
        self.running = True

        # Define the vertex data
        vertices = np.array(
            [-1.0, -1.0, 0.0, 1.0, -1.0, 0.0, 1.0, 1.0, 0.0, -1.0, 1.0, 0.0],
            dtype=np.float32,
        )

        indices = np.array([0, 1, 2, 2, 3, 0], dtype=np.uint32)

        # Create and bind a Vertex Array Object (VAO)
        VAO = glGenVertexArrays(1)
        glBindVertexArray(VAO)

        # Create a Vertex Buffer Object (VBO)
        VBO = glGenBuffers(1)
        glBindBuffer(GL_ARRAY_BUFFER, VBO)
        glBufferData(GL_ARRAY_BUFFER, vertices.nbytes, vertices, GL_STATIC_DRAW)

        # Create an Element Buffer Object (EBO)
        EBO = glGenBuffers(1)
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, EBO)
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, indices.nbytes, indices, GL_STATIC_DRAW)

        # Define the position attribute
        position = glGetAttribLocation(self.program, "vPosition")
        glEnableVertexAttribArray(position)
        glVertexAttribPointer(position, 3, GL_FLOAT, GL_FALSE, 0, None)

        # Unbind the VAO to avoid unintended modifications
        glBindVertexArray(0)

        while self.running:
            self._process_events()
            self._process_keys()

            # Calcula o tempo em segundos
            current_time = pg.time.get_ticks() / 1000.0
            glUniform1f(self.time_location, current_time)

            # OpenGL stuff
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)

            # Bind the VAO and draw
            glBindVertexArray(VAO)
            glDrawElements(GL_TRIANGLES, len(indices), GL_UNSIGNED_INT, None)
            glBindVertexArray(0)

            # Atualiza a tela
            pg.display.flip()
            self.clock.tick(self.max_fps)

    def run(self):
        # threading.Thread(target=self.start_websocket_server, daemon=True).start()
        self.render_loop()

    #
    # def start_websocket_server(self):
    #     asyncio.run(self.run_server())
    #
    # async def websocket_handler(self, websocket):
    #     async for message in websocket:
    #         try:
    #             command, value = message.split(":")
    #             if command == "change_blend_strength":
    #                 new_blend_strength = float(value)
    #
    #                 with self.lock:
    #                     self.blend_strength = new_blend_strength
    #         except ValueError:
    #             print(f"Invalid blend strength received: {message}")
    #
    # async def run_server(self):
    #     server = await websockets.serve(
    #         self.websocket_handler, WEBSOCKET_HOST, WEBSOCKET_PORT
    #     )
    #     print(f"WebSocket server started at ws://{WEBSOCKET_HOST}:{WEBSOCKET_PORT}")
    #     await server.wait_closed()
