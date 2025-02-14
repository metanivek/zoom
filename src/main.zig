//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

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

    // Main game loop
    var quit = false;
    var event: c.SDL_Event = undefined;

    while (!quit) {
        // Handle events
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    quit = true;
                },
                else => {},
            }
        }

        // Clear screen
        _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        _ = c.SDL_RenderClear(renderer);

        // TODO: Add rendering code here

        // Present renderer
        c.SDL_RenderPresent(renderer);
    }
}

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("zoom_lib");
