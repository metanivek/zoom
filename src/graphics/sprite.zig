const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const doom_textures = @import("../doom_textures.zig");
const picture = @import("picture.zig");
pub const Picture = picture.Picture;
pub const Header = picture.Header;

pub const Error = error{
    RenderError,
    InvalidSpriteName,
    InvalidFrameIndex,
    InvalidRotationState,
    NoValidFrameFound,
};

/// Represents a sprite animation sequence for a specific rotation
pub const SpriteAnimation = struct {
    /// The sprite prefix (e.g. "TROO")
    prefix: []const u8,
    /// The current rotation (0-8)
    rotation: u8,
    /// The current frame index in the sequence
    current_frame: usize = 0,
    /// List of frame letters in sequence (e.g. ['A', 'B', 'C'])
    frame_sequence: []const u8,
    /// Whether the animation is currently playing
    is_playing: bool = false,
    /// Time of last frame change
    last_frame_time: u64 = 0,
    /// Frame duration in milliseconds
    frame_duration: u64 = 100,

    pub fn init(allocator: std.mem.Allocator, prefix: []const u8, rotation: u8, frame_sequence: []const u8) !SpriteAnimation {
        return SpriteAnimation{
            .prefix = try allocator.dupe(u8, prefix),
            .rotation = rotation,
            .frame_sequence = try allocator.dupe(u8, frame_sequence),
        };
    }

    pub fn deinit(self: *SpriteAnimation, allocator: std.mem.Allocator) void {
        allocator.free(self.prefix);
        allocator.free(self.frame_sequence);
    }

    /// Get the current frame letter
    pub fn getCurrentFrame(self: *const SpriteAnimation) u8 {
        return self.frame_sequence[self.current_frame];
    }

    /// Advance to the next frame in the sequence
    pub fn nextFrame(self: *SpriteAnimation) void {
        if (self.is_playing) {
            const current_time = c.SDL_GetTicks64();
            if (current_time - self.last_frame_time >= self.frame_duration) {
                self.current_frame = (self.current_frame + 1) % self.frame_sequence.len;
                self.last_frame_time = current_time;
            }
        }
    }

    /// Start the animation
    pub fn play(self: *SpriteAnimation) void {
        if (!self.is_playing) {
            self.is_playing = true;
            self.last_frame_time = c.SDL_GetTicks64();
        }
    }

    /// Stop the animation
    pub fn stop(self: *SpriteAnimation) void {
        self.is_playing = false;
    }

    /// Set a specific frame by index
    pub fn setFrame(self: *SpriteAnimation, frame_index: usize) void {
        if (frame_index < self.frame_sequence.len) {
            self.current_frame = frame_index;
        }
    }

    /// Set the frame duration (in milliseconds)
    pub fn setFrameDuration(self: *SpriteAnimation, duration: u64) void {
        self.frame_duration = duration;
    }
};

/// Sprite name format can be either:
/// - "TROOA1" where:
///   - TROO: 4 letter sprite prefix
///   - A: frame (A-Z or 0-9)
///   - 1: rotation (0-8)
/// - "TROOA2A8" where:
///   - TROO: 4 letter sprite prefix
///   - A: first frame (A-Z)
///   - 2: first rotation (0-8)
///   - A: second frame (A-Z)
///   - 8: second rotation (0-8)
/// - "SPIDA1D1" where:
///   - SPID: 4 letter sprite prefix
///   - A: first frame (A-Z)
///   - 1: first rotation (0-8)
///   - D: second frame (A-Z)
///   - 1: second rotation (0-8)
pub const FrameRotation = struct {
    frame: u8,
    rotation: u8,
};

