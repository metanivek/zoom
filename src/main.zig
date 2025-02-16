//! DOOM-like game engine implementation

const std = @import("std");
const c = @cImport({
    @cInclude("SDL.h");
});
const texture = @import("texture.zig");
const TextureManager = texture.TextureManager;
const wad = @import("wad.zig");
const patch = @import("graphics/patch.zig");

const GameState = struct {
    quit: bool = false,
    keyboard: struct {
        escape: bool = false,
    } = .{},
    texture_manager: *TextureManager,
    wad_file: ?*wad.WadFile = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, screen_width: u32, screen_height: u32) !GameState {
        _ = screen_width;
        _ = screen_height;

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
            std.debug.print("No DOOM WAD file found\n", .{});
        }

        return .{
            .texture_manager = texture_manager,
            .wad_file = wad_file,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GameState) void {
        self.texture_manager.deinit();
        self.allocator.destroy(self.texture_manager);
        if (self.wad_file) |wad_ptr| {
            wad_ptr.deinit();
            self.allocator.destroy(wad_ptr);
        }
    }
};

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

    const SCREEN_WIDTH = 640;
    const SCREEN_HEIGHT = 400;

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

    // Main game loop
    while (!game_state.quit) {
        // Handle events
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    game_state.quit = true;
                },
                c.SDL_KEYDOWN, c.SDL_KEYUP => {
                    const is_down = event.type == c.SDL_KEYDOWN;
                    switch (event.key.keysym.sym) {
                        c.SDLK_ESCAPE => game_state.keyboard.escape = is_down,
                        else => {},
                    }
                },
                else => {},
            }
        }

        // Check for quit condition
        if (game_state.keyboard.escape) {
            game_state.quit = true;
        }

        // Clear screen
        _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        _ = c.SDL_RenderClear(renderer);

        // Render title screen if available
        if (game_state.texture_manager.menu_patches) |menu| {
            if (menu.title_screen) |title| {
                const surface = title.render(game_state.texture_manager.playpal.?, 0) catch |err| {
                    std.debug.print("Failed to render title: {any}\n", .{err});
                    continue;
                };
                defer c.SDL_FreeSurface(@ptrCast(surface));

                const title_texture = c.SDL_CreateTextureFromSurface(renderer, @ptrCast(surface)) orelse {
                    std.debug.print("Failed to create texture: {s}\n", .{c.SDL_GetError()});
                    continue;
                };
                defer c.SDL_DestroyTexture(title_texture);

                // Calculate centered position
                const dest_rect = c.SDL_Rect{
                    .x = @divTrunc(@as(i32, SCREEN_WIDTH) - @as(i32, @intCast(title.picture.header.width * 2)), 2),
                    .y = @divTrunc(@as(i32, SCREEN_HEIGHT) - @as(i32, @intCast(title.picture.header.height * 2)), 2),
                    .w = @intCast(title.picture.header.width * 2),
                    .h = @intCast(title.picture.header.height * 2),
                };

                _ = c.SDL_RenderCopy(renderer, title_texture, null, &dest_rect);
            }
        }

        // Present the rendered frame
        c.SDL_RenderPresent(renderer);
    }
}

test {
    // Import all modules for testing
    _ = @import("texture.zig");
    _ = @import("wad.zig");
    _ = @import("doom_textures.zig");
    _ = @import("doom_map.zig");
    _ = @import("graphics/patch.zig");
    _ = @import("graphics/picture.zig");
    _ = @import("graphics/sprite.zig");
    _ = @import("graphics/flat.zig");
    _ = @import("graphics/composite_texture.zig");
}
