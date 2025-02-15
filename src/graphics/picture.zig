const std = @import("std");

/// DOOM picture format header structure
/// Size: 8 bytes
pub const Header = struct {
    width: i16, // Width of the picture
    height: i16, // Height of the picture
    left_offset: i16, // Left offset for drawing
    top_offset: i16, // Top offset for drawing

    /// Read a picture header from a buffer
    pub fn read(data: []const u8) !Header {
        if (data.len < @sizeOf(Header)) {
            return error.InvalidHeader;
        }

        return Header{
            .width = std.mem.readInt(i16, data[0..2], .little),
            .height = std.mem.readInt(i16, data[2..4], .little),
            .left_offset = std.mem.readInt(i16, data[4..6], .little),
            .top_offset = std.mem.readInt(i16, data[6..8], .little),
        };
    }
};

/// A post is a vertical slice of pixels in a column
pub const Post = struct {
    row: u8, // Row to start drawing this post at
    length: u8, // Number of pixels in post
    pixels: []u8, // Pixel data (indices into palette)

    pub fn deinit(self: *Post, allocator: std.mem.Allocator) void {
        allocator.free(self.pixels);
    }
};

/// A column is a vertical slice of the picture, containing posts
pub const Column = struct {
    posts: std.ArrayList(Post),

    pub fn init(allocator: std.mem.Allocator) Column {
        return .{
            .posts = std.ArrayList(Post).init(allocator),
        };
    }

    pub fn deinit(self: *Column) void {
        for (self.posts.items) |*post| {
            post.deinit(self.posts.allocator);
        }
        self.posts.deinit();
    }
};

pub const Error = error{
    InvalidHeader,
    InvalidHeaderValues,
    InvalidColumnOffset,
    InvalidPostData,
    OutOfMemory,
};

