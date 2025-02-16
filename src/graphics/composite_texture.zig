const std = @import("std");
const wad = @import("../wad.zig");
const patch = @import("patch.zig");
const doom_textures = @import("../doom_textures.zig");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub const Error = error{
    InvalidTextureData,
    TextureNameTooLong,
    AllocationFailed,
    InvalidPnamesData,
    PatchIndexOutOfBounds,
    PatchNotFound,
    RenderError,
};

/// Reference to a patch within a composite texture
pub const PatchRef = struct {
    patch_name: []const u8,
    x_offset: i16,
    y_offset: i16,
};

/// Holds the mapping of patch indices to patch names
pub const PatchNames = struct {
    names: [][]const u8,
    allocator: std.mem.Allocator,

    /// Parse the PNAMES lump data
    pub fn parse(allocator: std.mem.Allocator, data: []const u8) !PatchNames {
        if (data.len < 4) {
            return Error.InvalidPnamesData;
        }

        // Read number of patch names
        const num_names = std.mem.readInt(u32, data[0..4], .little);

        // Ensure we have enough data
        if (data.len < 4 + num_names * 8) {
            return Error.InvalidPnamesData;
        }

        // Allocate array for names
        var names = try allocator.alloc([]const u8, num_names);
        errdefer {
            for (names) |name| {
                allocator.free(name);
            }
            allocator.free(names);
        }

        // Read each patch name (8 bytes each, null-terminated)
        var offset: usize = 4;
        for (0..num_names) |i| {
            var name_len: usize = 0;
            while (name_len < 8 and data[offset + name_len] != 0) : (name_len += 1) {}
            names[i] = try allocator.dupe(u8, data[offset .. offset + name_len]);
            offset += 8;
        }

        return PatchNames{
            .names = names,
            .allocator = allocator,
        };
    }

    /// Get patch name by index
    pub fn getName(self: *const PatchNames, index: usize) ![]const u8 {
        if (index >= self.names.len) {
            return Error.PatchIndexOutOfBounds;
        }
        return self.names[index];
    }

    /// Free allocated memory
    pub fn deinit(self: *PatchNames) void {
        for (self.names) |name| {
            self.allocator.free(name);
        }
        self.allocator.free(self.names);
    }

    /// Initialize PatchNames with a given allocator and patch names
    pub fn init(allocator: std.mem.Allocator, names: []const []const u8) !PatchNames {
        var patch_names = try allocator.alloc([]const u8, names.len);
        errdefer {
            for (patch_names) |name| {
                allocator.free(name);
            }
            allocator.free(patch_names);
        }

        for (0..names.len) |i| {
            patch_names[i] = try allocator.dupe(u8, names[i]);
        }

        return PatchNames{
            .names = patch_names,
            .allocator = allocator,
        };
    }
};

