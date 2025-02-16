const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL_ttf.h");
});
const lib = @import("lib");

const wad = lib.wad;
const doom_textures = lib.doom_textures;
const tex = lib.texture;
const patch = lib.graphics.patch;
const picture = lib.graphics.picture;
const sprite = lib.graphics.sprite;
const flat = lib.graphics.flat;

const ViewMode = enum {
    Palettes,
    Patches,
    Textures,
    Sprites,
    Flats,
};

const SpriteGroup = struct {
    prefix: []const u8,
    sprite_indices: std.ArrayList(usize), // Indices into texture_manager.sprites
    frame_sequences: [9]std.ArrayList(u8), // Frame sequences for each rotation (0-8)
    current_rotation: u8 = 0,
    is_animating: bool = false,

    pub fn init(allocator: std.mem.Allocator, prefix: []const u8) !SpriteGroup {
        var group = SpriteGroup{
            .prefix = try allocator.dupe(u8, prefix),
            .sprite_indices = std.ArrayList(usize).init(allocator),
            .frame_sequences = undefined,
            .is_animating = false,
        };
        // Initialize frame sequences for each rotation
        for (&group.frame_sequences) |*seq| {
            seq.* = std.ArrayList(u8).init(allocator);
        }
        return group;
    }

    pub fn deinit(self: *SpriteGroup, allocator: std.mem.Allocator) void {
        allocator.free(self.prefix);
        for (&self.frame_sequences) |*seq| {
            seq.deinit();
        }
        self.sprite_indices.deinit();
    }

    /// Add a frame letter to the sequence for a specific rotation
    pub fn addFrameLetter(self: *SpriteGroup, rotation: u8, frame: u8) !void {
        if (rotation > 8) return;
        // Check if frame letter already exists for this rotation
        for (self.frame_sequences[rotation].items) |existing_frame| {
            if (existing_frame == frame) return;
        }
        // Add new frame letter
        try self.frame_sequences[rotation].append(frame);
    }

    /// Get the frame sequence for a specific rotation
    pub fn getFrameSequence(self: *const SpriteGroup, rotation: u8) []const u8 {
        if (rotation > 8) return &[_]u8{};
        return self.frame_sequences[rotation].items;
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

    var texture_manager = tex.TextureManager.init(allocator);
    defer texture_manager.deinit();

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

    // Load all textures from WAD
    try texture_manager.loadFromWad(&wad_file);

    // Main loop variables
    var quit = false;
    var view_mode = ViewMode.Patches;
    var current_patch: usize = 0;
    var current_flat: usize = 0;
    var current_texture: usize = 0;
    var current_palette: u8 = 0;
    var current_rotation: u8 = 0;
    var current_group: usize = 0;

    // Create sprite groups
    var sprite_groups = std.ArrayList(SpriteGroup).init(allocator);
    defer {
        for (sprite_groups.items) |*group| {
            group.deinit(allocator);
        }
        sprite_groups.deinit();
    }

    // Group sprites by prefix
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

            // Add frame letter to the appropriate rotation sequence
            const sprite_obj = &sprite_entry.sprite;
            // For primary rotation
            try sprite_groups.items[group_idx].addFrameLetter(sprite_obj.name.first.rotation, sprite_obj.name.first.frame);
            // For second rotation/frame
            if (sprite_obj.name.second) |second| {
                try sprite_groups.items[group_idx].addFrameLetter(second.rotation, second.frame);
            }
        }

        // Sort frame sequences for consistent animation order
        for (sprite_groups.items) |*group| {
            for (&group.frame_sequences) |*seq| {
                std.mem.sort(u8, seq.items, {}, std.sort.asc(u8));
            }
        }

        // Set up animations for all sprites
        for (sprite_groups.items) |*group| {
            for (group.sprite_indices.items) |sprite_idx| {
                var sprite_obj = &texture_manager.sprites.items[sprite_idx].sprite;
                // Set up animation for both first and second rotations if they exist
                const first_sequence = group.getFrameSequence(sprite_obj.name.first.rotation);
                if (first_sequence.len > 0) {
                    try sprite_obj.setupAnimation(first_sequence);
                }
                if (sprite_obj.name.second) |second| {
                    const second_sequence = group.getFrameSequence(second.rotation);
                    if (second_sequence.len > 0) {
                        try sprite_obj.setupAnimation(second_sequence);
                    }
                }
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
                        c.SDLK_q => quit = true,
                        c.SDLK_m => {
                            // Cycle view mode
                            view_mode = switch (view_mode) {
                                .Palettes => .Patches,
                                .Patches => .Textures,
                                .Textures => .Sprites,
                                .Sprites => .Flats,
                                .Flats => .Palettes,
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
                            .Flats => {
                                if (texture_manager.flats.items.len > 0 and current_flat > 0) {
                                    current_flat -= 1;
                                }
                            },
                            .Textures => {
                                if (texture_manager.composite_textures.items.len > 0 and current_texture > 0) {
                                    current_texture -= 1;
                                }
                            },
                            .Palettes => {
                                if (current_palette > 0) {
                                    current_palette -= 1;
                                }
                            },
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
                            .Flats => {
                                if (texture_manager.flats.items.len > 0 and current_flat < texture_manager.flats.items.len - 1) {
                                    current_flat += 1;
                                }
                            },
                            .Textures => {
                                if (texture_manager.composite_textures.items.len > 0 and current_texture < texture_manager.composite_textures.items.len - 1) {
                                    current_texture += 1;
                                }
                            },
                            .Palettes => {
                                if (current_palette < 13) {
                                    current_palette += 1;
                                }
                            },
                        },
                        c.SDLK_SPACE => switch (view_mode) {
                            .Sprites => {
                                if (sprite_groups.items.len > 0) {
                                    const group = &sprite_groups.items[current_group];
                                    group.is_animating = !group.is_animating;
                                    // Find sprite with current rotation and toggle its animation
                                    for (group.sprite_indices.items) |sprite_idx| {
                                        var sprite_obj = &texture_manager.sprites.items[sprite_idx].sprite;
                                        if (sprite_obj.name.first.rotation == current_rotation) {
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
                    const surface = current_patch_obj.render(texture_manager.playpal.?, current_palette) catch |err| {
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

                    // Always show sprite group info at the top
                    var info_buf: [256]u8 = undefined;
                    _ = try std.fmt.bufPrint(&info_buf, "Sprite Group: {s} Frames: {d} Rotation: {d} {s}\x00", .{
                        group.prefix,
                        group.frame_sequences[current_rotation].items.len,
                        current_rotation,
                        if (group.is_animating) "(Animating)" else "",
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

                    // Draw list of sprite lump names that are used in the current rotation's animation
                    var y_offset: c_int = 50;
                    const frame_sequence = group.frame_sequences[current_rotation].items;

                    // First show the frame sequence for this rotation
                    var sequence_buf: [256]u8 = undefined;
                    _ = try std.fmt.bufPrint(&sequence_buf, "Frame sequence: {s}\x00", .{frame_sequence});
                    const sequence_surface = c.TTF_RenderText_Solid(font, &sequence_buf, text_color) orelse {
                        std.debug.print("Failed to render text: {s}\n", .{c.TTF_GetError()});
                        continue;
                    };
                    defer c.SDL_FreeSurface(sequence_surface);

                    const sequence_texture = c.SDL_CreateTextureFromSurface(renderer, sequence_surface) orelse {
                        std.debug.print("Failed to create texture: {s}\n", .{c.SDL_GetError()});
                        continue;
                    };
                    defer c.SDL_DestroyTexture(sequence_texture);

                    var sequence_rect = c.SDL_Rect{
                        .x = 20,
                        .y = y_offset,
                        .w = sequence_surface.*.w,
                        .h = sequence_surface.*.h,
                    };
                    _ = c.SDL_RenderCopy(renderer, sequence_texture, null, &sequence_rect);
                    y_offset += 30;

                    // Then show matching lumps
                    for (group.sprite_indices.items) |sprite_idx| {
                        const sprite_entry = &texture_manager.sprites.items[sprite_idx];
                        const sprite_obj = &sprite_entry.sprite;

                        // Only show lumps that match the current rotation's frame sequence
                        const matches_rotation = sprite_obj.name.first.rotation == current_rotation or
                            if (sprite_obj.name.second) |second| second.rotation == current_rotation else false;
                        const frame_in_sequence = for (frame_sequence) |frame| {
                            if (sprite_obj.name.first.rotation == current_rotation and sprite_obj.name.first.frame == frame) {
                                break true;
                            }
                            if (sprite_obj.name.second) |second| {
                                if (second.rotation == current_rotation and second.frame == frame) {
                                    break true;
                                }
                            }
                        } else false;

                        if (matches_rotation and frame_in_sequence) {
                            var lump_name_buf: [256]u8 = undefined;
                            // Get the actual sprite name length by finding the first non-printable character
                            var name_len: usize = 0;
                            for (sprite_entry.name) |char| {
                                if (char < 32 or char > 126) break;
                                name_len += 1;
                            }
                            _ = try std.fmt.bufPrint(&lump_name_buf, "  {s}\x00", .{sprite_entry.name[0..name_len]});

                            const lump_text_surface = c.TTF_RenderText_Solid(font, &lump_name_buf, text_color) orelse {
                                std.debug.print("Failed to render text: {s}\n", .{c.TTF_GetError()});
                                continue;
                            };
                            defer c.SDL_FreeSurface(lump_text_surface);

                            const lump_text_texture = c.SDL_CreateTextureFromSurface(renderer, lump_text_surface) orelse {
                                std.debug.print("Failed to create texture: {s}\n", .{c.SDL_GetError()});
                                continue;
                            };
                            defer c.SDL_DestroyTexture(lump_text_texture);

                            var lump_text_rect = c.SDL_Rect{
                                .x = 20,
                                .y = y_offset,
                                .w = lump_text_surface.*.w,
                                .h = lump_text_surface.*.h,
                            };
                            _ = c.SDL_RenderCopy(renderer, lump_text_texture, null, &lump_text_rect);
                            y_offset += 20;
                        }
                    }

                    // Find sprite with current rotation
                    const found_sprite: ?*sprite.Sprite = blk: {
                        // First, find any sprite with the current rotation to handle animation
                        var animation_sprite: ?*sprite.Sprite = null;
                        for (group.sprite_indices.items) |sprite_idx| {
                            const sprite_obj = &texture_manager.sprites.items[sprite_idx].sprite;
                            // Check for direct rotation match or second rotation match
                            if (sprite_obj.name.first.rotation == current_rotation or
                                (sprite_obj.name.second != null and sprite_obj.name.second.?.rotation == current_rotation))
                            {
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

                                    // Check first rotation/frame
                                    if (sprite_obj.name.first.rotation == current_rotation and
                                        sprite_obj.name.first.frame == current_frame)
                                    {
                                        break :blk sprite_obj;
                                    }

                                    // Check second rotation/frame if it exists
                                    if (sprite_obj.name.second) |second| {
                                        if (second.rotation == current_rotation and
                                            second.frame == current_frame)
                                        {
                                            break :blk sprite_obj;
                                        }
                                    }
                                }
                            }
                        }
                        break :blk animation_sprite; // Fall back to the animation sprite if no exact match
                    };

                    if (found_sprite) |sprite_obj| {
                        // Render sprite
                        const surface = sprite_obj.render(texture_manager.playpal.?, current_palette, current_rotation) catch |err| {
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
                        var sprite_info_buf: [256]u8 = undefined;
                        _ = try std.fmt.bufPrint(&sprite_info_buf, "Size: {d}x{d}\x00", .{
                            sprite_obj.picture.header.width,
                            sprite_obj.picture.header.height,
                        });

                        const sprite_text_surface = c.TTF_RenderText_Solid(font, &sprite_info_buf, text_color) orelse {
                            std.debug.print("Failed to render text: {s}\n", .{c.TTF_GetError()});
                            continue;
                        };
                        defer c.SDL_FreeSurface(sprite_text_surface);

                        const sprite_text_texture = c.SDL_CreateTextureFromSurface(renderer, sprite_text_surface) orelse {
                            std.debug.print("Failed to create texture: {s}\n", .{c.SDL_GetError()});
                            continue;
                        };
                        defer c.SDL_DestroyTexture(sprite_text_texture);

                        var sprite_text_rect = c.SDL_Rect{
                            .x = 50,
                            .y = 550,
                            .w = sprite_text_surface.*.w,
                            .h = sprite_text_surface.*.h,
                        };
                        _ = c.SDL_RenderCopy(renderer, sprite_text_texture, null, &sprite_text_rect);
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
                    const info_text = try std.fmt.bufPrint(&info_buf, "Palette {d}/13\x00", .{current_palette});

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
            .Flats => {
                if (texture_manager.flats.items.len > 0 and texture_manager.playpal != null) {
                    const flat_entry = &texture_manager.flats.items[current_flat];
                    const current_flat_obj = &flat_entry.flat;

                    // Render flat using our render function
                    const surface = current_flat_obj.render(texture_manager.playpal.?, current_palette) catch |err| {
                        std.debug.print("Failed to render flat: {any}\n", .{err});
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
                        .w = 64 * 4, // Scale up 4x for better visibility
                        .h = 64 * 4,
                    };
                    _ = c.SDL_RenderCopy(renderer, sdl_texture, null, &dest_rect);

                    // Draw flat info
                    var info_buf: [256]u8 = undefined;
                    const info_text = try std.fmt.bufPrint(&info_buf, "Flat: {s} (64x64)\x00", .{
                        flat_entry.name,
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
            .Textures => {
                if (texture_manager.composite_textures.items.len > 0 and texture_manager.playpal != null) {
                    const texture_entry = texture_manager.composite_textures.items[current_texture];
                    const texture_obj = &texture_entry.texture;

                    // Render the composite texture
                    const surface = texture_obj.render(&texture_manager, texture_manager.playpal.?, current_palette) catch |err| {
                        std.debug.print("Failed to render texture: {any}\n", .{err});
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
                        .w = @intCast(texture_obj.width * 4), // Scale up 4x for better visibility
                        .h = @intCast(texture_obj.height * 4),
                    };
                    _ = c.SDL_RenderCopy(renderer, sdl_texture, null, &dest_rect);

                    // Draw texture info
                    var info_buf: [256]u8 = undefined;
                    const info_text = try std.fmt.bufPrint(&info_buf, "Texture: {s} ({d}x{d}) Patches: {d}\x00", .{
                        texture_entry.name,
                        texture_obj.width,
                        texture_obj.height,
                        texture_obj.patches.len,
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

                    // Draw list of patches used in this texture
                    var y_offset: i32 = 50 + @as(i32, @intCast(texture_obj.height * 4)) + 20;
                    for (texture_obj.patches) |patch_ref| {
                        var patch_buf: [256]u8 = undefined;
                        const patch_text = try std.fmt.bufPrint(&patch_buf, "  {s} at ({d}, {d})\x00", .{
                            patch_ref.patch_name,
                            patch_ref.x_offset,
                            patch_ref.y_offset,
                        });

                        const patch_text_surface = c.TTF_RenderText_Solid(font, patch_text.ptr, text_color) orelse {
                            std.debug.print("Failed to render text: {s}\n", .{c.TTF_GetError()});
                            continue;
                        };
                        defer c.SDL_FreeSurface(patch_text_surface);

                        const patch_text_texture = c.SDL_CreateTextureFromSurface(renderer, patch_text_surface) orelse {
                            std.debug.print("Failed to create texture: {s}\n", .{c.SDL_GetError()});
                            continue;
                        };
                        defer c.SDL_DestroyTexture(patch_text_texture);

                        var patch_text_rect = c.SDL_Rect{
                            .x = 50,
                            .y = y_offset,
                            .w = patch_text_surface.*.w,
                            .h = patch_text_surface.*.h,
                        };
                        _ = c.SDL_RenderCopy(renderer, patch_text_texture, null, &patch_text_rect);
                        y_offset += 20;
                    }
                }
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
