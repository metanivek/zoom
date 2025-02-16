const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const doom_textures = @import("doom_textures.zig");
const wad = @import("wad.zig");
const patch = @import("graphics/patch.zig");
const sprite = @import("graphics/sprite.zig");
const flat = @import("graphics/flat.zig");

pub const TextureError = error{
    LoadError,
    InvalidFormat,
    PlaypalError,
    ColormapError,
    PatchError,
    SpriteError,
    FlatError,
};

pub const Texture = struct {
    surface: *c.SDL_Surface,
    width: u32,
    height: u32,

    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !Texture {
        _ = allocator;
        const surface = c.SDL_LoadBMP(path.ptr) orelse {
            std.debug.print("Failed to load texture: {s}\n", .{c.SDL_GetError()});
            return TextureError.LoadError;
        };

        return Texture{
            .surface = surface,
            .width = @intCast(surface.*.w),
            .height = @intCast(surface.*.h),
        };
    }

    pub fn deinit(self: *Texture) void {
        c.SDL_FreeSurface(self.surface);
    }

    pub fn getPixel(self: *const Texture, x: u32, y: u32) u32 {
        const pixels = @as([*]u8, @ptrCast(self.surface.*.pixels));
        const pitch = @as(u32, @intCast(self.surface.*.pitch));
        const bpp = @as(u32, @intCast(self.surface.*.format.*.BytesPerPixel));
        const offset = y * pitch + x * bpp;

        // Read RGB values
        const b = @as(u32, pixels[offset + 0]);
        const g = @as(u32, pixels[offset + 1]);
        const r = @as(u32, pixels[offset + 2]);

        // Return as 32-bit RGBA (alpha is always 255)
        return (r << 16) | (g << 8) | b | (0xFF000000);
    }

    pub fn sampleTexture(self: *const Texture, u: f32, v: f32) u32 {
        // Wrap texture coordinates
        const wrapped_u = @mod(u, 1.0);
        const wrapped_v = @mod(v, 1.0);

        // Convert to pixel coordinates
        const x = @as(u32, @intFromFloat(wrapped_u * @as(f32, @floatFromInt(self.width - 1))));
        const y = @as(u32, @intFromFloat(wrapped_v * @as(f32, @floatFromInt(self.height - 1))));

        return self.getPixel(x, y);
    }
};

const TextureEntry = struct {
    name: []const u8,
    texture: Texture,
};

const PatchEntry = struct {
    name: []const u8,
    patch: patch.Patch,
};

const SpriteEntry = struct {
    name: []const u8,
    sprite: sprite.Sprite,
};

const FlatEntry = struct {
    name: []const u8,
    flat: flat.Flat,
};

