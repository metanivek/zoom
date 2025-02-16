const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const doom_textures = @import("../doom_textures.zig");

pub const Error = error{
    InvalidSize,
    RenderError,
};

/// A flat is a 64x64 raw pixel texture used for floors and ceilings
pub const Flat = struct {
    /// Raw pixel data (64x64 bytes)
    pixels: []u8,
    allocator: std.mem.Allocator,

    /// Load a flat from WAD lump data
    /// Flats are raw pixel data, 64x64 bytes in size
    pub fn load(allocator: std.mem.Allocator, data: []const u8) !Flat {
        if (data.len != 64 * 64) {
            return Error.InvalidSize;
        }

        // Allocate and copy pixel data
        const pixels = try allocator.dupe(u8, data);
        errdefer allocator.free(pixels);

        return Flat{
            .pixels = pixels,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Flat) void {
        self.allocator.free(self.pixels);
    }

    /// Get the pixel at the given coordinates
    pub fn getPixel(self: *const Flat, x: u32, y: u32) u8 {
        if (x >= 64 or y >= 64) return 0;
        return self.pixels[y * 64 + x];
    }

    /// Render the flat to an SDL surface using the given palette
    pub fn render(self: *const Flat, playpal: *const doom_textures.Playpal, palette_index: u8) !*c.SDL_Surface {
        const surface = c.SDL_CreateRGBSurface(0, 64, 64, 32, 0xFF000000, 0x00FF0000, 0x0000FF00, 0x000000FF) orelse {
            return error.RenderError;
        };
        errdefer c.SDL_FreeSurface(surface);

        // Lock surface for direct pixel access
        if (c.SDL_LockSurface(surface) < 0) {
            return error.RenderError;
        }
        defer c.SDL_UnlockSurface(surface);

        const pixels = @as([*]u32, @ptrCast(@alignCast(surface.*.pixels)));
        const pitch = @divExact(surface.*.pitch, @sizeOf(u32));

        // Draw each pixel
        for (0..64) |y| {
            for (0..64) |x| {
                const color_idx = self.getPixel(@intCast(x), @intCast(y));
                const color = playpal.palettes[palette_index][color_idx];
                const pixel_offset = y * @as(usize, @intCast(pitch)) + x;
                pixels[pixel_offset] = ((@as(u32, color[0]) << 24) |
                    (@as(u32, color[1]) << 16) |
                    (@as(u32, color[2]) << 8) |
                    0xFF);
            }
        }

        return surface;
    }
};

test "Flat - load and pixel access" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create test data (64x64 = 4096 bytes)
    var test_data: [64 * 64]u8 = undefined;
    for (0..64 * 64) |i| {
        test_data[i] = @truncate(i);
    }

    // Test loading
    var flat = try Flat.load(allocator, &test_data);
    defer flat.deinit();

    // Test dimensions
    try testing.expectEqual(@as(usize, 64 * 64), flat.pixels.len);

    // Test pixel access
    try testing.expectEqual(@as(u8, 0), flat.getPixel(0, 0));
    try testing.expectEqual(@as(u8, 65), flat.getPixel(1, 1));
    try testing.expectEqual(@as(u8, 127), flat.getPixel(63, 1));

    // Test out of bounds access
    try testing.expectEqual(@as(u8, 0), flat.getPixel(64, 0));
    try testing.expectEqual(@as(u8, 0), flat.getPixel(0, 64));
}

test "Flat - invalid size" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test data with wrong size
    var invalid_data = [_]u8{0} ** 32;
    try testing.expectError(Error.InvalidSize, Flat.load(allocator, &invalid_data));
}

test {
    std.testing.refAllDecls(@This());
}