/// A picture in DOOM's column-based format
pub const Picture = struct {
    header: Header,
    columns: []Column,
    allocator: std.mem.Allocator,

    /// Load a picture from data
    pub fn load(allocator: std.mem.Allocator, data: []const u8) !Picture {
        // Minimum size check - need at least header + 1 column offset
        if (data.len < @sizeOf(Header) + 4) return error.InvalidHeader;

        // Read header
        const header = try Header.read(data);

        // Basic sanity checks
        if (header.width <= 0 or header.height <= 0) {
            return error.InvalidHeaderValues;
        }

        // Allocate columns
        var columns = try allocator.alloc(Column, @intCast(header.width));
        errdefer {
            for (columns) |*column| {
                column.deinit();
            }
            allocator.free(columns);
        }

        // Initialize columns
        for (columns) |*column| {
            column.* = Column.init(allocator);
        }

        // Calculate where picture data starts (after header and column offsets)
        const picture_data_start: u32 = @sizeOf(Header) + @as(u32, @intCast(header.width)) * 4;
        if (picture_data_start > data.len) return error.InvalidColumnOffset;

        // Process each column offset
        for (0..@as(u16, @intCast(header.width))) |col| {
            const offset_start = @sizeOf(Header) + col * 4;
            const offset_end = offset_start + 4;
            var offset_bytes: [4]u8 = undefined;
            @memcpy(&offset_bytes, data[offset_start..offset_end]);
            const offset = std.mem.readInt(u32, &offset_bytes, .little);

            if (offset >= data.len) return error.InvalidColumnOffset;

            // Read posts in this column
            var pos: usize = offset;
            var post_count: u32 = 0;
            while (pos < data.len) {
                // Prevent infinite loops
                post_count += 1;
                if (post_count > header.height * 2) break; // Allow more posts than height since they can overlap

                // Read row byte
                if (pos + 1 > data.len) return error.InvalidPostData;
                const row = data[pos];
                pos += 1;

                // A row of 255 marks the end of the column
                if (row == 255) break;

                // Read length byte
                if (pos + 1 > data.len) return error.InvalidPostData;
                const length = data[pos];
                pos += 1;

                // Skip padding byte before pixels
                if (pos + 1 > data.len) return error.InvalidPostData;
                pos += 1;

                // Read pixel data
                if (pos + length > data.len) {
                    return error.InvalidPostData;
                }

                // Check if we have the padding byte after pixels
                if (pos + length + 1 > data.len) {
                    return error.InvalidPostData;
                }

                // Allocate and copy pixel data
                const pixels = try allocator.alloc(u8, length);
                errdefer allocator.free(pixels);

                @memcpy(pixels, data[pos .. pos + length]);

                // Create post
                try columns[col].posts.append(.{
                    .row = row,
                    .length = length,
                    .pixels = pixels,
                });

                // Skip pixels and padding byte after
                pos += length + 1;
            }
        }

        return Picture{
            .header = header,
            .columns = columns,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Picture) void {
        for (self.columns) |*column| {
            column.deinit();
        }
        self.allocator.free(self.columns);
    }

    /// Get the pixel at the given coordinates
    /// Returns null if the pixel is transparent
    pub fn getPixel(self: *const Picture, x: u32, y: u32) ?u8 {
        if (x >= @as(u32, @intCast(self.header.width)) or y >= @as(u32, @intCast(self.header.height))) {
            return null;
        }

        const column = &self.columns[x];
        for (column.posts.items) |post| {
            const start_y = post.row;
            const end_y = std.math.add(u8, start_y, post.length) catch return null;
            if (y >= start_y and y < end_y) {
                return post.pixels[y - start_y];
            }
        }

        return null;
    }
};

test {
    std.testing.refAllDecls(@This());
}

// Test helpers
fn createTestData(
    allocator: std.mem.Allocator,
    width: i16,
    height: i16,
    left_offset: i16,
    top_offset: i16,
    column_data: []const u8,
) ![]u8 {
    // Calculate total size needed
    const header_size = @sizeOf(Header);
    const column_offsets_size = @as(usize, @intCast(width)) * 4;
    const total_size = header_size + column_offsets_size + column_data.len;

    // Allocate buffer
    var data = try allocator.alloc(u8, total_size);
    errdefer allocator.free(data);

    // Write header
    std.mem.writeInt(i16, data[0..2], width, .little);
    std.mem.writeInt(i16, data[2..4], height, .little);
    std.mem.writeInt(i16, data[4..6], left_offset, .little);
    std.mem.writeInt(i16, data[6..8], top_offset, .little);

    // Write column offsets - each points to start of column in column_data
    var i: usize = 0;
    const column_data_start = header_size + column_offsets_size;
    while (i < width) : (i += 1) {
        const offset: u32 = @intCast(column_data_start); // Each column starts at the same position for test data
        var offset_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &offset_bytes, offset, .little);
        @memcpy(data[header_size + i * 4 .. header_size + i * 4 + 4], &offset_bytes);
    }

    // Write column data
    @memcpy(data[column_data_start..], column_data);

    return data;
}

test "load valid simple picture" {
    const allocator = std.testing.allocator;

    // Create a simple 1x2 picture with one post per column
    // Each post starts at y=0 with length 2
    const column_data = [_]u8{
        0x00, // top_delta
        0x02, // length
        0x00, // padding before pixels
        0x01, 0x02, // pixel data
        0x00, // padding after pixels
        0xFF, // end of column marker
    };

    // Create test picture with 1 column
    const picture_data = try createTestData(
        allocator,
        1, // width
        2, // height
        0, // left_offset
        0, // top_offset
        &column_data,
    );
    defer allocator.free(picture_data);

    // Load the picture
    var test_picture = try Picture.load(allocator, picture_data);
    defer test_picture.deinit();

    // Verify header
    try std.testing.expectEqual(@as(i16, 1), test_picture.header.width);
    try std.testing.expectEqual(@as(i16, 2), test_picture.header.height);
    try std.testing.expectEqual(@as(i16, 0), test_picture.header.left_offset);
    try std.testing.expectEqual(@as(i16, 0), test_picture.header.top_offset);

    // Verify column data
    try std.testing.expectEqual(@as(usize, 1), test_picture.columns.len);
    try std.testing.expectEqual(@as(usize, 1), test_picture.columns[0].posts.items.len);

    // Verify post data
    const post = test_picture.columns[0].posts.items[0];
    try std.testing.expectEqual(@as(u8, 0), post.row);
    try std.testing.expectEqual(@as(u8, 2), post.length);
    try std.testing.expectEqual(@as(u8, 1), post.pixels[0]);
    try std.testing.expectEqual(@as(u8, 2), post.pixels[1]);
}

