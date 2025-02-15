const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_ttf.h");
});
const wad = @import("wad.zig");
const doom_textures = @import("doom_textures.zig");
const patch = @import("graphics/patch.zig");

/// Get the next or previous sprite frame name
/// For example: TROOA1 -> TROOB1 (next) or TROOZ1 (prev)
fn getRelatedSpriteName(allocator: std.mem.Allocator, wad_file: *wad.WadFile, current: [:0]const u8, next: bool) !?[:0]const u8 {
    if (current.len < 6) return null;

    // Create buffer for new name
    var new_name = try allocator.allocSentinel(u8, current.len, 0);
    errdefer allocator.free(new_name);
    @memcpy(new_name[0..current.len], current);

    // Get the frame letter (usually 4th character)
    const frame_pos = 4;
    const current_frame = new_name[frame_pos];

    // Try each letter until we find one that exists or we've tried them all
    var tries: u8 = 0;
    var frame = current_frame;
    while (tries < 26) : (tries += 1) {
        // Get next/prev frame letter
        frame = if (next) blk: {
            if (frame == 'Z' or frame == 'z') break :blk 'A';
            break :blk @as(u8, @intCast(@as(i8, @intCast(frame)) + 1));
        } else blk: {
            if (frame == 'A' or frame == 'a') break :blk 'Z';
            break :blk @as(u8, @intCast(@as(i8, @intCast(frame)) - 1));
        };

        new_name[frame_pos] = frame;
        if (wad_file.findLump(new_name)) |_| {
            return new_name;
        }
    }

    // No valid frame found
    allocator.free(new_name);
    return null;
}

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get command line arguments
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.next();

    // Get WAD file path
    const wad_path = args.next() orelse {
        std.debug.print("Usage: lump_viewer <wad_file> <lump_name>\n", .{});
        return error.InvalidArguments;
    };

    // Get initial lump name
    var current_lump_name: [:0]const u8 = args.next() orelse {
        std.debug.print("Usage: lump_viewer <wad_file> <lump_name>\n", .{});
        return error.InvalidArguments;
    };

    // Load WAD file
    var wad_file = try wad.WadFile.init(allocator, wad_path);
    defer wad_file.deinit();

    // Load PLAYPAL for colors
    var playpal = try doom_textures.Playpal.load(allocator, &wad_file);
    defer playpal.deinit();

    // Initialize SDL
    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
        std.debug.print("SDL2 initialization failed: {s}\n", .{c.SDL_GetError()});
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    // Initialize SDL_ttf
    if (c.TTF_Init() < 0) {
        std.debug.print("SDL_ttf initialization failed: {s}\n", .{c.TTF_GetError()});
        return error.TTFInitializationFailed;
    }
    defer c.TTF_Quit();

    // Load font
    const font = c.TTF_OpenFont("/System/Library/Fonts/Helvetica.ttc", 24) orelse {
        std.debug.print("Failed to load font: {s}\n", .{c.TTF_GetError()});
        return error.FontLoadFailed;
    };
    defer c.TTF_CloseFont(font);

    // Create window
    const window = c.SDL_CreateWindow(
        "DOOM Lump Viewer",
        c.SDL_WINDOWPOS_CENTERED,
        c.SDL_WINDOWPOS_CENTERED,
        800,
        600,
        c.SDL_WINDOW_SHOWN,
    ) orelse {
        std.debug.print("Window creation failed: {s}\n", .{c.SDL_GetError()});
        return error.WindowCreationFailed;
    };
    defer c.SDL_DestroyWindow(window);

    // Create renderer
    const renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED) orelse {
        std.debug.print("Renderer creation failed: {s}\n", .{c.SDL_GetError()});
        return error.RendererCreationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    // Main loop
    var quit = false;
    var event: c.SDL_Event = undefined;
    var current_palette: u8 = 0;
    var current_patch: ?patch.Patch = null;
    defer if (current_patch) |*p| p.deinit();

    // Keep track of allocated lump name
    var allocated_lump_name: ?[:0]const u8 = null;
    defer if (allocated_lump_name) |name| allocator.free(name);

    while (!quit) {
        // Try to load current lump if not loaded
        if (current_patch == null) {
            // Find lump
            if (wad_file.findLump(current_lump_name)) |lump_entry| {
                // Read lump data
                if (wad_file.readLump(lump_entry)) |lump_data| {
                    // Try to load as patch
                    if (patch.Patch.load(allocator, lump_data)) |loaded_patch| {
                        current_patch = loaded_patch;
                    } else |_| {
                        std.debug.print("Failed to load lump as patch\n", .{});
                    }
                    allocator.free(lump_data);
                } else |_| {
                    std.debug.print("Failed to read lump data\n", .{});
                }
            } else {
                std.debug.print("Lump '{s}' not found\n", .{current_lump_name});
            }
        }

        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    quit = true;
                },
                c.SDL_KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        c.SDLK_ESCAPE => {
                            quit = true;
                        },
                        c.SDLK_LEFT => {
                            if (current_palette > 0) current_palette -= 1;
                        },
                        c.SDLK_RIGHT => {
                            if (current_palette < 13) current_palette += 1;
                        },
                        c.SDLK_UP => {
                            // Try to load next frame
                            if (try getRelatedSpriteName(allocator, &wad_file, current_lump_name, true)) |next_name| {
                                if (current_patch) |*p| p.deinit();
                                current_patch = null;
                                if (allocated_lump_name) |name| allocator.free(name);
                                allocated_lump_name = next_name;
                                current_lump_name = next_name;
                            }
                        },
                        c.SDLK_DOWN => {
                            // Try to load previous frame
                            if (try getRelatedSpriteName(allocator, &wad_file, current_lump_name, false)) |prev_name| {
                                if (current_patch) |*p| p.deinit();
                                current_patch = null;
                                if (allocated_lump_name) |name| allocator.free(name);
                                allocated_lump_name = prev_name;
                                current_lump_name = prev_name;
                            }
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        // Clear screen
        _ = c.SDL_SetRenderDrawColor(renderer, 40, 40, 40, 255);
        _ = c.SDL_RenderClear(renderer);

        // Render current patch if loaded
        if (current_patch) |loaded_patch| {
            const surface = loaded_patch.render(&playpal, current_palette) catch |err| {
                std.debug.print("Failed to render patch: {any}\n", .{err});
                continue;
            };
            defer c.SDL_FreeSurface(@ptrCast(surface));

            // Create texture from surface
            const sdl_texture = c.SDL_CreateTextureFromSurface(renderer, @ptrCast(surface)) orelse {
                std.debug.print("Failed to create texture: {s}\n", .{c.SDL_GetError()});
                continue;
            };
            defer c.SDL_DestroyTexture(sdl_texture);

            // Calculate centered position and scaled size
            const scale = 4; // Scale up the image by 4x
            const dest_rect = c.SDL_Rect{
                .x = @divTrunc(@as(i32, 800) - @as(i32, @intCast(loaded_patch.picture.header.width * scale)), 2),
                .y = @divTrunc(@as(i32, 600) - @as(i32, @intCast(loaded_patch.picture.header.height * scale)), 2),
                .w = @intCast(loaded_patch.picture.header.width * scale),
                .h = @intCast(loaded_patch.picture.header.height * scale),
            };

            // Draw texture
            _ = c.SDL_RenderCopy(renderer, sdl_texture, null, &dest_rect);

            // Create display text with lump name and palette number
            var display_text: [64]u8 = undefined;
            const text = std.fmt.bufPrintZ(&display_text, "{s} (Palette: {d})", .{ current_lump_name, current_palette }) catch continue;

            // Render text
            const text_color = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
            const text_surface = c.TTF_RenderText_Solid(font, text.ptr, text_color) orelse {
                std.debug.print("Failed to render text: {s}\n", .{c.TTF_GetError()});
                continue;
            };
            defer c.SDL_FreeSurface(text_surface);

            const text_texture = c.SDL_CreateTextureFromSurface(renderer, text_surface) orelse {
                std.debug.print("Failed to create text texture: {s}\n", .{c.SDL_GetError()});
                continue;
            };
            defer c.SDL_DestroyTexture(text_texture);

            var text_rect = c.SDL_Rect{
                .x = 10,
                .y = 10,
                .w = text_surface.*.w,
                .h = text_surface.*.h,
            };
            _ = c.SDL_RenderCopy(renderer, text_texture, null, &text_rect);
        }

        // Present
        c.SDL_RenderPresent(renderer);

        // Cap frame rate
        c.SDL_Delay(16);
    }
}
