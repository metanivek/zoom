//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const Map = @import("map.zig").Map;
const Renderer3D = @import("renderer.zig").Renderer3D;
const texture = @import("texture.zig");
const TextureManager = texture.TextureManager;
const wad = @import("wad.zig");

const GameState = struct {
    quit: bool = false,
    keyboard: struct {
        w: bool = false,
        s: bool = false,
        a: bool = false,
        d: bool = false,
        left: bool = false,
        right: bool = false,
        escape: bool = false,
        debug: bool = false,
        m: bool = false,
    } = .{},
    map: *Map,
    renderer3d: Renderer3D,
    render_mode: enum { Mode2D, Mode3D } = .Mode3D,
    texture_manager: *TextureManager,
    wad_file: ?*wad.WadFile = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, screen_width: u32, screen_height: u32) !GameState {
        const map = try allocator.create(Map);
        map.* = try Map.init(allocator);

        const texture_manager = try allocator.create(TextureManager);
        texture_manager.* = TextureManager.init(allocator);

        // Try to load DOOM WAD file for textures
        var wad_file: ?*wad.WadFile = null;
        if (std.fs.cwd().access("doom1.wad", .{})) {
            const wad_ptr = try allocator.create(wad.WadFile);
            wad_ptr.* = try wad.WadFile.init(allocator, "doom1.wad");
            wad_file = wad_ptr;

            // Load PLAYPAL and COLORMAP
            try texture_manager.loadFromWad(wad_ptr);
        } else |_| {
            std.debug.print("No DOOM WAD file found, using fallback textures\n", .{});
        }

        // Load wall textures (fallback or for testing)
        try texture_manager.loadTexture("wall1", "assets/textures/wall1.bmp");
        try texture_manager.loadTexture("wall2", "assets/textures/wall2.bmp");
        try texture_manager.loadTexture("wall3", "assets/textures/wall3.bmp");
        try texture_manager.loadTexture("bricks", "assets/textures/bricks.bmp");
        try texture_manager.loadTexture("stripes", "assets/textures/stripes.bmp");

        return .{
            .map = map,
            .renderer3d = Renderer3D.init(screen_width, screen_height, texture_manager),
            .texture_manager = texture_manager,
            .wad_file = wad_file,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GameState) void {
        self.map.deinit();
        self.allocator.destroy(self.map);
        self.texture_manager.deinit();
        self.allocator.destroy(self.texture_manager);
        if (self.wad_file) |wad_ptr| {
            wad_ptr.deinit();
            self.allocator.destroy(wad_ptr);
        }
    }
};

// Target frame rate and time step
const FRAME_RATE: u32 = 60;
const FIXED_DELTA_TIME: f32 = 1.0 / @as(f32, @floatFromInt(FRAME_RATE));
const MAX_FRAME_TIME: f32 = 0.25; // Maximum time step (prevents spiral of death)

