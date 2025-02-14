const std = @import("std");
const doom_map = @import("doom_map.zig");

/// WAD file header structure
/// Size: 12 bytes
pub const WadHeader = struct {
    /// Magic number: 'IWAD' or 'PWAD'
    identification: [4]u8,
    /// Number of lumps in WAD
    num_lumps: u32,
    /// Pointer to directory
    dir_pointer: u32,

    /// Validates the WAD header identification
    pub fn isValid(self: *const WadHeader) bool {
        const iwad = [_]u8{ 'I', 'W', 'A', 'D' };
        const pwad = [_]u8{ 'P', 'W', 'A', 'D' };
        return std.mem.eql(u8, &self.identification, &iwad) or
            std.mem.eql(u8, &self.identification, &pwad);
    }

    /// Returns true if this is an IWAD (Internal WAD)
    pub fn isIWAD(self: *const WadHeader) bool {
        const iwad = [_]u8{ 'I', 'W', 'A', 'D' };
        return std.mem.eql(u8, &self.identification, &iwad);
    }

    /// Read a WAD header from a file
    pub fn read(file: std.fs.File) !WadHeader {
        var ident: [4]u8 = undefined;
        var num_lumps: u32 = undefined;
        var dir_ptr: u32 = undefined;

        // Read identification
        if ((try file.read(&ident)) != 4) return error.ReadError;

        // Read number of lumps (little-endian)
        var num_lumps_bytes: [4]u8 = undefined;
        if ((try file.read(&num_lumps_bytes)) != 4) return error.ReadError;
        num_lumps = std.mem.readInt(u32, &num_lumps_bytes, .little);

        // Read directory pointer (little-endian)
        var dir_ptr_bytes: [4]u8 = undefined;
        if ((try file.read(&dir_ptr_bytes)) != 4) return error.ReadError;
        dir_ptr = std.mem.readInt(u32, &dir_ptr_bytes, .little);

        return WadHeader{
            .identification = ident,
            .num_lumps = num_lumps,
            .dir_pointer = dir_ptr,
        };
    }
};

/// WAD directory entry structure
/// Size: 16 bytes
pub const WadDirEntry = struct {
    /// Offset to start of lump data
    file_pos: u32,
    /// Size of lump in bytes
    size: u32,
    /// Name of lump, padded with zeros
    name: [8]u8,

    /// Gets the lump name as a string slice
    pub fn getName(self: *const WadDirEntry) []const u8 {
        // Find the first zero or return full name if none found
        for (self.name, 0..) |c, i| {
            if (c == 0) return self.name[0..i];
        }
        return &self.name;
    }

    /// Read a directory entry from a file
    pub fn read(file: std.fs.File) !WadDirEntry {
        var pos_bytes: [4]u8 = undefined;
        var size_bytes: [4]u8 = undefined;
        var name: [8]u8 = undefined;

        // Read file position (little-endian)
        if ((try file.read(&pos_bytes)) != 4) return error.ReadError;
        const file_pos = std.mem.readInt(u32, &pos_bytes, .little);

        // Read size (little-endian)
        if ((try file.read(&size_bytes)) != 4) return error.ReadError;
        const size = std.mem.readInt(u32, &size_bytes, .little);

        // Read name
        if ((try file.read(&name)) != 8) return error.ReadError;

        return WadDirEntry{
            .file_pos = file_pos,
            .size = size,
            .name = name,
        };
    }
};

/// Error type for WAD operations
pub const WadError = error{
    InvalidHeader,
    InvalidMagicNumber,
    ReadError,
    SeekError,
    OutOfMemory,
    FileTooSmall,
    MapNotFound,
    InvalidMapData,
};

