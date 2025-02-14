const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub const TextureError = error{
    LoadError,
    InvalidFormat,
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

pub const TextureManager = struct {
    textures: std.StringHashMap(TextureEntry),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TextureManager {
        return .{
            .textures = std.StringHashMap(TextureEntry).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TextureManager) void {
        var iterator = self.textures.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.texture.deinit();
            self.allocator.free(entry.value_ptr.name);
        }
        self.textures.deinit();
    }

    pub fn loadTexture(self: *TextureManager, name: []const u8, path: []const u8) !void {
        const texture = try Texture.loadFromFile(self.allocator, path);
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);

        const entry = TextureEntry{
            .name = name_copy,
            .texture = texture,
        };

        try self.textures.put(name_copy, entry);
    }

    pub fn getTexture(self: *TextureManager, name: []const u8) ?*Texture {
        if (self.textures.getPtr(name)) |entry| {
            return &entry.texture;
        }
        return null;
    }
};
