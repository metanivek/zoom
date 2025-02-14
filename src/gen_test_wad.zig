const std = @import("std");
const doom_map = @import("doom_map.zig");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Create test WAD file
    const wad_path = "test/test.wad";
    const file = try std.fs.cwd().createFile(wad_path, .{});
    defer file.close();

    // Calculate directory pointer (will be after all lump data)
    const header_size: u32 = 12; // 4 bytes identification + 4 bytes num_lumps + 4 bytes dir_pointer
    var current_pos: u32 = header_size;

    // Define all lumps first
    const things = [_]doom_map.Thing{
        .{ // Player 1 start
            .x = 0,
            .y = 0,
            .angle = 0,
            .type = doom_map.Thing.Types.PLAYER1_START,
            .flags = 0,
        },
    };

    const vertices = [_]doom_map.Vertex{
        .{ .x = -32, .y = -32 }, // 0
        .{ .x = 32, .y = -32 }, // 1
        .{ .x = 32, .y = 32 }, // 2
        .{ .x = -32, .y = 32 }, // 3
    };

    const linedefs = [_]doom_map.LineDef{
        .{ // North wall
            .start_vertex = 0,
            .end_vertex = 1,
            .flags = doom_map.LineDef.Flags.BLOCKING,
            .special_type = 0,
            .sector_tag = 0,
            .right_sidedef = 0,
            .left_sidedef = 0xFFFF,
        },
        .{ // East wall
            .start_vertex = 1,
            .end_vertex = 2,
            .flags = doom_map.LineDef.Flags.BLOCKING,
            .special_type = 0,
            .sector_tag = 0,
            .right_sidedef = 1,
            .left_sidedef = 0xFFFF,
        },
        .{ // South wall
            .start_vertex = 2,
            .end_vertex = 3,
            .flags = doom_map.LineDef.Flags.BLOCKING,
            .special_type = 0,
            .sector_tag = 0,
            .right_sidedef = 2,
            .left_sidedef = 0xFFFF,
        },
        .{ // West wall
            .start_vertex = 3,
            .end_vertex = 0,
            .flags = doom_map.LineDef.Flags.BLOCKING,
            .special_type = 0,
            .sector_tag = 0,
            .right_sidedef = 3,
            .left_sidedef = 0xFFFF,
        },
    };

    const sidedefs = [_]doom_map.SideDef{
        .{ // North wall
            .x_offset = 0,
            .y_offset = 0,
            .upper_texture = "STARTAN1".*,
            .lower_texture = "-       ".*,
            .middle_texture = "STARTAN1".*,
            .sector = 0,
        },
        .{ // East wall
            .x_offset = 0,
            .y_offset = 0,
            .upper_texture = "STARTAN1".*,
            .lower_texture = "-       ".*,
            .middle_texture = "STARTAN1".*,
            .sector = 0,
        },
        .{ // South wall
            .x_offset = 0,
            .y_offset = 0,
            .upper_texture = "STARTAN1".*,
            .lower_texture = "-       ".*,
            .middle_texture = "STARTAN1".*,
            .sector = 0,
        },
        .{ // West wall
            .x_offset = 0,
            .y_offset = 0,
            .upper_texture = "STARTAN1".*,
            .lower_texture = "-       ".*,
            .middle_texture = "STARTAN1".*,
            .sector = 0,
        },
    };

    const sectors = [_]doom_map.Sector{
        .{
            .floor_height = 0,
            .ceiling_height = 128,
            .floor_texture = "FLOOR0_1".*,
            .ceiling_texture = "CEIL1_1 ".*,
            .light_level = 192,
            .special_type = 0,
            .tag = 0,
        },
    };

    // Calculate positions and sizes for directory entries
    const map_marker_pos = current_pos;
    const map_marker_size: u32 = 0;
    current_pos += map_marker_size;

    const things_pos = current_pos;
    const things_size: u32 = @sizeOf(@TypeOf(things));
    current_pos += things_size;

    const linedefs_pos = current_pos;
    const linedefs_size: u32 = @sizeOf(@TypeOf(linedefs));
    current_pos += linedefs_size;

    const sidedefs_pos = current_pos;
    const sidedefs_size: u32 = @sizeOf(@TypeOf(sidedefs));
    current_pos += sidedefs_size;

    const vertices_pos = current_pos;
    const vertices_size: u32 = @sizeOf(@TypeOf(vertices));
    current_pos += vertices_size;

    const segs_pos = current_pos;
    const segs_size: u32 = 0;
    current_pos += segs_size;

    const ssectors_pos = current_pos;
    const ssectors_size: u32 = 0;
    current_pos += ssectors_size;

    const nodes_pos = current_pos;
    const nodes_size: u32 = 0;
    current_pos += nodes_size;

    const sectors_pos = current_pos;
    const sectors_size: u32 = @sizeOf(@TypeOf(sectors));
    current_pos += sectors_size;

    // Directory will be written at current_pos
    const dir_pointer = current_pos;

    // Write WAD header
    try file.writeAll("IWAD"); // identification
    try file.writer().writeInt(u32, 9, .little); // num_lumps (map marker + 8 map lumps)
    try file.writer().writeInt(u32, dir_pointer, .little); // dir_pointer

    // Write map marker (empty)
    const map_name = "E1M1";

    // Write all lump data
    try file.writeAll(std.mem.sliceAsBytes(&things));
    try file.writeAll(std.mem.sliceAsBytes(&linedefs));
    try file.writeAll(std.mem.sliceAsBytes(&sidedefs));
    try file.writeAll(std.mem.sliceAsBytes(&vertices));
    // Empty SEGS, SSECTORS, and NODES lumps (no data to write)
    try file.writeAll(std.mem.sliceAsBytes(&sectors));

    // Write directory entries
    const dir_entries = [_]struct { pos: u32, size: u32, name: []const u8 }{
        .{ .pos = map_marker_pos, .size = map_marker_size, .name = map_name },
        .{ .pos = things_pos, .size = things_size, .name = "THINGS" },
        .{ .pos = linedefs_pos, .size = linedefs_size, .name = "LINEDEFS" },
        .{ .pos = sidedefs_pos, .size = sidedefs_size, .name = "SIDEDEFS" },
        .{ .pos = vertices_pos, .size = vertices_size, .name = "VERTEXES" },
        .{ .pos = segs_pos, .size = segs_size, .name = "SEGS" },
        .{ .pos = ssectors_pos, .size = ssectors_size, .name = "SSECTORS" },
        .{ .pos = nodes_pos, .size = nodes_size, .name = "NODES" },
        .{ .pos = sectors_pos, .size = sectors_size, .name = "SECTORS" },
    };

    // Write directory entries
    for (dir_entries) |entry| {
        try file.writer().writeInt(u32, entry.pos, .little);
        try file.writer().writeInt(u32, entry.size, .little);
        var name_buf: [8]u8 = [_]u8{0} ** 8;
        @memcpy(name_buf[0..@min(8, entry.name.len)], entry.name[0..@min(8, entry.name.len)]);
        try file.writeAll(&name_buf);
    }
}