/// Main WAD file handler
pub const WadFile = struct {
    file: std.fs.File,
    header: WadHeader,
    directory: []WadDirEntry,
    allocator: std.mem.Allocator,

    /// Opens and loads a WAD file
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !WadFile {
        // Open the WAD file in binary mode
        const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
        errdefer file.close();

        // Check file size
        const file_size = try file.getEndPos();
        if (file_size < @sizeOf(WadHeader)) {
            std.debug.print("File too small: {} bytes\n", .{file_size});
            return WadError.FileTooSmall;
        }

        // Read the header
        const header = try WadHeader.read(file);

        // Debug print the header identification
        std.debug.print("WAD Header ID: '{s}' (bytes: {any})\n", .{ header.identification, header.identification });
        std.debug.print("Number of lumps: {}\n", .{header.num_lumps});
        std.debug.print("Directory pointer: 0x{X}\n", .{header.dir_pointer});

        if (!header.isValid()) {
            std.debug.print("Invalid WAD header magic number\n", .{});
            return WadError.InvalidMagicNumber;
        }

        // Verify directory pointer is within file bounds
        if (header.dir_pointer >= file_size) {
            std.debug.print("Directory pointer (0x{X}) beyond file size (0x{X})\n", .{
                header.dir_pointer,
                file_size,
            });
            return WadError.InvalidHeader;
        }

        // Seek to directory
        try file.seekTo(header.dir_pointer);

        // Read directory entries
        const dir_size = @sizeOf(WadDirEntry) * header.num_lumps;
        if (header.dir_pointer + dir_size > file_size) {
            std.debug.print("Directory entries would extend beyond file size\n", .{});
            return WadError.InvalidHeader;
        }

        var directory = try allocator.alloc(WadDirEntry, header.num_lumps);
        errdefer allocator.free(directory);

        // Read each directory entry individually to handle endianness
        var i: usize = 0;
        while (i < header.num_lumps) : (i += 1) {
            directory[i] = try WadDirEntry.read(file);
        }

        return WadFile{
            .file = file,
            .header = header,
            .directory = directory,
            .allocator = allocator,
        };
    }

    /// Cleans up WAD file resources
    pub fn deinit(self: *WadFile) void {
        self.allocator.free(self.directory);
        self.file.close();
    }

    /// Finds a lump by name
    pub fn findLump(self: *const WadFile, name: []const u8) ?*const WadDirEntry {
        for (self.directory) |*entry| {
            if (std.mem.eql(u8, entry.getName(), name)) {
                return entry;
            }
        }
        return null;
    }

    /// Reads a lump's data into a newly allocated buffer
    pub fn readLump(self: *WadFile, entry: *const WadDirEntry) ![]u8 {
        const data = try self.allocator.alloc(u8, entry.size);
        errdefer self.allocator.free(data);

        try self.file.seekTo(entry.file_pos);
        const bytes_read = try self.file.read(data);
        if (bytes_read != entry.size) {
            return WadError.ReadError;
        }

        return data;
    }

    /// Reads a lump by name
    pub fn readLumpByName(self: *WadFile, name: []const u8) !?[]u8 {
        if (self.findLump(name)) |entry| {
            return try self.readLump(entry);
        }
        return null;
    }

    /// Reads a map from the WAD file
    pub fn readMap(self: *WadFile, map_name: []const u8) !doom_map.DoomMap {
        // Find the index of the map marker in the directory
        var map_index: usize = 0;
        var found = false;

        for (self.directory, 0..) |entry, i| {
            if (std.mem.eql(u8, entry.getName(), map_name)) {
                map_index = i;
                found = true;
                break;
            }
        }

        if (!found) return WadError.MapNotFound;

        // Initialize the map
        var map = doom_map.DoomMap.init(self.allocator);
        errdefer map.deinit();

        // Read map lumps in order
        // Each map consists of multiple lumps in a specific order
        inline for (.{
            .{ "THINGS", &map.things },
            .{ "LINEDEFS", &map.linedefs },
            .{ "SIDEDEFS", &map.sidedefs },
            .{ "VERTEXES", &map.vertices },
            .{ "SEGS", &map.segs },
            .{ "SSECTORS", &map.subsectors },
            .{ "NODES", &map.nodes },
            .{ "SECTORS", &map.sectors },
        }) |lump_info| {
            const target_slice = lump_info[1];

            // Get the lump entry
            const lump_index = map_index + 1; // Skip the map marker
            if (lump_index >= self.directory.len) return WadError.InvalidMapData;
            const lump = self.directory[lump_index];

            // Calculate number of elements based on lump size and structure size
            const element_size = @sizeOf(@TypeOf(target_slice.*[0]));
            const num_elements = lump.size / element_size;

            // Allocate memory for the elements
            target_slice.* = try self.allocator.alloc(@TypeOf(target_slice.*[0]), num_elements);

            // Read the data
            try self.file.seekTo(lump.file_pos);
            const bytes_read = try self.file.readAll(std.mem.sliceAsBytes(target_slice.*));
            if (bytes_read != lump.size) return WadError.ReadError;

            map_index += 1;
        }

        return map;
    }
};

// Tests
test "WadHeader validation" {
    const testing = std.testing;

    var header = WadHeader{
        .identification = "IWAD".*,
        .num_lumps = 10,
        .dir_pointer = 100,
    };
    try testing.expect(header.isValid());
    try testing.expect(header.isIWAD());

    header.identification = "PWAD".*;
    try testing.expect(header.isValid());
    try testing.expect(!header.isIWAD());

    header.identification = "XWAD".*;
    try testing.expect(!header.isValid());
}