pub const SpriteName = struct {
    prefix: [4]u8,
    first: FrameRotation,
    second: ?FrameRotation = null,

    /// Returns true if this sprite has a second frame/rotation pair
    pub fn hasSecondPair(self: SpriteName) bool {
        return self.second != null;
    }

    /// Returns true if this sprite has a different frame for the second pair
    pub fn hasAlternateFrame(self: SpriteName) bool {
        return self.second != null and self.second.?.frame != self.first.frame;
    }

    /// Returns true if this sprite has a different rotation for the second pair
    pub fn hasDifferentRotation(self: SpriteName) bool {
        return self.second != null and self.second.?.rotation != self.first.rotation;
    }

    pub fn parse(name: []const u8) !SpriteName {
        // Validate name length
        if (name.len != 6 and name.len != 8) return error.InvalidSpriteName;

        // Validate prefix (should be printable ASCII)
        for (name[0..4]) |char| {
            if (char < 32 or char > 126) return error.InvalidSpriteName;
        }

        // Parse first frame and rotation
        const first_frame = name[4];
        const first_rotation = name[5];

        // Validate first frame (A-Z or 0-9)
        if (!((first_frame >= 'A' and first_frame <= 'Z') or (first_frame >= '0' and first_frame <= '9'))) {
            return error.InvalidSpriteName;
        }

        // Validate first rotation (0-8)
        if (first_rotation < '0' or first_rotation > '8') return error.InvalidSpriteName;

        // For numeric frames, only allow rotation 0
        if (first_frame >= '0' and first_frame <= '9' and first_rotation != '0') {
            return error.InvalidSpriteName;
        }

        // Handle standard case (6 characters, e.g. "TROOA1" or "TROOK0")
        if (name.len == 6) {
            return SpriteName{
                .prefix = name[0..4].*,
                .first = .{
                    .frame = first_frame,
                    .rotation = first_rotation - '0',
                },
                .second = null,
            };
        }

        // Handle 8 character cases
        const second_frame = name[6];
        const second_rotation = name[7];

        // For numeric frames, only allow rotation 0
        if (first_frame >= '0' and first_frame <= '9') {
            if (second_rotation != '0') {
                return error.InvalidSpriteName;
            }
            return SpriteName{
                .prefix = name[0..4].*,
                .first = .{
                    .frame = first_frame,
                    .rotation = 0,
                },
                .second = null,
            };
        }

        // Validate second frame (A-Z)
        if (second_frame < 'A' or second_frame > 'Z') {
            return error.InvalidSpriteName;
        }

        // Validate second rotation (0-8)
        if (second_rotation < '0' or second_rotation > '8') {
            return error.InvalidSpriteName;
        }

        // For 8 character names, must have either different frame or different rotation
        if (second_frame == first_frame and second_rotation == first_rotation) {
            return error.InvalidSpriteName;
        }

        return SpriteName{
            .prefix = name[0..4].*,
            .first = .{
                .frame = first_frame,
                .rotation = first_rotation - '0',
            },
            .second = .{
                .frame = second_frame,
                .rotation = second_rotation - '0',
            },
        };
    }

    pub fn format(
        self: SpriteName,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.writeAll(&self.prefix);
        try writer.writeByte(self.first.frame);
        try writer.writeByte(self.first.rotation + '0');
        if (self.second) |second| {
            try writer.writeByte(second.frame);
            try writer.writeByte(second.rotation + '0');
        }
    }
};

