//! DOOM-like game engine implementation

const std = @import("std");
const c = @cImport({
    @cInclude("SDL.h");
});
const texture = @import("texture.zig");
const TextureManager = texture.TextureManager;
const wad = @import("wad.zig");
const patch = @import("graphics/patch.zig");

const Config = struct {
    // Display settings
    screen_width: u32 = 640,
    screen_height: u32 = 400,
    window_title: []const u8 = "ZOOM",
    fullscreen: bool = false,
    vsync: bool = true,
    target_fps: u32 = 60,

    // Game settings
    wad_file_path: []const u8 = "doom1.wad",
    debug_mode: bool = false,
    show_fps: bool = false,

    // Rendering settings
    texture_scale: u32 = 2, // Scale factor for textures

    pub fn frameTime(self: Config) u32 {
        return if (self.vsync) 0 else @divTrunc(1000, self.target_fps);
    }

    pub fn getWindowFlags(self: Config) u32 {
        var flags: u32 = c.SDL_WINDOW_SHOWN;
        if (self.fullscreen) {
            flags |= c.SDL_WINDOW_FULLSCREEN;
        }
        return flags;
    }

    pub fn getRendererFlags(self: Config) u32 {
        var flags: u32 = c.SDL_RENDERER_ACCELERATED;
        if (self.vsync) {
            flags |= c.SDL_RENDERER_PRESENTVSYNC;
        }
        return flags;
    }
};

const SDLError = error{
    InitializationFailed,
    WindowCreationFailed,
    RendererCreationFailed,
};

const SDLContext = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,

    pub fn init(config: Config) SDLError!SDLContext {
        if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
            std.debug.print("SDL2 initialization failed: {s}\n", .{c.SDL_GetError()});
            return SDLError.InitializationFailed;
        }
        errdefer c.SDL_Quit();

        const window = c.SDL_CreateWindow(
            config.window_title.ptr,
            c.SDL_WINDOWPOS_CENTERED,
            c.SDL_WINDOWPOS_CENTERED,
            @intCast(config.screen_width),
            @intCast(config.screen_height),
            config.getWindowFlags(),
        ) orelse {
            std.debug.print("Window creation failed: {s}\n", .{c.SDL_GetError()});
            return SDLError.WindowCreationFailed;
        };
        errdefer c.SDL_DestroyWindow(window);

        const renderer = c.SDL_CreateRenderer(window, -1, config.getRendererFlags()) orelse {
            std.debug.print("Renderer creation failed: {s}\n", .{c.SDL_GetError()});
            return SDLError.RendererCreationFailed;
        };

        return .{
            .window = window,
            .renderer = renderer,
        };
    }

    pub fn deinit(self: *SDLContext) void {
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }
};

const KeyboardState = struct {
    escape: bool = false,

    pub fn handleKeyEvent(self: *KeyboardState, key: c.SDL_Keycode, is_down: bool) void {
        switch (key) {
            c.SDLK_ESCAPE => self.escape = is_down,
            else => {},
        }
    }
};

const GameError = error{
    WadLoadFailed,
    TextureLoadFailed,
    TextureCreationFailed,
    SurfaceRenderFailed,
} || SDLError;

