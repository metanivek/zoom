const std = @import("std");

/// DOOM map data structures
/// Based on the DOOM WAD format specification
/// A vertex in a DOOM map
pub const Vertex = struct {
    x: i16, // X coordinate (fixed point)
    y: i16, // Y coordinate (fixed point)

    pub fn toFloat(self: Vertex) struct { x: f32, y: f32 } {
        return .{
            .x = @as(f32, @floatFromInt(self.x)),
            .y = @as(f32, @floatFromInt(self.y)),
        };
    }
};

/// A linedef defines a wall segment in a DOOM map
pub const LineDef = struct {
    start_vertex: u16, // Index of start vertex
    end_vertex: u16, // Index of end vertex
    flags: u16, // Behavior flags
    special_type: u16, // Special behavior type
    sector_tag: u16, // Sector tag
    right_sidedef: u16, // Index of right sidedef
    left_sidedef: u16, // Index of left sidedef (0xFFFF if none)

    pub const Flags = struct {
        pub const BLOCKING = 0x0001; // Blocks players and monsters
        pub const BLOCK_MONSTERS = 0x0002; // Blocks only monsters
        pub const TWO_SIDED = 0x0004; // Wall has two sides (not solid)
        pub const UPPER_UNPEGGED = 0x0008; // Upper texture is unpegged
        pub const LOWER_UNPEGGED = 0x0010; // Lower texture is unpegged
        pub const SECRET = 0x0020; // Shown as one-sided on automap
        pub const BLOCK_SOUND = 0x0040; // Blocks sound
        pub const NEVER_ON_AUTOMAP = 0x0080; // Never shown on automap
        pub const ALWAYS_ON_AUTOMAP = 0x0100; // Always shown on automap
    };
};

/// A sidedef defines the wall textures for one side of a linedef
pub const SideDef = struct {
    x_offset: i16, // X offset for texture
    y_offset: i16, // Y offset for texture
    upper_texture: [8]u8, // Name of upper texture
    lower_texture: [8]u8, // Name of lower texture
    middle_texture: [8]u8, // Name of middle texture
    sector: u16, // Sector this sidedef faces

    pub fn getUpperTexture(self: *const SideDef) []const u8 {
        return std.mem.sliceTo(&self.upper_texture, 0);
    }

    pub fn getLowerTexture(self: *const SideDef) []const u8 {
        return std.mem.sliceTo(&self.lower_texture, 0);
    }

    pub fn getMiddleTexture(self: *const SideDef) []const u8 {
        return std.mem.sliceTo(&self.middle_texture, 0);
    }
};

/// A sector defines the floor/ceiling heights and textures
pub const Sector = struct {
    floor_height: i16, // Floor height
    ceiling_height: i16, // Ceiling height
    floor_texture: [8]u8, // Name of floor texture
    ceiling_texture: [8]u8, // Name of ceiling texture
    light_level: u16, // Light level (0-255)
    special_type: u16, // Special behavior type
    tag: u16, // Tag number

    pub fn getFloorTexture(self: *const Sector) []const u8 {
        return std.mem.sliceTo(&self.floor_texture, 0);
    }

    pub fn getCeilingTexture(self: *const Sector) []const u8 {
        return std.mem.sliceTo(&self.ceiling_texture, 0);
    }
};

/// A thing defines an object in the map (player start, monster, item, etc)
pub const Thing = struct {
    x: i16, // X coordinate
    y: i16, // Y coordinate
    angle: u16, // Angle (0-359)
    type: u16, // Type of thing
    flags: u16, // Behavior flags

    pub const Flags = struct {
        pub const EASY = 0x0001; // Appears in easy mode
        pub const MEDIUM = 0x0002; // Appears in medium mode
        pub const HARD = 0x0004; // Appears in hard mode
        pub const AMBUSH = 0x0008; // Deaf monsters, multiplayer only items
        pub const NOT_SINGLE = 0x0010; // Not in single player
        pub const NOT_DEATHMATCH = 0x0020; // Not in deathmatch
        pub const NOT_COOP = 0x0040; // Not in cooperative
    };

    pub const Types = struct {
        pub const PLAYER1_START = 1;
        pub const PLAYER2_START = 2;
        pub const PLAYER3_START = 3;
        pub const PLAYER4_START = 4;
        pub const DEATHMATCH_START = 11;
    };
};

/// A node in the BSP tree
pub const Node = struct {
    x_partition: i16, // X coordinate of partition line start
    y_partition: i16, // Y coordinate of partition line start
    dx_partition: i16, // Delta X of partition line
    dy_partition: i16, // Delta Y of partition line
    right_bbox: [4]i16, // Bounding box for right child
    left_bbox: [4]i16, // Bounding box for left child
    right_child: u16, // Right child index
    left_child: u16, // Left child index
};

/// A subsector (leaf node in BSP tree)
pub const SubSector = struct {
    seg_count: u16, // Number of segs in this subsector
    first_seg: u16, // Index of first seg
};

/// A seg (line segment of a linedef)
pub const Seg = struct {
    start_vertex: u16, // Index of start vertex
    end_vertex: u16, // Index of end vertex
    angle: u16, // Angle (0-65535)
    linedef: u16, // Index of parent linedef
    direction: u16, // 0 (same as linedef) or 1 (opposite of linedef)
    offset: u16, // Distance along linedef to start of seg
};

/// A complete DOOM map
pub const DoomMap = struct {
    vertices: []Vertex,
    linedefs: []LineDef,
    sidedefs: []SideDef,
    sectors: []Sector,
    things: []Thing,
    nodes: []Node,
    subsectors: []SubSector,
    segs: []Seg,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DoomMap {
        return .{
            .vertices = &[0]Vertex{},
            .linedefs = &[0]LineDef{},
            .sidedefs = &[0]SideDef{},
            .sectors = &[0]Sector{},
            .things = &[0]Thing{},
            .nodes = &[0]Node{},
            .subsectors = &[0]SubSector{},
            .segs = &[0]Seg{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DoomMap) void {
        self.allocator.free(self.vertices);
        self.allocator.free(self.linedefs);
        self.allocator.free(self.sidedefs);
        self.allocator.free(self.sectors);
        self.allocator.free(self.things);
        self.allocator.free(self.nodes);
        self.allocator.free(self.subsectors);
        self.allocator.free(self.segs);
    }
};