pub const TextureManager = struct {
    textures: std.ArrayList(TextureEntry),
    patches: std.ArrayList(PatchEntry),
    sprites: std.ArrayList(SpriteEntry),
    flats: std.ArrayList(FlatEntry),
    allocator: std.mem.Allocator,
    playpal: ?doom_textures.Playpal = null,
    colormap: ?doom_textures.Colormap = null,

    pub fn init(allocator: std.mem.Allocator) TextureManager {
        return .{
            .textures = std.ArrayList(TextureEntry).init(allocator),
            .patches = std.ArrayList(PatchEntry).init(allocator),
            .sprites = std.ArrayList(SpriteEntry).init(allocator),
            .flats = std.ArrayList(FlatEntry).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TextureManager) void {
        for (self.textures.items) |*entry| {
            entry.texture.deinit();
            self.allocator.free(entry.name);
        }
        self.textures.deinit();

        for (self.patches.items) |*entry| {
            entry.patch.deinit();
            self.allocator.free(entry.name);
        }
        self.patches.deinit();

        for (self.sprites.items) |*entry| {
            entry.sprite.deinit();
            self.allocator.free(entry.name);
        }
        self.sprites.deinit();

        for (self.flats.items) |*entry| {
            entry.flat.deinit();
            self.allocator.free(entry.name);
        }
        self.flats.deinit();

        if (self.playpal) |*pal| pal.deinit();
        if (self.colormap) |*cmap| cmap.deinit();
    }

    pub fn loadFromWad(self: *TextureManager, wad_file: *wad.WadFile) !void {
        // Load PLAYPAL
        self.playpal = try doom_textures.Playpal.load(self.allocator, wad_file);
        errdefer if (self.playpal) |*pal| pal.deinit();

        // Load COLORMAP
        self.colormap = try doom_textures.Colormap.load(self.allocator, wad_file);
        errdefer if (self.colormap) |*cmap| cmap.deinit();

        // Track marker sections
        var in_patch_marker = false;
        var in_sprite_marker = false;
        var in_flat_marker = false;

        for (wad_file.directory) |*entry| {
            const name = entry.getName();

            // Check for patch markers
            if (std.mem.eql(u8, name, "P_START") or std.mem.eql(u8, name, "PP_START")) {
                in_patch_marker = true;
                continue;
            } else if (std.mem.eql(u8, name, "P_END") or std.mem.eql(u8, name, "PP_END")) {
                in_patch_marker = false;
                continue;
            }

            // Check for sprite markers
            if (std.mem.eql(u8, name, "S_START") or std.mem.eql(u8, name, "SS_START")) {
                in_sprite_marker = true;
                continue;
            } else if (std.mem.eql(u8, name, "S_END") or std.mem.eql(u8, name, "SS_END")) {
                in_sprite_marker = false;
                continue;
            }

            // Check for flat markers
            if (std.mem.eql(u8, name, "F_START") or std.mem.eql(u8, name, "FF_START")) {
                in_flat_marker = true;
                continue;
            } else if (std.mem.eql(u8, name, "F_END") or std.mem.eql(u8, name, "FF_END")) {
                in_flat_marker = false;
                continue;
            }

            // Skip nested P1/P2/P3 and F1/F2 markers
            if (std.mem.eql(u8, name, "P1_START") or
                std.mem.eql(u8, name, "P2_START") or
                std.mem.eql(u8, name, "P3_START") or
                std.mem.eql(u8, name, "P1_END") or
                std.mem.eql(u8, name, "P2_END") or
                std.mem.eql(u8, name, "P3_END") or
                std.mem.eql(u8, name, "F1_START") or
                std.mem.eql(u8, name, "F2_START") or
                std.mem.eql(u8, name, "F1_END") or
                std.mem.eql(u8, name, "F2_END"))
            {
                continue;
            }

            // Process entries based on current marker section
            if (in_patch_marker) {
                const data = try wad_file.readLump(entry);
                defer self.allocator.free(data);
                try self.loadPatch(name, data);
            } else if (in_sprite_marker) {
                const data = try wad_file.readLump(entry);
                defer self.allocator.free(data);
                try self.loadSprite(name, data);
            } else if (in_flat_marker) {
                const data = try wad_file.readLump(entry);
                defer self.allocator.free(data);
                try self.loadFlat(name, data);
            }
        }
    }

    pub fn loadTexture(self: *TextureManager, name: []const u8, path: []const u8) !void {
        // Create owned copy of name
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);

        // Load texture
        var texture = try Texture.loadFromFile(self.allocator, path);
        errdefer texture.deinit();

        // Add to list
        try self.textures.append(.{
            .name = name_copy,
            .texture = texture,
        });
    }

    pub fn loadPatch(self: *TextureManager, name: []const u8, data: []const u8) !void {
        // Create owned copy of name
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);

        // Load patch
        var loaded_patch = try patch.Patch.load(self.allocator, data);
        errdefer loaded_patch.deinit();

        // Add to list
        try self.patches.append(.{
            .name = name_copy,
            .patch = loaded_patch,
        });
    }

    pub fn loadSprite(self: *TextureManager, name: []const u8, data: []const u8) !void {
        // Create owned copy of name, but only up to the first non-printable character
        var name_len: usize = 0;
        for (name) |char| {
            if (char == 0 or char < 32 or char > 126) break;
            name_len += 1;
        }
        const name_copy = try self.allocator.dupe(u8, name[0..name_len]);
        errdefer self.allocator.free(name_copy);

        // Load sprite
        var loaded_sprite = sprite.Sprite.load(self.allocator, data, name) catch |err| {
            self.allocator.free(name_copy);
            return err;
        };
        errdefer loaded_sprite.deinit();

        // Add to list
        try self.sprites.append(.{
            .name = name_copy,
            .sprite = loaded_sprite,
        });
    }

    pub fn loadFlat(self: *TextureManager, name: []const u8, data: []const u8) !void {
        // Create owned copy of name
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);

        // Load flat
        var loaded_flat = flat.Flat.load(self.allocator, data) catch |err| {
            self.allocator.free(name_copy);
            return err;
        };
        errdefer loaded_flat.deinit();

        // Add to list
        try self.flats.append(.{
            .name = name_copy,
            .flat = loaded_flat,
        });
    }

    pub fn getTexture(self: *const TextureManager, name: []const u8) ?*const Texture {
        for (self.textures.items) |*entry| {
            if (std.mem.eql(u8, entry.name, name)) {
                return &entry.texture;
            }
        }
        return null;
    }

    pub fn getPatch(self: *const TextureManager, name: []const u8) ?*const patch.Patch {
        for (self.patches.items) |*entry| {
            if (std.mem.eql(u8, entry.name, name)) {
                return &entry.patch;
            }
        }
        return null;
    }

    pub fn getSprite(self: *const TextureManager, name: []const u8) ?*const sprite.Sprite {
        for (self.sprites.items) |*entry| {
            if (std.mem.eql(u8, entry.name, name)) {
                return &entry.sprite;
            }
        }
        return null;
    }

    pub fn getFlat(self: *const TextureManager, name: []const u8) ?*const flat.Flat {
        for (self.flats.items) |*entry| {
            if (std.mem.eql(u8, entry.name, name)) {
                return &entry.flat;
            }
        }
        return null;
    }

    /// Convert a palette color to RGB using the current PLAYPAL
    pub fn paletteToRgb(self: *const TextureManager, color_idx: u8) ![3]u8 {
        if (self.playpal) |p| {
            return p.getColor(0, color_idx); // Use first palette by default
        }
        return TextureError.PlaypalError;
    }

    /// Get a shaded palette color index using COLORMAP
    pub fn getShade(self: *const TextureManager, color_idx: u8, light_level: u8) !u8 {
        if (self.colormap) |cmap| {
            return cmap.getShade(color_idx, light_level);
        }
        return TextureError.ColormapError;
    }
};