test "invalid header" {
    const allocator = std.testing.allocator;

    // Test data too small for header
    {
        const invalid_data = [_]u8{0} ** 4; // Only 4 bytes, need 8 for header
        try std.testing.expectError(error.InvalidHeader, Picture.load(allocator, &invalid_data));
    }

    // Test invalid dimensions
    {
        var picture_data = std.ArrayList(u8).init(allocator);
        defer picture_data.deinit();

        // Write header with invalid width
        try picture_data.writer().writeInt(i16, 0, .little); // width = 0 (invalid)
        try picture_data.writer().writeInt(i16, 2, .little); // height
        try picture_data.writer().writeInt(i16, 0, .little); // left_offset
        try picture_data.writer().writeInt(i16, 0, .little); // top_offset
        try picture_data.writer().writeInt(u32, 12, .little); // column offset

        try std.testing.expectError(error.InvalidHeaderValues, Picture.load(allocator, picture_data.items));
    }
}

test "invalid column offset" {
    const allocator = std.testing.allocator;

    // Create picture data with invalid column offset
    var picture_data = try createTestData(
        allocator,
        1, // width
        2, // height
        0,
        0,
        &[_]u8{},
    );
    defer allocator.free(picture_data);

    // Write an invalid column offset that points past end of data
    const header_size = @sizeOf(Header);
    const invalid_offset: u32 = 1000; // Points way past end of data
    std.mem.writeInt(u32, picture_data[header_size .. header_size + 4], invalid_offset, .little);

    try std.testing.expectError(error.InvalidColumnOffset, Picture.load(allocator, picture_data));
}

test "invalid post data" {
    const allocator = std.testing.allocator;

    // Test post with insufficient data
    {
        // Create test data directly with insufficient pixel data
        const test_data = [_]u8{
            // Header (8 bytes)
            0x01, 0x00, // width = 1
            0x02, 0x00, // height = 2
            0x00, 0x00, // left_offset = 0
            0x00, 0x00, // top_offset = 0
            // Column offset (4 bytes)
            0x0C, 0x00, 0x00, 0x00, // offset = 12 (points to start of column data)
            // Column data
            0x00, // row
            0x02, // length
            0x00, // padding before pixels
            0x01, // only 1 byte of pixel data when length is 2
            // Missing: second pixel byte and padding after pixels
        };

        // Attempt to load the picture - should fail with InvalidPostData
        const result = Picture.load(allocator, &test_data);
        try std.testing.expectError(error.InvalidPostData, result);
    }
}

test "getPixel" {
    const allocator = std.testing.allocator;

    const column_data = [_]u8{
        0x00, // top_delta
        0x02, // length
        0x00, // padding before pixels
        0x01, 0x02, // pixel data
        0x00, // padding after pixels
        0xFF, // end of column marker
    };

    const picture_data = try createTestData(
        allocator,
        1,
        2,
        0,
        0,
        &column_data,
    );
    defer allocator.free(picture_data);

    var test_picture = try Picture.load(allocator, picture_data);
    defer test_picture.deinit();

    // Test valid pixels
    try std.testing.expectEqual(@as(u8, 1), test_picture.getPixel(0, 0).?);
    try std.testing.expectEqual(@as(u8, 2), test_picture.getPixel(0, 1).?);

    // Test transparent pixels
    try std.testing.expectEqual(@as(?u8, null), test_picture.getPixel(1, 0)); // Outside width
    try std.testing.expectEqual(@as(?u8, null), test_picture.getPixel(0, 2)); // Outside height
}