/// Definition of a composite texture
pub const CompositeTexture = struct {
    name: []const u8,
    width: u16,
    height: u16,
    patches: []PatchRef,
    allocator: std.mem.Allocator,

    /// Parse a composite texture definition from WAD data
    pub fn parse(allocator: std.mem.Allocator, data: []const u8, offset: *usize, patch_names: *const PatchNames) !CompositeTexture {
        // Ensure we have enough data for the header
        if (data.len - offset.* < 8 + 2 + 2 + 2) {
            return Error.InvalidTextureData;
        }

        // Read texture name (8 bytes, null-terminated)
        var name_len: usize = 0;
        while (name_len < 8 and data[offset.* + name_len] != 0) : (name_len += 1) {}
        const name = try allocator.dupe(u8, data[offset.* .. offset.* + name_len]);
        errdefer allocator.free(name);
        offset.* += 8;

        // Skip unused fields (4 bytes)
        offset.* += 4;

        // Read dimensions
        const width_bytes: *const [2]u8 = @ptrCast(data[offset.* .. offset.* + 2]);
        const width = std.mem.readInt(u16, width_bytes, .little);
        offset.* += 2;

        const height_bytes: *const [2]u8 = @ptrCast(data[offset.* .. offset.* + 2]);
        const height = std.mem.readInt(u16, height_bytes, .little);
        offset.* += 2;

        // Skip unused fields (4 bytes)
        offset.* += 4;

        // Read number of patches
        const num_patches_bytes: *const [2]u8 = @ptrCast(data[offset.* .. offset.* + 2]);
        const num_patches = std.mem.readInt(u16, num_patches_bytes, .little);
        offset.* += 2;

        // Allocate patch array
        var i: usize = 0;
        var patches = try allocator.alloc(PatchRef, num_patches);
        errdefer {
            for (0..i) |j| {
                allocator.free(patches[j].patch_name);
            }
            allocator.free(patches);
        }

        // Read patch references
        while (i < num_patches) : (i += 1) {
            // Read x and y offsets
            const x_offset_bytes: *const [2]u8 = @ptrCast(data[offset.* .. offset.* + 2]);
            const x_offset = std.mem.readInt(i16, x_offset_bytes, .little);
            offset.* += 2;

            const y_offset_bytes: *const [2]u8 = @ptrCast(data[offset.* .. offset.* + 2]);
            const y_offset = std.mem.readInt(i16, y_offset_bytes, .little);
            offset.* += 2;

            // Read patch index and look up name
            const patch_idx_bytes: *const [2]u8 = @ptrCast(data[offset.* .. offset.* + 2]);
            const patch_idx = std.mem.readInt(u16, patch_idx_bytes, .little);
            offset.* += 2;

            // Skip unused fields (4 bytes)
            offset.* += 4;

            // Look up patch name using the index
            const patch_name = try patch_names.getName(patch_idx);
            const patch_name_copy = try allocator.dupe(u8, patch_name);
            errdefer allocator.free(patch_name_copy);

            patches[i] = .{
                .patch_name = patch_name_copy,
                .x_offset = x_offset,
                .y_offset = y_offset,
            };
        }

        return CompositeTexture{
            .name = name,
            .width = width,
            .height = height,
            .patches = patches,
            .allocator = allocator,
        };
    }

    /// Render the composite texture using the provided patches and palette
    pub fn render(
        self: *const CompositeTexture,
        texture_manager: *const @import("../texture.zig").TextureManager,
        playpal: *const doom_textures.Playpal,
        palette: u8,
    ) !*c.SDL_Surface {
        // Create surface for the composite texture
        const rmask: u32 = if (c.SDL_BYTEORDER == c.SDL_BIG_ENDIAN) 0xFF000000 else 0x000000FF;
        const gmask: u32 = if (c.SDL_BYTEORDER == c.SDL_BIG_ENDIAN) 0x00FF0000 else 0x0000FF00;
        const bmask: u32 = if (c.SDL_BYTEORDER == c.SDL_BIG_ENDIAN) 0x0000FF00 else 0x00FF0000;
        const amask: u32 = if (c.SDL_BYTEORDER == c.SDL_BIG_ENDIAN) 0x000000FF else 0xFF000000;

        const surface = c.SDL_CreateRGBSurface(
            0,
            @intCast(self.width),
            @intCast(self.height),
            32,
            rmask,
            gmask,
            bmask,
            amask,
        ) orelse {
            return Error.RenderError;
        };
        errdefer c.SDL_FreeSurface(surface);

        // Lock surface for pixel access
        if (c.SDL_LockSurface(surface) < 0) {
            return Error.RenderError;
        }
        defer c.SDL_UnlockSurface(surface);

        // Get surface pixels as u32 array for direct access
        const pixels = @as([*]u32, @ptrCast(@alignCast(surface.*.pixels)));
        const pitch = @divExact(@as(usize, @intCast(surface.*.pitch)), @sizeOf(u32));

        // Clear surface with transparency
        for (0..@as(usize, @intCast(self.height))) |y| {
            for (0..@as(usize, @intCast(self.width))) |x| {
                pixels[y * pitch + x] = 0x00000000;
            }
        }

        // Draw each patch
        for (self.patches) |patch_ref| {
            // Get the patch from texture manager
            const patch_obj = texture_manager.getPatch(patch_ref.patch_name) orelse {
                return Error.PatchNotFound;
            };

            // Calculate patch bounds
            const start_x = @max(0, patch_ref.x_offset);
            const start_y = @max(0, patch_ref.y_offset);
            const end_x = @min(@as(i32, @intCast(self.width)), patch_ref.x_offset + @as(i32, @intCast(patch_obj.picture.header.width)));
            const end_y = @min(@as(i32, @intCast(self.height)), patch_ref.y_offset + @as(i32, @intCast(patch_obj.picture.header.height)));

            // Draw patch pixels
            var y: i32 = start_y;
            while (y < end_y) : (y += 1) {
                var x: i32 = start_x;
                while (x < end_x) : (x += 1) {
                    // Get patch pixel
                    const patch_x = @as(u32, @intCast(x - patch_ref.x_offset));
                    const patch_y = @as(u32, @intCast(y - patch_ref.y_offset));
                    if (patch_obj.getPixel(patch_x, patch_y)) |color_idx| {
                        // Convert palette index to RGB
                        const rgb = playpal.getColor(palette, color_idx);
                        const pixel = (@as(u32, rgb[0]) << 16) | (@as(u32, rgb[1]) << 8) | rgb[2] | 0xFF000000;
                        pixels[@as(usize, @intCast(y)) * pitch + @as(usize, @intCast(x))] = pixel;
                    }
                }
            }
        }

        return surface;
    }

    /// Free allocated memory
    pub fn deinit(self: *CompositeTexture) void {
        self.allocator.free(self.name);
        for (self.patches) |patch_ref| {
            self.allocator.free(patch_ref.patch_name);
        }
        self.allocator.free(self.patches);
    }
};