/// A sprite is a graphic resource used for game objects (monsters, items, etc)
/// It extends the base Picture format with sprite-specific metadata
pub const Sprite = struct {
    picture: Picture,
    name: SpriteName,
    animation: ?SpriteAnimation = null,

    /// Load a sprite from WAD lump data and name
    pub fn load(allocator: std.mem.Allocator, data: []const u8, name: []const u8) !Sprite {
        return Sprite{
            .picture = try Picture.load(allocator, data),
            .name = try SpriteName.parse(name),
            .animation = null,
        };
    }

    pub fn deinit(self: *Sprite) void {
        if (self.animation) |*anim| {
            anim.deinit(self.picture.allocator);
        }
        self.picture.deinit();
    }

    /// Set up animation for this sprite
    pub fn setupAnimation(self: *Sprite, frame_sequence: []const u8) !void {
        if (self.animation) |*anim| {
            anim.deinit(self.picture.allocator);
        }
        self.animation = try SpriteAnimation.init(
            self.picture.allocator,
            &self.name.prefix,
            self.name.first.rotation,
            frame_sequence,
        );
    }

    /// Update the sprite's animation state
    pub fn update(self: *Sprite) void {
        if (self.animation) |*anim| {
            anim.nextFrame();
        }
    }

    /// Get the current frame letter
    pub fn getCurrentFrame(self: *const Sprite) ?u8 {
        return if (self.animation) |anim| anim.getCurrentFrame() else null;
    }

    /// Start the animation
    pub fn play(self: *Sprite) void {
        if (self.animation) |*anim| {
            anim.play();
        }
    }

    /// Stop the animation
    pub fn stop(self: *Sprite) void {
        if (self.animation) |*anim| {
            anim.stop();
        }
    }

    /// Set a specific frame by index
    pub fn setFrame(self: *Sprite, frame_index: usize) void {
        if (self.animation) |*anim| {
            anim.setFrame(frame_index);
        }
    }

    /// Set the frame duration (in milliseconds)
    pub fn setFrameDuration(self: *Sprite, duration: u64) void {
        if (self.animation) |*anim| {
            anim.setFrameDuration(duration);
        }
    }

    /// Get the pixel at the given coordinates
    /// Returns null if the pixel is transparent
    /// For mirrored sprites, when getting pixels for the mirrored rotation,
    /// the x coordinate is flipped horizontally
    pub fn getPixel(self: *const Sprite, x: u32, y: u32, rotation: ?u8) ?u8 {
        // If a rotation is specified and this is a mirrored sprite,
        // check if we need to flip the x coordinate
        if (rotation != null and self.name.hasSecondPair()) {
            if (rotation.? == self.name.second.?.rotation) {
                // For sprites with alternate frames, we should already have
                // the correct sprite instance for this rotation
                const flipped_x = @as(u32, @intCast(self.picture.header.width)) - 1 - x;
                return self.picture.getPixel(flipped_x, y);
            }
        }
        return self.picture.getPixel(x, y);
    }

    /// Render the sprite to an SDL surface using the given palette
    /// If rotation is provided, it will handle mirroring if necessary
    pub fn render(self: *const Sprite, playpal: *const doom_textures.Playpal, palette_index: u8, rotation: ?u8) !*c.SDL_Surface {
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
                if (self.getPixel(@intCast(x), @intCast(y), rotation)) |color_idx| {
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

test "parse valid sprite names" {
    // Test numeric frame sprite name
    {
        const name = try SpriteName.parse("TROO10");
        std.debug.print("\nNumeric frame test:\n", .{});
        std.debug.print("  has_alternate_frame: {}\n", .{name.hasAlternateFrame()});
        std.debug.print("  has_different_rotation: {}\n", .{name.hasDifferentRotation()});
        std.debug.print("  second_frame: {?}\n", .{if (name.second) |s| s.frame else null});
        std.debug.print("  second_rotation: {?}\n", .{if (name.second) |s| s.rotation else null});
        try std.testing.expectEqualSlices(u8, "TROO", &name.prefix);
        try std.testing.expectEqual(@as(u8, '1'), name.first.frame);
        try std.testing.expectEqual(@as(u8, 0), name.first.rotation);
        try std.testing.expectEqual(false, name.hasSecondPair());
    }

    // Test standard sprite name
    {
        const name = try SpriteName.parse("TROOA1");
        std.debug.print("\nStandard sprite test:\n", .{});
        std.debug.print("  has_alternate_frame: {}\n", .{name.hasAlternateFrame()});
        std.debug.print("  has_different_rotation: {}\n", .{name.hasDifferentRotation()});
        std.debug.print("  second_frame: {?}\n", .{if (name.second) |s| s.frame else null});
        std.debug.print("  second_rotation: {?}\n", .{if (name.second) |s| s.rotation else null});
        try std.testing.expectEqualSlices(u8, "TROO", &name.prefix);
        try std.testing.expectEqual(@as(u8, 'A'), name.first.frame);
        try std.testing.expectEqual(@as(u8, 1), name.first.rotation);
        try std.testing.expectEqual(false, name.hasSecondPair());
    }

    // Test mirrored sprite name with same frame
    {
        const name = try SpriteName.parse("TROOA2A8");
        std.debug.print("\nMirrored sprite test:\n", .{});
        std.debug.print("  has_alternate_frame: {}\n", .{name.hasAlternateFrame()});
        std.debug.print("  has_different_rotation: {}\n", .{name.hasDifferentRotation()});
        std.debug.print("  second_frame: {?}\n", .{if (name.second) |s| s.frame else null});
        std.debug.print("  second_rotation: {?}\n", .{if (name.second) |s| s.rotation else null});
        try std.testing.expectEqualSlices(u8, "TROO", &name.prefix);
        try std.testing.expectEqual(@as(u8, 'A'), name.first.frame);
        try std.testing.expectEqual(@as(u8, 2), name.first.rotation);
        try std.testing.expectEqual(true, name.hasSecondPair());
        try std.testing.expectEqual(true, name.hasDifferentRotation());
        try std.testing.expectEqual(false, name.hasAlternateFrame());
        if (name.second) |second| {
            try std.testing.expectEqual(@as(u8, 'A'), second.frame);
            try std.testing.expectEqual(@as(u8, 8), second.rotation);
        }
    }

    // Test mirrored sprite name with alternate frame
    {
        const name = try SpriteName.parse("SPIDA1D1");
        std.debug.print("\nAlternate frame test:\n", .{});
        std.debug.print("  has_alternate_frame: {}\n", .{name.hasAlternateFrame()});
        std.debug.print("  has_different_rotation: {}\n", .{name.hasDifferentRotation()});
        std.debug.print("  second_frame: {?}\n", .{if (name.second) |s| s.frame else null});
        std.debug.print("  second_rotation: {?}\n", .{if (name.second) |s| s.rotation else null});
        try std.testing.expectEqualSlices(u8, "SPID", &name.prefix);
        try std.testing.expectEqual(@as(u8, 'A'), name.first.frame);
        try std.testing.expectEqual(@as(u8, 1), name.first.rotation);
        try std.testing.expectEqual(true, name.hasSecondPair());
        try std.testing.expectEqual(false, name.hasDifferentRotation());
        try std.testing.expectEqual(true, name.hasAlternateFrame());
        if (name.second) |second| {
            try std.testing.expectEqual(@as(u8, 'D'), second.frame);
            try std.testing.expectEqual(@as(u8, 1), second.rotation);
        }
    }
}

test "parse invalid sprite names" {
    // Invalid length
    try std.testing.expectError(error.InvalidSpriteName, SpriteName.parse("TROO"));
    try std.testing.expectError(error.InvalidSpriteName, SpriteName.parse("TROOA"));
    try std.testing.expectError(error.InvalidSpriteName, SpriteName.parse("TROOA2A")); // Incomplete mirrored name

    // Invalid frame
    try std.testing.expectError(error.InvalidSpriteName, SpriteName.parse("TROO11"));
    try std.testing.expectError(error.InvalidSpriteName, SpriteName.parse("TROO12A8")); // Different frames in mirrored name

    // Invalid rotation
    try std.testing.expectError(error.InvalidSpriteName, SpriteName.parse("TROOA9"));
    try std.testing.expectError(error.InvalidSpriteName, SpriteName.parse("TROOA2A9")); // Invalid mirror rotation
}

test "load and render mirrored sprite" {
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
    try picture_data.writer().writeInt(i16, 2, .little); // width = 2 to test mirroring
    try picture_data.writer().writeInt(i16, 2, .little); // height
    try picture_data.writer().writeInt(i16, 0, .little); // left_offset
    try picture_data.writer().writeInt(i16, 0, .little); // top_offset

    // Calculate offsets
    const header_size = @sizeOf(Header);
    const column_offsets_size = 2 * 4; // 2 columns * 4 bytes per offset
    const first_column_offset = header_size + column_offsets_size;
    const second_column_offset = first_column_offset + column_data.len;

    // Write column offsets
    try picture_data.writer().writeInt(u32, first_column_offset, .little); // first column
    try picture_data.writer().writeInt(u32, second_column_offset, .little); // second column

    // Write column data for both columns
    try picture_data.appendSlice(&column_data);
    try picture_data.appendSlice(&column_data);

    // Load sprite with mirrored name
    var test_sprite = try Sprite.load(allocator, picture_data.items, "TROOA2A8");
    defer test_sprite.deinit();

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

    // Test normal rotation (2)
    {
        const surface = try test_sprite.render(&mock_playpal, 0, 2);
        defer c.SDL_FreeSurface(surface);

        // Verify surface properties
        try std.testing.expectEqual(@as(c_int, 2), surface.*.w);
        try std.testing.expectEqual(@as(c_int, 2), surface.*.h);

        // Lock surface to check pixel values
        if (c.SDL_LockSurface(surface) < 0) {
            return error.RenderError;
        }
        defer c.SDL_UnlockSurface(surface);

        const pixels = @as([*]u32, @ptrCast(@alignCast(surface.*.pixels)));
        // Check first column pixels (should be original order)
        try std.testing.expectEqual(@as(u32, 0xFF0000FF), pixels[0]); // First pixel
        try std.testing.expectEqual(@as(u32, 0xFF0000FF), pixels[2]); // Second pixel
    }

    // Test mirrored rotation (8)
    {
        const surface = try test_sprite.render(&mock_playpal, 0, 8);
        defer c.SDL_FreeSurface(surface);

        // Verify surface properties
        try std.testing.expectEqual(@as(c_int, 2), surface.*.w);
        try std.testing.expectEqual(@as(c_int, 2), surface.*.h);

        // Lock surface to check pixel values
        if (c.SDL_LockSurface(surface) < 0) {
            return error.RenderError;
        }
        defer c.SDL_UnlockSurface(surface);

        const pixels = @as([*]u32, @ptrCast(@alignCast(surface.*.pixels)));
        // Check first column pixels (should be reversed order due to mirroring)
        try std.testing.expectEqual(@as(u32, 0xFF0000FF), pixels[1]); // First pixel (flipped)
        try std.testing.expectEqual(@as(u32, 0xFF0000FF), pixels[3]); // Second pixel (flipped)
    }
}

test "sprite animation with mirrored frames" {
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
    try picture_data.writer().writeInt(i16, 2, .little); // width = 2 to test mirroring
    try picture_data.writer().writeInt(i16, 2, .little); // height
    try picture_data.writer().writeInt(i16, 0, .little); // left_offset
    try picture_data.writer().writeInt(i16, 0, .little); // top_offset

    // Calculate offsets
    const header_size = @sizeOf(Header);
    const column_offsets_size = 2 * 4; // 2 columns * 4 bytes per offset
    const first_column_offset = header_size + column_offsets_size;
    const second_column_offset = first_column_offset + column_data.len;

    // Write column offsets
    try picture_data.writer().writeInt(u32, first_column_offset, .little); // first column
    try picture_data.writer().writeInt(u32, second_column_offset, .little); // second column

    // Write column data for both columns
    try picture_data.appendSlice(&column_data);
    try picture_data.appendSlice(&column_data);

    // Load sprite with mirrored name
    var sprite_obj = try Sprite.load(allocator, picture_data.items, "TROOA2A8");
    defer sprite_obj.deinit();

    // Set up animation with frame sequence
    try sprite_obj.setupAnimation(&[_]u8{ 'A', 'B', 'C' });

    // Test animation state
    try std.testing.expectEqual(false, sprite_obj.animation.?.is_playing);
    try std.testing.expectEqual(@as(usize, 0), sprite_obj.animation.?.current_frame);
    try std.testing.expectEqual(@as(u8, 'A'), sprite_obj.animation.?.getCurrentFrame());

    // Test frame advancement
    sprite_obj.play();
    try std.testing.expectEqual(true, sprite_obj.animation.?.is_playing);
    sprite_obj.update();
    try std.testing.expectEqual(@as(u8, 'A'), sprite_obj.animation.?.getCurrentFrame());

    // Test pixel access for mirrored rotation
    try std.testing.expectEqual(@as(?u8, 1), sprite_obj.getPixel(0, 0, 2)); // Original rotation
    try std.testing.expectEqual(@as(?u8, 1), sprite_obj.getPixel(1, 0, 8)); // Mirrored rotation
}

test "sprite animation with alternate frames" {
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
    try picture_data.writer().writeInt(i16, 2, .little); // width = 2 to test mirroring
    try picture_data.writer().writeInt(i16, 2, .little); // height
    try picture_data.writer().writeInt(i16, 0, .little); // left_offset
    try picture_data.writer().writeInt(i16, 0, .little); // top_offset

    // Calculate offsets
    const header_size = @sizeOf(Header);
    const column_offsets_size = 2 * 4; // 2 columns * 4 bytes per offset
    const first_column_offset = header_size + column_offsets_size;
    const second_column_offset = first_column_offset + column_data.len;

    // Write column offsets
    try picture_data.writer().writeInt(u32, first_column_offset, .little); // first column
    try picture_data.writer().writeInt(u32, second_column_offset, .little); // second column

    // Write column data for both columns
    try picture_data.appendSlice(&column_data);
    try picture_data.appendSlice(&column_data);

    // Load sprite with alternate frame name
    var sprite_obj = try Sprite.load(allocator, picture_data.items, "SPIDA1D1");
    defer sprite_obj.deinit();

    // Set up animation with frame sequence
    try sprite_obj.setupAnimation(&[_]u8{ 'A', 'B', 'C' });

    // Test sprite name parsing
    try std.testing.expectEqual(true, sprite_obj.name.hasAlternateFrame());
    try std.testing.expectEqual(@as(u8, 'D'), sprite_obj.name.second.?.frame);
    try std.testing.expectEqual(@as(u8, 1), sprite_obj.name.first.rotation);
    try std.testing.expectEqual(@as(u8, 1), sprite_obj.name.second.?.rotation);

    // Test pixel access for alternate frame rotation
    try std.testing.expectEqual(@as(?u8, 1), sprite_obj.getPixel(0, 0, 1)); // Original rotation
    try std.testing.expectEqual(@as(?u8, 1), sprite_obj.getPixel(1, 0, 1)); // Mirrored rotation with alternate frame
}
