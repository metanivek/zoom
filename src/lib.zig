// Core modules
pub const wad = @import("wad.zig");
pub const doom_map = @import("doom_map.zig");
pub const doom_textures = @import("doom_textures.zig");
pub const texture = @import("texture.zig");

// Graphics modules
pub const graphics = struct {
    pub const patch = @import("graphics/patch.zig");
    pub const picture = @import("graphics/picture.zig");
    pub const sprite = @import("graphics/sprite.zig");
    pub const flat = @import("graphics/flat.zig");
};