/// Parse TEXTURE1/TEXTURE2 lump data
pub fn parseTextureLump(allocator: std.mem.Allocator, data: []const u8, patch_names: *const PatchNames) ![]CompositeTexture {
    if (data.len < 4) {
        return Error.InvalidTextureData;
    }

    // Read number of textures
    const num_textures = std.mem.readInt(u32, data[0..4], .little);

    // Read texture offsets
    var offsets = try allocator.alloc(u32, num_textures);
    defer allocator.free(offsets);

    var offset: usize = 4;
    for (0..num_textures) |i| {
        if (offset + 4 > data.len) {
            return Error.InvalidTextureData;
        }
        const bytes: *const [4]u8 = @ptrCast(data[offset .. offset + 4]);
        offsets[i] = std.mem.readInt(u32, bytes, .little);
        offset += 4;
    }

    // Parse each texture
    var textures = try allocator.alloc(CompositeTexture, num_textures);
    errdefer {
        for (textures) |*texture| {
            texture.deinit();
        }
        allocator.free(textures);
    }

    for (0..num_textures) |i| {
        var texture_offset: usize = offsets[i];
        textures[i] = try CompositeTexture.parse(allocator, data, &texture_offset, patch_names);
    }

    return textures;
}

test {
    std.testing.refAllDecls(@This());
}

test "parse valid composite texture" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create mock patch names
    var patch_names = try PatchNames.init(allocator, &[_][]const u8{ "PATCH1", "PATCH2" });
    defer patch_names.deinit();

    // Create test data
    var texture_data = std.ArrayList(u8).init(allocator);
    defer texture_data.deinit();

    // Write texture name (8 bytes, null-terminated)
    try texture_data.appendSlice("TEXTURE1");
    try texture_data.appendSlice(&[_]u8{0} ** (8 - "TEXTURE1".len)); // Pad to 8 bytes

    // Write unused fields (4 bytes)
    try texture_data.appendSlice(&[_]u8{0} ** 4);

    // Write dimensions
    try texture_data.writer().writeInt(u16, 64, .little); // width
    try texture_data.writer().writeInt(u16, 128, .little); // height

    // Write unused fields (4 bytes)
    try texture_data.appendSlice(&[_]u8{0} ** 4);

    // Write number of patches
    try texture_data.writer().writeInt(u16, 1, .little); // num_patches

    // Write patch references
    // First patch
    try texture_data.writer().writeInt(i16, 0, .little); // x_offset
    try texture_data.writer().writeInt(i16, 0, .little); // y_offset
    try texture_data.writer().writeInt(u16, 0, .little); // patch_idx
    try texture_data.appendSlice(&[_]u8{0} ** 4); // Unused fields

    // Parse texture
    var offset: usize = 0;
    var texture = try CompositeTexture.parse(allocator, texture_data.items, &offset, &patch_names);
    defer texture.deinit();

    // Verify texture properties
    try testing.expectEqualStrings("TEXTURE1", texture.name);
    try testing.expectEqual(@as(u16, 64), texture.width);
    try testing.expectEqual(@as(u16, 128), texture.height);
    try testing.expectEqual(@as(usize, 1), texture.patches.len);

    // Verify first patch
    try testing.expectEqualStrings("PATCH1", texture.patches[0].patch_name);
    try testing.expectEqual(@as(i16, 0), texture.patches[0].x_offset);
    try testing.expectEqual(@as(i16, 0), texture.patches[0].y_offset);
}

