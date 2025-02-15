const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const doom_textures = @import("../doom_textures.zig");
pub const Picture = @import("picture.zig").Picture;

pub const Error = error{
    RenderError,
};

/// A patch is a graphic resource that can be used as part of a wall texture
/// It extends the base Picture format with rendering capabilities
pub const Patch = struct {
    picture: Picture,

    /// Load a patch from WAD lump data
    pub fn load(allocator: std.mem.Allocator, data: []const u8) !Patch {
        return Patch{
            .picture = try Picture.load(allocator, data),
        };
    }

    pub fn deinit(self: *Patch) void {
        self.picture.deinit();
    }

    /// Get the pixel at the given coordinates
    /// Returns null if the pixel is transparent
    pub fn getPixel(self: *const Patch, x: u32, y: u32) ?u8 {
        return self.picture.getPixel(x, y);
    }

    /// Render the patch to an SDL surface using the given palette
    pub fn render(self: *const Patch, playpal: *const doom_textures.Playpal, palette_index: u8) !*c.SDL_Surface {
        const surface = c.SDL_CreateRGBSurface(0, @intCast(self.picture.header.width), @intCast(self.picture.header.height), 32, 0xFF000000, 0x00FF0000, 0x0000FF00, 0x000000FF) orelse {
            return error.RenderError;
        };
        errdefer c.SDL_FreeSurface(surface);

        // Fill with transparent black
        _ = c.SDL_FillRect(surface, null, 0);

        // Lock surface for direct pixel access
        if (c.SDL_LockSurface(surface) < 0) {
            return error.RenderError;
        }
        defer c.SDL_UnlockSurface(surface);

        const pixels = @as([*]u32, @ptrCast(@alignCast(surface.*.pixels)));
        const pitch = @divExact(surface.*.pitch, @sizeOf(u32));

        // Draw each column
        for (0..@as(u32, @intCast(self.picture.header.width))) |x| {
            for (0..@as(u32, @intCast(self.picture.header.height))) |y| {
                if (self.getPixel(@intCast(x), @intCast(y))) |color_idx| {
                    const color = playpal.palettes[palette_index][color_idx];
                    const pixel_offset = y * @as(usize, @intCast(pitch)) + x;
                    pixels[pixel_offset] = ((@as(u32, color[0]) << 24) |
                        (@as(u32, color[1]) << 16) |
                        (@as(u32, color[2]) << 8) |
                        0xFF);
                }
            }
        }

        return surface;
    }
};

test {
    std.testing.refAllDecls(@This());
}

test "load and render patch" {
    const allocator = std.testing.allocator;

    // Create test data using the Picture format
    const column_data = [_]u8{
        0x00, // row
        0x02, // length
        0x00, // padding
        0x01, 0x02, // pixel data
        0x00, // padding
        0xFF, // end of column marker
    };

    var picture_data = std.ArrayList(u8).init(allocator);
    defer picture_data.deinit();

    // Write header
    try picture_data.writer().writeInt(i16, 1, .little); // width
    try picture_data.writer().writeInt(i16, 2, .little); // height
    try picture_data.writer().writeInt(i16, 0, .little); // left_offset
    try picture_data.writer().writeInt(i16, 0, .little); // top_offset

    // Write column offset - point to just after the column offsets
    try picture_data.writer().writeInt(u32, 0, .little); // offset relative to picture_data_start

    // Write column data
    try picture_data.appendSlice(&column_data);

    // Load patch
    var test_patch = try Patch.load(allocator, picture_data.items);
    defer test_patch.deinit();

    // Create mock playpal for testing
    var mock_playpal = doom_textures.Playpal{
        .palettes = undefined,
        .allocator = allocator,
    };
    // Set all colors to red for testing
    for (0..14) |palette| {
        for (0..256) |color| {
            mock_playpal.palettes[palette][color] = .{ 255, 0, 0 };
        }
    }

    // Render the patch
    const surface = try test_patch.render(&mock_playpal, 0);
    defer c.SDL_FreeSurface(surface);

    // Verify surface properties
    try std.testing.expectEqual(@as(c_int, 1), surface.*.w);
    try std.testing.expectEqual(@as(c_int, 2), surface.*.h);
    try std.testing.expectEqual(@as(c_int, 32), surface.*.format.*.BitsPerPixel);

    // Lock surface to check pixel values
    if (c.SDL_LockSurface(surface) < 0) {
        return error.RenderError;
    }
    defer c.SDL_UnlockSurface(surface);

    const pixels = @as([*]u32, @ptrCast(@alignCast(surface.*.pixels)));
    const pitch = @divExact(surface.*.pitch, @sizeOf(u32));
    const pitch_usize = @as(usize, @intCast(pitch));

    // Check pixel values
    try std.testing.expectEqual(@as(u32, 0xFF0000FF), pixels[0]); // First pixel should be red
    try std.testing.expectEqual(@as(u32, 0xFF0000FF), pixels[pitch_usize]); // Second pixel should be red
}
