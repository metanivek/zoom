//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

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
    } = .{},
};

// Target frame rate and time step
const FRAME_RATE: u32 = 60;
const FIXED_DELTA_TIME: f32 = 1.0 / @as(f32, @floatFromInt(FRAME_RATE));
const MAX_FRAME_TIME: f32 = 0.25; // Maximum time step (prevents spiral of death)

pub fn main() !void {
    // Initialize SDL
    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
        std.debug.print("SDL2 initialization failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    // Create window
    const window = c.SDL_CreateWindow(
        "ZOOM",
        c.SDL_WINDOWPOS_CENTERED,
        c.SDL_WINDOWPOS_CENTERED,
        800,
        600,
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

    var game_state = GameState{};
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

        // Render at whatever rate we can
        render(renderer);
    }
}

fn update(state: *GameState) void {
    // Check for quit condition
    if (state.keyboard.escape) {
        state.quit = true;
        return;
    }

    // TODO: Add game state updates here
    // Example debug output to show input state
    if (state.keyboard.w) std.debug.print("Moving forward\n", .{});
    if (state.keyboard.s) std.debug.print("Moving backward\n", .{});
    if (state.keyboard.a) std.debug.print("Strafing left\n", .{});
    if (state.keyboard.d) std.debug.print("Strafing right\n", .{});
    if (state.keyboard.left) std.debug.print("Turning left\n", .{});
    if (state.keyboard.right) std.debug.print("Turning right\n", .{});
}

fn render(renderer: *c.SDL_Renderer) void {
    // Clear screen
    _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
    _ = c.SDL_RenderClear(renderer);

    // TODO: Add rendering code here

    // Present renderer
    c.SDL_RenderPresent(renderer);
}

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("zoom_lib");