const GameState = struct {
    quit: bool = false,
    keyboard: KeyboardState = .{},
    texture_manager: *TextureManager,
    wad_file: ?*wad.WadFile = null,
    allocator: std.mem.Allocator,
    delta_time: f32 = 0,
    config: Config,

    pub fn init(allocator: std.mem.Allocator, config: Config) GameError!GameState {
        const texture_manager = allocator.create(TextureManager) catch {
            return GameError.TextureLoadFailed;
        };
        texture_manager.* = TextureManager.init(allocator);

        // Try to load DOOM WAD file for textures
        var wad_file: ?*wad.WadFile = null;
        if (std.fs.cwd().access(config.wad_file_path, .{})) {
            const wad_ptr = allocator.create(wad.WadFile) catch {
                texture_manager.deinit();
                allocator.destroy(texture_manager);
                return GameError.WadLoadFailed;
            };
            wad_ptr.* = wad.WadFile.init(allocator, config.wad_file_path) catch |err| {
                allocator.destroy(wad_ptr);
                texture_manager.deinit();
                allocator.destroy(texture_manager);
                std.debug.print("Failed to initialize WAD file: {any}\n", .{err});
                return GameError.WadLoadFailed;
            };
            wad_file = wad_ptr;

            // Load PLAYPAL and COLORMAP
            texture_manager.loadFromWad(wad_ptr) catch |err| {
                wad_ptr.deinit();
                allocator.destroy(wad_ptr);
                texture_manager.deinit();
                allocator.destroy(texture_manager);
                std.debug.print("Failed to load textures from WAD: {any}\n", .{err});
                return GameError.TextureLoadFailed;
            };
        } else |_| {
            if (config.debug_mode) {
                std.debug.print("No DOOM WAD file found at path: {s}\n", .{config.wad_file_path});
            }
        }

        return .{
            .texture_manager = texture_manager,
            .wad_file = wad_file,
            .allocator = allocator,
            .config = config,
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

    pub fn handleEvents(self: *GameState) void {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    self.quit = true;
                },
                c.SDL_KEYDOWN, c.SDL_KEYUP => {
                    const is_down = event.type == c.SDL_KEYDOWN;
                    self.keyboard.handleKeyEvent(event.key.keysym.sym, is_down);
                },
                else => {},
            }
        }
    }

    pub fn update(self: *GameState) void {
        // Check for quit condition
        if (self.keyboard.escape) {
            self.quit = true;
        }

        // Add future game state updates here
        // They will automatically have access to delta_time
    }

    pub fn render(self: *const GameState, sdl: *SDLContext) GameError!void {
        // Clear screen
        if (c.SDL_SetRenderDrawColor(sdl.renderer, 0, 0, 0, 255) < 0) {
            std.debug.print("Failed to set render draw color: {s}\n", .{c.SDL_GetError()});
            return GameError.TextureCreationFailed;
        }
        if (c.SDL_RenderClear(sdl.renderer) < 0) {
            std.debug.print("Failed to clear renderer: {s}\n", .{c.SDL_GetError()});
            return GameError.TextureCreationFailed;
        }

        // Render title screen if available
        if (self.texture_manager.menu_patches) |menu| {
            if (menu.title_screen) |title| {
                const surface = title.render(self.texture_manager.playpal.?, 0) catch |err| {
                    std.debug.print("Failed to render title: {any}\n", .{err});
                    return GameError.SurfaceRenderFailed;
                };
                defer c.SDL_FreeSurface(@ptrCast(surface));

                const title_texture = c.SDL_CreateTextureFromSurface(sdl.renderer, @ptrCast(surface)) orelse {
                    std.debug.print("Failed to create texture: {s}\n", .{c.SDL_GetError()});
                    return GameError.TextureCreationFailed;
                };
                defer c.SDL_DestroyTexture(title_texture);

                // Calculate centered position using config's texture scale
                const width = @as(u32, @intCast(@max(0, title.picture.header.width)));
                const height = @as(u32, @intCast(@max(0, title.picture.header.height)));
                const scaled_width = @as(i32, @intCast(width * self.config.texture_scale));
                const scaled_height = @as(i32, @intCast(height * self.config.texture_scale));
                const screen_width = @as(i32, @intCast(self.config.screen_width));
                const screen_height = @as(i32, @intCast(self.config.screen_height));

                const dest_rect = c.SDL_Rect{
                    .x = @divTrunc(screen_width - scaled_width, 2),
                    .y = @divTrunc(screen_height - scaled_height, 2),
                    .w = scaled_width,
                    .h = scaled_height,
                };

                if (c.SDL_RenderCopy(sdl.renderer, title_texture, null, &dest_rect) < 0) {
                    std.debug.print("Failed to copy texture to renderer: {s}\n", .{c.SDL_GetError()});
                    return GameError.TextureCreationFailed;
                }
            }
        }

        c.SDL_RenderPresent(sdl.renderer);
    }
};

const FrameTimer = struct {
    last_time: u32,
    frame_time: u32,

    pub fn init(config: Config) FrameTimer {
        return .{
            .last_time = c.SDL_GetTicks(),
            .frame_time = config.frameTime(),
        };
    }

    pub fn tick(self: *FrameTimer) f32 {
        const current_time = c.SDL_GetTicks();
        const elapsed = current_time - self.last_time;

        // If we're running too fast, delay
        if (self.frame_time > 0 and elapsed < self.frame_time) {
            c.SDL_Delay(self.frame_time - elapsed);
        }

        // Get the actual elapsed time (including any delay)
        const actual_elapsed = c.SDL_GetTicks() - self.last_time;
        self.last_time = c.SDL_GetTicks();

        return @as(f32, @floatFromInt(actual_elapsed)) / 1000.0;
    }
};

pub fn main() GameError!void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create default config
    const config = Config{};

    // Initialize SDL
    var sdl_context = try SDLContext.init(config);
    defer sdl_context.deinit();

    var game_state = try GameState.init(allocator, config);
    defer game_state.deinit();

    var frame_timer = FrameTimer.init(config);

    // Main game loop
    while (!game_state.quit) {
        // Handle input events
        game_state.handleEvents();

        // Update game state with delta time
        game_state.delta_time = frame_timer.tick();
        game_state.update();

        // Render frame
        try game_state.render(&sdl_context);
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