// Movement constants
const MOVE_SPEED: f32 = 200.0; // pixels per second
const TURN_SPEED: f32 = 3.0; // radians per second

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize SDL
    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
        std.debug.print("SDL2 initialization failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const SCREEN_WIDTH = 800;
    const SCREEN_HEIGHT = 600;

    // Create window
    const window = c.SDL_CreateWindow(
        "ZOOM",
        c.SDL_WINDOWPOS_CENTERED,
        c.SDL_WINDOWPOS_CENTERED,
        SCREEN_WIDTH,
        SCREEN_HEIGHT,
        c.SDL_WINDOW_SHOWN,
    ) orelse {
        std.debug.print("Window creation failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLWindowCreationFailed;
    };
    defer c.SDL_DestroyWindow(window);

    // Create renderer
    const renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED) orelse {
        std.debug.print("Renderer creation failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLRendererCreationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    var game_state = try GameState.init(allocator, SCREEN_WIDTH, SCREEN_HEIGHT);
    defer game_state.deinit();
    var event: c.SDL_Event = undefined;

    var last_time: u64 = c.SDL_GetPerformanceCounter();
    var accumulator: f32 = 0.0;

    // Main game loop
    while (!game_state.quit) {
        // Calculate frame time
        const current_time = c.SDL_GetPerformanceCounter();
        const elapsed = @as(f32, @floatFromInt(current_time - last_time)) / @as(f32, @floatFromInt(c.SDL_GetPerformanceFrequency()));
        last_time = current_time;

        // Cap maximum frame time to prevent spiral of death
        const frame_time = if (elapsed > MAX_FRAME_TIME) MAX_FRAME_TIME else elapsed;
        accumulator += frame_time;

        // Handle events
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    game_state.quit = true;
                },
                c.SDL_KEYDOWN, c.SDL_KEYUP => {
                    const is_down = event.type == c.SDL_KEYDOWN;
                    switch (event.key.keysym.sym) {
                        c.SDLK_w => game_state.keyboard.w = is_down,
                        c.SDLK_s => game_state.keyboard.s = is_down,
                        c.SDLK_a => game_state.keyboard.a = is_down,
                        c.SDLK_d => game_state.keyboard.d = is_down,
                        c.SDLK_LEFT => game_state.keyboard.left = is_down,
                        c.SDLK_RIGHT => game_state.keyboard.right = is_down,
                        c.SDLK_ESCAPE => game_state.keyboard.escape = is_down,
                        c.SDLK_F1 => {
                            if (is_down) {
                                game_state.map.toggleDebug();
                            }
                        },
                        c.SDLK_m => {
                            if (is_down) {
                                game_state.render_mode = if (game_state.render_mode == .Mode3D) .Mode2D else .Mode3D;
                            }
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        // Fixed time step updates
        while (accumulator >= FIXED_DELTA_TIME) {
            update(&game_state);
            accumulator -= FIXED_DELTA_TIME;
        }

        // Render based on current mode
        switch (game_state.render_mode) {
            .Mode2D => game_state.map.render(renderer),
            .Mode3D => game_state.renderer3d.render(renderer, game_state.map, game_state.map.player.position, game_state.map.player.angle),
        }

        // Present the rendered frame
        c.SDL_RenderPresent(renderer);
    }
}

fn update(state: *GameState) void {
    // Check for quit condition
    if (state.keyboard.escape) {
        state.quit = true;
        return;
    }

    // Update player rotation
    if (state.keyboard.left) {
        state.map.player.angle -= TURN_SPEED * FIXED_DELTA_TIME;
    }
    if (state.keyboard.right) {
        state.map.player.angle += TURN_SPEED * FIXED_DELTA_TIME;
    }

    // Calculate movement vector based on player's angle
    var dx: f32 = 0;
    var dy: f32 = 0;

    if (state.keyboard.w) {
        dx += @cos(state.map.player.angle) * MOVE_SPEED * FIXED_DELTA_TIME;
        dy += @sin(state.map.player.angle) * MOVE_SPEED * FIXED_DELTA_TIME;
    }
    if (state.keyboard.s) {
        dx -= @cos(state.map.player.angle) * MOVE_SPEED * FIXED_DELTA_TIME;
        dy -= @sin(state.map.player.angle) * MOVE_SPEED * FIXED_DELTA_TIME;
    }
    if (state.keyboard.a) {
        const strafe_angle = state.map.player.angle - std.math.pi / 2.0;
        dx += @cos(strafe_angle) * MOVE_SPEED * FIXED_DELTA_TIME;
        dy += @sin(strafe_angle) * MOVE_SPEED * FIXED_DELTA_TIME;
    }
    if (state.keyboard.d) {
        const strafe_angle = state.map.player.angle + std.math.pi / 2.0;
        dx += @cos(strafe_angle) * MOVE_SPEED * FIXED_DELTA_TIME;
        dy += @sin(strafe_angle) * MOVE_SPEED * FIXED_DELTA_TIME;
    }

    // Try to move player with collision detection
    state.map.tryMovePlayer(dx, dy);
}

test {
    // Import all modules for testing
    _ = @import("map.zig");
    _ = @import("renderer.zig");
    _ = @import("texture.zig");
    _ = @import("wad.zig");
    _ = @import("doom_textures.zig");
    _ = @import("doom_map.zig");
    _ = @import("graphics/patch.zig");
    _ = @import("graphics/picture.zig");
    _ = @import("graphics/sprite.zig");
}
