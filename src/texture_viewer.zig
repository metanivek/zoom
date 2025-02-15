const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL_ttf.h");
});
const wad = @import("wad.zig");
const doom_textures = @import("doom_textures.zig");
const tex = @import("texture.zig");
const patch = @import("graphics/patch.zig");
const picture = @import("graphics/picture.zig");
const sprite = @import("graphics/sprite.zig");

const ViewMode = enum {
    Palettes,
    Patches,
    Textures,
    Sprites,
};

const SpriteGroup = struct {
    prefix: []const u8,
    sprite_indices: std.ArrayList(usize), // Indices into texture_manager.sprites
    frame_sequence: []u8, // Sequence of frame letters for animation
    current_rotation: u8 = 0,
    is_animating: bool = false,

    pub fn init(allocator: std.mem.Allocator, prefix: []const u8) !SpriteGroup {
        return SpriteGroup{
            .prefix = try allocator.dupe(u8, prefix),
            .sprite_indices = std.ArrayList(usize).init(allocator),
            .frame_sequence = try allocator.alloc(u8, 0),
            .is_animating = false,
        };
    }

    pub fn deinit(self: *SpriteGroup, allocator: std.mem.Allocator) void {
        allocator.free(self.prefix);
        allocator.free(self.frame_sequence);
        self.sprite_indices.deinit();
    }

    pub fn addFrameLetter(self: *SpriteGroup, allocator: std.mem.Allocator, frame: u8) !void {
        // Check if frame letter already exists
        for (self.frame_sequence) |existing_frame| {
            if (existing_frame == frame) return;
        }
        // Add new frame letter
        const new_sequence = try allocator.realloc(self.frame_sequence, self.frame_sequence.len + 1);
        new_sequence[new_sequence.len - 1] = frame;
        self.frame_sequence = new_sequence;
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

    // Initialize SDL_ttf
    if (c.TTF_Init() < 0) {
        std.debug.print("SDL_ttf initialization failed: {s}\n", .{c.TTF_GetError()});
        return error.TTFInitializationFailed;
    }
    defer c.TTF_Quit();

    // Load font
    const font = c.TTF_OpenFont("/System/Library/Fonts/Helvetica.ttc", 16) orelse {
        std.debug.print("Failed to load font: {s}\n", .{c.TTF_GetError()});
        return error.FontLoadFailed;
    };
    defer c.TTF_CloseFont(font);

    // Create window
    const window = c.SDL_CreateWindow(
        "DOOM Texture Viewer",
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

    // Load WAD file
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.next();

    // Get WAD file path
    const wad_path = args.next() orelse {
        std.debug.print("Usage: texture_viewer <wad_file>\n", .{});
        return error.InvalidArguments;
    };

    var wad_file = try wad.WadFile.init(allocator, wad_path);
    defer wad_file.deinit();

    // Initialize texture manager
    var texture_manager = tex.TextureManager.init(allocator);
    defer texture_manager.deinit();

    // Load PLAYPAL and COLORMAP
    try texture_manager.loadFromWad(&wad_file);

    // Load patches and sprites from WAD
    var in_patch_marker = false;
    var in_sprite_marker = false;
    for (wad_file.directory) |*entry| {
        const name = entry.getName();

        // Check for patch markers
        if (std.mem.eql(u8, name, "P_START") or std.mem.eql(u8, name, "PP_START")) {
            in_patch_marker = true;
            continue;
        } else if (std.mem.eql(u8, name, "P_END") or std.mem.eql(u8, name, "PP_END")) {
            in_patch_marker = false;
            continue;
        }

        // Check for sprite markers
        if (std.mem.eql(u8, name, "S_START") or std.mem.eql(u8, name, "SS_START")) {
            in_sprite_marker = true;
            continue;
        } else if (std.mem.eql(u8, name, "S_END") or std.mem.eql(u8, name, "SS_END")) {
            in_sprite_marker = false;
            continue;
        }

        // Skip nested P1/P2/P3 markers
        if (std.mem.eql(u8, name, "P1_START") or
            std.mem.eql(u8, name, "P2_START") or
            std.mem.eql(u8, name, "P3_START") or
            std.mem.eql(u8, name, "P1_END") or
            std.mem.eql(u8, name, "P2_END") or
            std.mem.eql(u8, name, "P3_END"))
        {
            continue;
        }

        // Process entries based on current marker section
        if (in_patch_marker) {
            // Try to load as patch
            std.debug.print("\nLoading patch '{s}' (file_pos={d}, size={d})\n", .{ name, entry.file_pos, entry.size });
            const data = try wad_file.readLump(entry);
            defer allocator.free(data);

            texture_manager.loadPatch(name, data) catch |err| {
                std.debug.print("\nFailed to load patch '{s}': {any}\n", .{ name, err });
                std.debug.print("Patch data size: {d} bytes\n", .{data.len});
                std.debug.print("First 16 bytes: ", .{});
                for (data[0..@min(16, data.len)]) |byte| {
                    std.debug.print("{X:0>2} ", .{byte});
                }
                std.debug.print("\n", .{});
                if (data.len >= @sizeOf(picture.Header)) {
                    const header = @as(*const picture.Header, @ptrCast(@alignCast(data.ptr)));
                    std.debug.print("Patch header:\n", .{});
                    std.debug.print("  width: {d}\n", .{header.width});
                    std.debug.print("  height: {d}\n", .{header.height});
                    std.debug.print("  left_offset: {d}\n", .{header.left_offset});
                    std.debug.print("  top_offset: {d}\n", .{header.top_offset});
                }
                return err;
            };
        } else if (in_sprite_marker) {
            // Try to load as sprite
            std.debug.print("\nLoading sprite '{s}' (file_pos={d}, size={d})\n", .{ name, entry.file_pos, entry.size });
            const data = try wad_file.readLump(entry);
            defer allocator.free(data);

            texture_manager.loadSprite(name, data) catch |err| {
                std.debug.print("\nFailed to load sprite '{s}': {any}\n", .{ name, err });
                std.debug.print("Sprite data size: {d} bytes\n", .{data.len});
                std.debug.print("First 16 bytes: ", .{});
                for (data[0..@min(16, data.len)]) |byte| {
                    std.debug.print("{X:0>2} ", .{byte});
                }
                std.debug.print("\n", .{});
                if (data.len >= @sizeOf(picture.Header)) {
                    const header = @as(*const picture.Header, @ptrCast(@alignCast(data.ptr)));
                    std.debug.print("Sprite header:\n", .{});
                    std.debug.print("  width: {d}\n", .{header.width});
                    std.debug.print("  height: {d}\n", .{header.height});
                    std.debug.print("  left_offset: {d}\n", .{header.left_offset});
                    std.debug.print("  top_offset: {d}\n", .{header.top_offset});
                }
                continue;
            };
        }
    }

    // Main loop variables
    var quit = false;
    var view_mode = ViewMode.Patches;
    var current_patch: usize = 0;
    var current_palette: u8 = 0;
    var current_rotation: u8 = 0;

    // Create sprite groups
    var sprite_groups = std.ArrayList(SpriteGroup).init(allocator);
    defer {
        for (sprite_groups.items) |*group| {
            group.deinit(allocator);
        }
        sprite_groups.deinit();
    }

    // Group sprites by prefix
    var current_group: usize = 0;
    {
        var prefix_map = std.StringHashMap(usize).init(allocator);
        defer prefix_map.deinit();

        // First pass: collect unique prefixes and create groups
        for (texture_manager.sprites.items, 0..) |sprite_entry, i| {
            const prefix = sprite_entry.name[0..4];
            const group_idx = if (prefix_map.get(prefix)) |idx| idx else blk: {
                // Create new group
                const group = try SpriteGroup.init(allocator, prefix);
                try sprite_groups.append(group);
                try prefix_map.put(prefix, sprite_groups.items.len - 1);
                break :blk sprite_groups.items.len - 1;
            };

            // Add sprite index to its group
            try sprite_groups.items[group_idx].sprite_indices.append(i);

            // Add frame letter to sequence if not already present
            try sprite_groups.items[group_idx].addFrameLetter(allocator, sprite_entry.sprite.name.frame);
        }

        // Sort frame sequences for consistent animation order
        for (sprite_groups.items) |*group| {
            std.mem.sort(u8, group.frame_sequence, {}, std.sort.asc(u8));
        }

        // Set up animations for all sprites
        for (sprite_groups.items) |*group| {
            for (group.sprite_indices.items) |sprite_idx| {
                var sprite_obj = &texture_manager.sprites.items[sprite_idx].sprite;
                try sprite_obj.setupAnimation(group.frame_sequence);
            }
        }
    }

    while (!quit) {
        // Handle events
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    quit = true;
                },
                c.SDL_KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        c.SDLK_ESCAPE => quit = true,
                        c.SDLK_m => {
                            // Cycle view mode
                            view_mode = switch (view_mode) {
                                .Palettes => .Patches,
                                .Patches => .Textures,
                                .Textures => .Sprites,
                                .Sprites => .Palettes,
                            };
                        },
                        c.SDLK_LEFT => switch (view_mode) {
                            .Patches => {
                                if (texture_manager.patches.items.len > 0 and current_patch > 0) {
                                    current_patch -= 1;
                                }
                            },
                            .Sprites => {
                                if (sprite_groups.items.len > 0 and current_group > 0) {
                                    current_group -= 1;
                                }
                            },
                            .Palettes => {
                                if (current_palette > 0) {
                                    current_palette -= 1;
                                }
                            },
                            else => {},
                        },
                        c.SDLK_RIGHT => switch (view_mode) {
                            .Patches => {
                                if (texture_manager.patches.items.len > 0 and current_patch < texture_manager.patches.items.len - 1) {
                                    current_patch += 1;
                                }
                            },
                            .Sprites => {
                                if (sprite_groups.items.len > 0 and current_group < sprite_groups.items.len - 1) {
                                    current_group += 1;
                                }
                            },
                            .Palettes => {
                                if (current_palette < 13) {
                                    current_palette += 1;
                                }
                            },
                            else => {},
                        },
                        c.SDLK_SPACE => switch (view_mode) {
                            .Sprites => {
                                if (sprite_groups.items.len > 0) {
                                    const group = &sprite_groups.items[current_group];
                                    group.is_animating = !group.is_animating;
                                    // Find sprite with current rotation and toggle its animation
                                    for (group.sprite_indices.items) |sprite_idx| {
                                        var sprite_obj = &texture_manager.sprites.items[sprite_idx].sprite;
                                        if (sprite_obj.name.rotation == current_rotation) {
                                            if (group.is_animating) {
                                                sprite_obj.play();
                                            } else {
                                                sprite_obj.stop();
                                            }
                                            break;
                                        }
                                    }
                                }
                            },
                            else => {},
                        },
                        c.SDLK_UP => switch (view_mode) {
                            .Sprites => {
                                if (current_rotation < 8) {
                                    current_rotation += 1;
                                }
                            },
                            else => {},
                        },
                        c.SDLK_DOWN => switch (view_mode) {
                            .Sprites => {
                                if (current_rotation > 0) {
                                    current_rotation -= 1;
                                }
                            },
                            else => {},
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }

        // Clear screen
        _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
        _ = c.SDL_RenderClear(renderer);

        switch (view_mode) {
            .Patches => {
                if (texture_manager.patches.items.len > 0 and texture_manager.playpal != null) {
                    const patch_entry = &texture_manager.patches.items[current_patch];
                    const current_patch_obj = &patch_entry.patch;

                    // Render patch using our new render function
                    const surface = current_patch_obj.render(&texture_manager.playpal.?, current_palette) catch |err| {
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

                    // Draw texture
                    var dest_rect = c.SDL_Rect{
                        .x = 50,
                        .y = 50,
                        .w = @intCast(current_patch_obj.picture.header.width * 2),
                        .h = @intCast(current_patch_obj.picture.header.height * 2),
                    };
                    _ = c.SDL_RenderCopy(renderer, sdl_texture, null, &dest_rect);

                    // Draw patch info
                    var info_buf: [256]u8 = undefined;
                    const info_text = try std.fmt.bufPrint(&info_buf, "Patch: {s} ({d}x{d})\x00", .{
                        patch_entry.name,
                        current_patch_obj.picture.header.width,
                        current_patch_obj.picture.header.height,
                    });

                    const text_color = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
                    const text_surface = c.TTF_RenderText_Solid(font, info_text.ptr, text_color) orelse {
                        std.debug.print("Failed to render text: {s}\n", .{c.TTF_GetError()});
                        continue;
                    };
                    defer c.SDL_FreeSurface(text_surface);

                    const text_texture = c.SDL_CreateTextureFromSurface(renderer, text_surface) orelse {
                        std.debug.print("Failed to create texture: {s}\n", .{c.SDL_GetError()});
                        continue;
                    };
                    defer c.SDL_DestroyTexture(text_texture);

                    var text_rect = c.SDL_Rect{
                        .x = 50,
                        .y = 10,
                        .w = text_surface.*.w,
                        .h = text_surface.*.h,
                    };
                    _ = c.SDL_RenderCopy(renderer, text_texture, null, &text_rect);
                }
            },
            .Sprites => {
                if (sprite_groups.items.len > 0 and texture_manager.playpal != null) {
                    const group = &sprite_groups.items[current_group];

                    // Draw list of sprite lump names for current prefix
                    var y_offset: c_int = 50;
                    for (group.sprite_indices.items) |sprite_idx| {
                        const sprite_entry = &texture_manager.sprites.items[sprite_idx];
                        var info_buf: [256]u8 = undefined;
                        // Get the actual sprite name length by finding the first non-printable character
                        var name_len: usize = 0;
                        for (sprite_entry.name) |char| {
                            if (char < 32 or char > 126) break;
                            name_len += 1;
                        }
                        _ = try std.fmt.bufPrint(&info_buf, "{s}\x00", .{sprite_entry.name[0..name_len]});

                        const text_color = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
                        const text_surface = c.TTF_RenderText_Solid(font, &info_buf, text_color) orelse {
                            std.debug.print("Failed to render text: {s}\n", .{c.TTF_GetError()});
                            continue;
                        };
                        defer c.SDL_FreeSurface(text_surface);

                        const text_texture = c.SDL_CreateTextureFromSurface(renderer, text_surface) orelse {
                            std.debug.print("Failed to create texture: {s}\n", .{c.SDL_GetError()});
                            continue;
                        };
                        defer c.SDL_DestroyTexture(text_texture);

                        var text_rect = c.SDL_Rect{
                            .x = 20,
                            .y = y_offset,
                            .w = text_surface.*.w,
                            .h = text_surface.*.h,
                        };
                        _ = c.SDL_RenderCopy(renderer, text_texture, null, &text_rect);
                        y_offset += 20;
                    }

                    // Find sprite with current rotation
                    const current_sprite: ?*sprite.Sprite = blk: {
                        // First, find any sprite with the current rotation to handle animation
                        var animation_sprite: ?*sprite.Sprite = null;
                        for (group.sprite_indices.items) |sprite_idx| {
                            const sprite_obj = &texture_manager.sprites.items[sprite_idx].sprite;
                            if (sprite_obj.name.rotation == current_rotation) {
                                animation_sprite = sprite_obj;
                                break;
                            }
                        }

                        // If we found a sprite, handle its animation
                        if (animation_sprite) |anim_sprite| {
                            // Handle animation
                            if (group.is_animating) {
                                anim_sprite.play();
                            } else {
                                anim_sprite.stop();
                            }
                            anim_sprite.update();

                            // Get the current frame letter
                            if (anim_sprite.getCurrentFrame()) |current_frame| {
                                // Find the sprite that matches both rotation and current frame
                                for (group.sprite_indices.items) |sprite_idx| {
                                    const sprite_obj = &texture_manager.sprites.items[sprite_idx].sprite;
                                    if (sprite_obj.name.rotation == current_rotation and
                                        sprite_obj.name.frame == current_frame)
                                    {
                                        break :blk sprite_obj;
                                    }
                                }
                            }
                        }
                        break :blk animation_sprite; // Fall back to the animation sprite if no exact match
                    };

                    if (current_sprite) |sprite_obj| {
                        // Render sprite
                        const surface = sprite_obj.render(&texture_manager.playpal.?, current_palette, current_rotation) catch |err| {
                            std.debug.print("Failed to render sprite: {any}\n", .{err});
                            continue;
                        };
                        defer c.SDL_FreeSurface(@ptrCast(surface));

                        // Create texture from surface
                        const sdl_texture = c.SDL_CreateTextureFromSurface(renderer, @ptrCast(surface)) orelse {
                            std.debug.print("Failed to create texture: {s}\n", .{c.SDL_GetError()});
                            continue;
                        };
                        defer c.SDL_DestroyTexture(sdl_texture);

                        // Draw texture
                        var dest_rect = c.SDL_Rect{
                            .x = @intCast(@divTrunc(@as(i32, 800) - @as(i32, @intCast(sprite_obj.picture.header.width * 2)), 2)),
                            .y = @intCast(500 - @as(i32, @intCast(sprite_obj.picture.header.height * 2))),
                            .w = @intCast(sprite_obj.picture.header.width * 2),
                            .h = @intCast(sprite_obj.picture.header.height * 2),
                        };
                        _ = c.SDL_RenderCopy(renderer, sdl_texture, null, &dest_rect);

                        // Draw sprite info
                        var info_buf: [256]u8 = undefined;
                        _ = try std.fmt.bufPrint(&info_buf, "Sprite Group: {s} Frame: {d}/{d} Rotation: {d} {s} ({d}x{d})\x00", .{
                            group.prefix,
                            if (sprite_obj.animation) |anim| anim.current_frame + 1 else 1,
                            group.frame_sequence.len,
                            current_rotation,
                            if (group.is_animating) "(Animating)" else "",
                            sprite_obj.picture.header.width,
                            sprite_obj.picture.header.height,
                        });

                        const text_color = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
                        const text_surface = c.TTF_RenderText_Solid(font, &info_buf, text_color) orelse {
                            std.debug.print("Failed to render text: {s}\n", .{c.TTF_GetError()});
                            continue;
                        };
                        defer c.SDL_FreeSurface(text_surface);

                        const text_texture = c.SDL_CreateTextureFromSurface(renderer, text_surface) orelse {
                            std.debug.print("Failed to create texture: {s}\n", .{c.SDL_GetError()});
                            continue;
                        };
                        defer c.SDL_DestroyTexture(text_texture);

                        var text_rect = c.SDL_Rect{
                            .x = 50,
                            .y = 10,
                            .w = text_surface.*.w,
                            .h = text_surface.*.h,
                        };
                        _ = c.SDL_RenderCopy(renderer, text_texture, null, &text_rect);
                    }
                }
            },
            .Palettes => {
                if (texture_manager.playpal) |pal| {
                    // Draw current palette
                    const cell_size: c_int = 32;
                    const start_x: c_int = 50;
                    const start_y: c_int = 50;

                    var i: usize = 0;
                    while (i < 256) : (i += 1) {
                        const x = start_x + @as(c_int, @intCast(i % 16)) * cell_size;
                        const y = start_y + @as(c_int, @intCast(i / 16)) * cell_size;

                        const rgb = pal.getColor(current_palette, @intCast(i));
                        _ = c.SDL_SetRenderDrawColor(renderer, rgb[0], rgb[1], rgb[2], 255);

                        const rect = c.SDL_Rect{
                            .x = x,
                            .y = y,
                            .w = cell_size - 1,
                            .h = cell_size - 1,
                        };
                        _ = c.SDL_RenderFillRect(renderer, &rect);
                    }

                    // Draw palette info
                    var info_buf: [256]u8 = undefined;
                    const info_text = try std.fmt.bufPrint(&info_buf, "Palette {d}/13", .{current_palette});

                    const text_color = c.SDL_Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
                    const text_surface = c.TTF_RenderText_Solid(font, info_text.ptr, text_color) orelse {
                        std.debug.print("Failed to render text: {s}\n", .{c.TTF_GetError()});
                        continue;
                    };
                    defer c.SDL_FreeSurface(text_surface);

                    const text_texture = c.SDL_CreateTextureFromSurface(renderer, text_surface) orelse {
                        std.debug.print("Failed to create texture: {s}\n", .{c.SDL_GetError()});
                        continue;
                    };
                    defer c.SDL_DestroyTexture(text_texture);

                    var text_rect = c.SDL_Rect{
                        .x = 50,
                        .y = 10,
                        .w = text_surface.*.w,
                        .h = text_surface.*.h,
                    };
                    _ = c.SDL_RenderCopy(renderer, text_texture, null, &text_rect);
                }
            },
            .Textures => {
                // TODO: Implement texture viewing
            },
        }

        // Present the rendered frame
        c.SDL_RenderPresent(renderer);

        // Cap frame rate
        c.SDL_Delay(16);
    }
}

fn renderText(
    renderer: *c.SDL_Renderer,
    font: *c.TTF_Font,
    comptime fmt: []const u8,
    args: anytype,
    x: c_int,
    y: c_int,
    color: u32,
) !void {
    var buf: [1024]u8 = undefined;
    const text = try std.fmt.bufPrint(&buf, fmt, args);

    const r = @as(u8, @truncate((color >> 24) & 0xFF));
    const g = @as(u8, @truncate((color >> 16) & 0xFF));
    const b = @as(u8, @truncate((color >> 8) & 0xFF));
    const a = @as(u8, @truncate(color & 0xFF));

    const sdl_color = c.SDL_Color{
        .r = r,
        .g = g,
        .b = b,
        .a = a,
    };

    const surface = c.TTF_RenderText_Blended(font, text.ptr, sdl_color) orelse {
        std.debug.print("Failed to render text: {s}\n", .{c.TTF_GetError()});
        return error.TextRenderFailed;
    };
    defer c.SDL_FreeSurface(surface);

    const texture = c.SDL_CreateTextureFromSurface(renderer, surface) orelse {
        std.debug.print("Failed to create texture from text: {s}\n", .{c.SDL_GetError()});
        return error.TextureCreateFailed;
    };
    defer c.SDL_DestroyTexture(texture);

    var rect = c.SDL_Rect{
        .x = x,
        .y = y,
        .w = surface.*.w,
        .h = surface.*.h,
    };

    _ = c.SDL_RenderCopy(renderer, texture, null, &rect);
}
