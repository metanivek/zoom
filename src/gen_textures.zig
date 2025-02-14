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

    const TEXTURE_SIZE = 64;

    // Create surfaces for different wall textures
    const surfaces = [_]struct { name: []const u8, surface: *c.SDL_Surface }{
        // Wall 1: Simple red brick pattern
        .{
            .name = "wall1",
            .surface = try createBrickTexture(TEXTURE_SIZE, 0x3333AA),
        },
        // Wall 2: Simple gray stone pattern
        .{
            .name = "wall2",
            .surface = try createStoneTexture(TEXTURE_SIZE, 0x888888),
        },
        // Wall 3: Simple brown wood pattern
        .{
            .name = "wall3",
            .surface = try createWoodTexture(TEXTURE_SIZE, 0x13458B),
        },
        // Wall 4: Vertical stripe pattern
        .{
            .name = "stripes",
            .surface = try createVerticalStripeTexture(TEXTURE_SIZE, 0x3333AA, 0x666666, 8), // 8 pixel wide stripes
        },
    };

    // Save textures
    for (surfaces) |texture| {
        const path = try std.fmt.allocPrint(
            std.heap.page_allocator,
            "assets/textures/{s}.bmp",
            .{texture.name},
        );
        defer std.heap.page_allocator.free(path);

        if (c.SDL_SaveBMP(texture.surface, path.ptr) < 0) {
            std.debug.print("Failed to save texture: {s}\n", .{c.SDL_GetError()});
            return error.SaveTextureFailed;
        }
        c.SDL_FreeSurface(texture.surface);
    }
}

fn createSurface(size: u32) !*c.SDL_Surface {
    // Create a 24-bit RGB surface (no alpha channel)
    // On little-endian systems (like x86), bytes are stored as BGR
    // On big-endian systems, bytes are stored as RGB
    const rmask: u32 = if (c.SDL_BYTEORDER == c.SDL_BIG_ENDIAN) 0xFF0000 else 0x0000FF;
    const gmask: u32 = 0x00FF00; // Green mask is the same for both endianness
    const bmask: u32 = if (c.SDL_BYTEORDER == c.SDL_BIG_ENDIAN) 0x0000FF else 0xFF0000;

    const surface = c.SDL_CreateRGBSurface(0, @intCast(size), @intCast(size), 24, rmask, gmask, bmask, 0) orelse {
        std.debug.print("Failed to create surface: {s}\n", .{c.SDL_GetError()});
        return error.CreateSurfaceFailed;
    };
    return surface;
}

fn setPixel(surface: *c.SDL_Surface, x: u32, y: u32, color: u32) void {
    const pixels = @as([*]u8, @ptrCast(surface.*.pixels));
    const pitch = @as(u32, @intCast(surface.*.pitch));
    const bpp = @as(u32, @intCast(surface.*.format.*.BytesPerPixel));

    const offset = y * pitch + x * bpp;

    // Extract RGB components
    const r = @as(u8, @truncate((color >> 16) & 0xFF));
    const g = @as(u8, @truncate((color >> 8) & 0xFF));
    const b = @as(u8, @truncate(color & 0xFF));

    // Store in correct byte order based on endianness
    if (c.SDL_BYTEORDER == c.SDL_BIG_ENDIAN) {
        pixels[offset + 0] = r;
        pixels[offset + 1] = g;
        pixels[offset + 2] = b;
    } else {
        pixels[offset + 0] = b;
        pixels[offset + 1] = g;
        pixels[offset + 2] = r;
    }
}

fn createBrickTexture(size: u32, base_color: u32) !*c.SDL_Surface {
    const surface = try createSurface(size);

    // Simple brick pattern
    const brick_height = size / 4; // 4 rows of bricks
    const brick_width = size / 2; // 2 bricks per row
    const mortar_size = 2; // 2 pixel mortar lines
    const mortar_color = 0x666666; // Gray is same in both formats

    var y: u32 = 0;
    while (y < size) : (y += 1) {
        const row = y / brick_height;
        const row_offset = if (row % 2 == 0) 0 else brick_width / 2;
        const is_h_mortar = y % brick_height < mortar_size;

        var x: u32 = 0;
        while (x < size) : (x += 1) {
            const effective_x = (x + row_offset) % size;
            const is_v_mortar = effective_x % brick_width < mortar_size;

            const color = if (is_h_mortar or is_v_mortar)
                mortar_color
            else
                base_color;

            setPixel(surface, x, y, color);
        }
    }

    return surface;
}

fn createStoneTexture(size: u32, base_color: u32) !*c.SDL_Surface {
    const surface = try createSurface(size);

    // Simple stone block pattern
    const block_size = size / 4; // 4x4 grid of blocks
    const gap_size = 2; // 2 pixel gaps
    const gap_color = 0x666666; // Simple gray gaps

    var y: u32 = 0;
    while (y < size) : (y += 1) {
        var x: u32 = 0;
        while (x < size) : (x += 1) {
            const is_gap = (x % block_size < gap_size) or (y % block_size < gap_size);
            const color = if (is_gap) gap_color else base_color;
            setPixel(surface, x, y, color);
        }
    }

    return surface;
}

fn createWoodTexture(size: u32, base_color: u32) !*c.SDL_Surface {
    const surface = try createSurface(size);

    // Simple wood plank pattern
    const plank_height = size / 4; // 4 planks
    const plank_gap = 2; // 2 pixel gaps
    const gap_color = 0x663300; // Dark brown gaps

    var y: u32 = 0;
    while (y < size) : (y += 1) {
        const is_gap = y % plank_height < plank_gap;
        var x: u32 = 0;
        while (x < size) : (x += 1) {
            const color = if (is_gap) gap_color else base_color;
            setPixel(surface, x, y, color);
        }
    }

    return surface;
}

fn createVerticalStripeTexture(size: u32, color1: u32, color2: u32, stripe_width: u32) !*c.SDL_Surface {
    const surface = try createSurface(size);

    var y: u32 = 0;
    while (y < size) : (y += 1) {
        var x: u32 = 0;
        while (x < size) : (x += 1) {
            // Use x position to determine stripe color
            const stripe_index = x / stripe_width;
            const color = if (stripe_index % 2 == 0) color1 else color2;
            setPixel(surface, x, y, color);
        }
    }

    return surface;
}