test "parse texture lump" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create mock patch names
    var patch_names = try PatchNames.init(allocator, &[_][]const u8{"PATCH1"});
    defer patch_names.deinit();

    // Create test lump data
    var lump_data = std.ArrayList(u8).init(allocator);
    defer lump_data.deinit();

    // Write number of textures
    try lump_data.writer().writeInt(u32, 1, .little);

    // Write texture offset
    const texture_offset = 4 + 4; // 4 bytes for num_textures + 4 bytes for offset table
    try lump_data.writer().writeInt(u32, texture_offset, .little);

    // Write texture data
    // Name (8 bytes, null-terminated)
    try lump_data.appendSlice("TEXTURE1");
    try lump_data.appendSlice(&[_]u8{0} ** (8 - "TEXTURE1".len)); // Pad to 8 bytes
    try lump_data.appendSlice(&[_]u8{0} ** 4); // Unused fields

    // Dimensions
    try lump_data.writer().writeInt(u16, 64, .little); // width
    try lump_data.writer().writeInt(u16, 64, .little); // height
    try lump_data.appendSlice(&[_]u8{0} ** 4); // Unused fields

    // One patch
    try lump_data.writer().writeInt(u16, 1, .little); // num_patches
    try lump_data.writer().writeInt(i16, 0, .little); // x_offset
    try lump_data.writer().writeInt(i16, 0, .little); // y_offset
    try lump_data.writer().writeInt(u16, 0, .little); // patch_idx
    try lump_data.appendSlice(&[_]u8{0} ** 4); // Unused fields

    // Ensure we have enough data
    try testing.expectEqual(@as(usize, texture_offset + 8 + 4 + 2 + 2 + 4 + 2 + 2 + 2 + 2 + 4), lump_data.items.len);

    // Parse lump
    const textures = try parseTextureLump(allocator, lump_data.items, &patch_names);
    defer {
        for (textures) |*texture| {
            texture.deinit();
        }
        allocator.free(textures);
    }

    // Verify results
    try testing.expectEqual(@as(usize, 1), textures.len);
    try testing.expectEqualStrings("TEXTURE1", textures[0].name);
    try testing.expectEqual(@as(u16, 64), textures[0].width);
    try testing.expectEqual(@as(u16, 64), textures[0].height);
    try testing.expectEqual(@as(usize, 1), textures[0].patches.len);
    try testing.expectEqualStrings("PATCH1", textures[0].patches[0].patch_name);
}

test "render composite texture" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a simple composite texture
    var texture = CompositeTexture{
        .name = try allocator.dupe(u8, "TEST"),
        .width = 64,
        .height = 64,
        .patches = try allocator.alloc(PatchRef, 1),
        .allocator = allocator,
    };
    defer texture.deinit();

    // Set up one patch
    texture.patches[0] = .{
        .patch_name = try allocator.dupe(u8, "PATCH1"),
        .x_offset = 0,
        .y_offset = 0,
    };

    // Create mock texture manager
    var texture_manager = @import("../texture.zig").TextureManager.init(allocator);
    defer texture_manager.deinit();

    // Create mock patch
    var patch_data = std.ArrayList(u8).init(allocator);
    defer patch_data.deinit();

    // Picture header
    try patch_data.writer().writeInt(u16, 64, .little); // width
    try patch_data.writer().writeInt(u16, 64, .little); // height
    try patch_data.writer().writeInt(i16, 0, .little); // left_offset
    try patch_data.writer().writeInt(i16, 0, .little); // top_offset

    // Column offsets (64 columns)
    const column_data_start = 8 + 64 * 4; // header + column offsets
    for (0..64) |i| {
        try patch_data.writer().writeInt(u32, @as(u32, @intCast(column_data_start + i)), .little);
    }

    // Column data (empty columns)
    for (0..64) |_| {
        try patch_data.append(0xFF); // end of column marker
    }

    try texture_manager.loadPatch("PATCH1", patch_data.items);

    // Create mock playpal
    var playpal = doom_textures.Playpal{
        .palettes = undefined,
        .allocator = allocator,
    };
    // Set all colors to red for testing
    for (0..14) |palette| {
        for (0..256) |color| {
            playpal.palettes[palette][color] = .{ 255, 0, 0 };
        }
    }

    // Render the texture
    const surface = try texture.render(&texture_manager, &playpal, 0);
    defer c.SDL_FreeSurface(surface);

    // Verify surface properties
    try testing.expectEqual(@as(c_int, 64), surface.*.w);
    try testing.expectEqual(@as(c_int, 64), surface.*.h);
    try testing.expectEqual(@as(c_int, 32), surface.*.format.*.BitsPerPixel);
}