test "WadDirEntry name handling" {
    const testing = std.testing;

    // Test full name
    var entry = WadDirEntry{
        .file_pos = 0,
        .size = 0,
        .name = "TESTNAME".*,
    };
    try testing.expectEqualStrings("TESTNAME", entry.getName());

    // Test zero-terminated name
    entry.name = [_]u8{ 'T', 'E', 'S', 'T', 0 } ++ [_]u8{0} ** 3;
    try testing.expectEqualStrings("TEST", entry.getName());
}

test "Create test WAD file" {
    const testing = std.testing;
    const tmp_dir = std.testing.tmpDir;
    var tmp = tmp_dir.dir;
    const allocator = testing.allocator;

    // Create a test WAD file
    const test_wad_path = "test.wad";
    {
        const file = try tmp.createFile(test_wad_path, .{});
        defer file.close();

        // Write header
        const header = WadHeader{
            .identification = "PWAD".*,
            .num_lumps = 2,
            .dir_pointer = @sizeOf(WadHeader),
        };
        _ = try file.write(std.mem.asBytes(&header));

        // Write directory entries
        const entries = [_]WadDirEntry{
            .{
                .file_pos = @sizeOf(WadHeader) + @sizeOf(WadDirEntry) * 2,
                .size = 5,
                .name = "FIRST\x00\x00\x00".*,
            },
            .{
                .file_pos = @sizeOf(WadHeader) + @sizeOf(WadDirEntry) * 2 + 5,
                .size = 6,
                .name = "SECOND\x00".*,
            },
        };
        _ = try file.write(std.mem.sliceAsBytes(&entries));

        // Write lump data
        _ = try file.write("Hello");
        _ = try file.write("World!");
    }

    // Test reading the WAD file
    {
        var wad_file = try WadFile.init(allocator, test_wad_path);
        defer wad_file.deinit();

        try testing.expect(!wad_file.header.isIWAD());
        try testing.expect(wad_file.header.num_lumps == 2);

        // Test finding lumps
        const first_lump = wad_file.findLump("FIRST") orelse return error.LumpNotFound;
        try testing.expectEqualStrings("FIRST", first_lump.getName());
        try testing.expect(first_lump.size == 5);

        const second_lump = wad_file.findLump("SECOND") orelse return error.LumpNotFound;
        try testing.expectEqualStrings("SECOND", second_lump.getName());
        try testing.expect(second_lump.size == 6);

        // Test reading lump data
        if (try wad_file.readLumpByName("FIRST")) |data| {
            defer allocator.free(data);
            try testing.expectEqualStrings("Hello", data);
        } else {
            return error.LumpDataNotFound;
        }

        if (try wad_file.readLumpByName("SECOND")) |data| {
            defer allocator.free(data);
            try testing.expectEqualStrings("World!", data);
        } else {
            return error.LumpDataNotFound;
        }
    }

    // Clean up
    try tmp.deleteFile(test_wad_path);
}

test "WAD map loading" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Open test WAD file
    var wad_file = try WadFile.init(allocator, "test/test.wad");
    defer wad_file.deinit();

    // Load E1M1 map
    var map = try wad_file.readMap("E1M1");
    defer map.deinit();

    // Verify map data
    try testing.expect(map.vertices.len > 0);
    try testing.expect(map.linedefs.len > 0);
    try testing.expect(map.sidedefs.len > 0);
    try testing.expect(map.sectors.len > 0);
    try testing.expect(map.things.len > 0);

    // Verify player start exists
    var found_player_start = false;
    for (map.things) |thing| {
        if (thing.type == doom_map.Thing.Types.PLAYER1_START) {
            found_player_start = true;
            break;
        }
    }
    try testing.expect(found_player_start);

    // Verify map connectivity
    for (map.linedefs) |linedef| {
        // Check vertex indices are valid
        try testing.expect(linedef.start_vertex < map.vertices.len);
        try testing.expect(linedef.end_vertex < map.vertices.len);

        // Check sidedef indices are valid
        try testing.expect(linedef.right_sidedef < map.sidedefs.len);
        if (linedef.left_sidedef != 0xFFFF) {
            try testing.expect(linedef.left_sidedef < map.sidedefs.len);
        }
    }

    // Verify sidedefs
    for (map.sidedefs) |sidedef| {
        try testing.expect(sidedef.sector < map.sectors.len);
    }
}
