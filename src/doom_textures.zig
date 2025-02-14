const std = @import("std");
const wad = @import("wad.zig");

/// DOOM's PLAYPAL lump contains 14 256-color palettes
/// Each palette is 768 bytes (256 RGB triplets)
pub const Playpal = struct {
    /// Each palette is 256 RGB colors
    palettes: [14][256][3]u8,
    allocator: std.mem.Allocator,

    pub fn load(allocator: std.mem.Allocator, wad_file: *wad.WadFile) !Playpal {
        const playpal_data = (try wad_file.readLumpByName("PLAYPAL")) orelse {
            return error.PlaypalNotFound;
        };
        defer allocator.free(playpal_data);

        if (playpal_data.len != 14 * 256 * 3) {
            return error.InvalidPlaypalSize;
        }

        var playpal = Playpal{
            .palettes = undefined,
            .allocator = allocator,
        };

        // Copy data into palettes array
        for (0..14) |palette_idx| {
            for (0..256) |color_idx| {
                playpal.palettes[palette_idx][color_idx][0] = playpal_data[palette_idx * 768 + color_idx * 3 + 0]; // R
                playpal.palettes[palette_idx][color_idx][1] = playpal_data[palette_idx * 768 + color_idx * 3 + 1]; // G
                playpal.palettes[palette_idx][color_idx][2] = playpal_data[palette_idx * 768 + color_idx * 3 + 2]; // B
            }
        }

        return playpal;
    }

    pub fn deinit(self: *Playpal) void {
        _ = self;
    }

    /// Get RGB color from palette index
    pub fn getColor(self: *const Playpal, palette_idx: u8, color_idx: u8) [3]u8 {
        return self.palettes[palette_idx][color_idx];
    }
};

/// DOOM's COLORMAP lump contains 34 light level colormaps
/// Each colormap is 256 bytes mapping from the base palette to a darker version
pub const Colormap = struct {
    /// Each colormap is 256 bytes mapping to palette indices
    colormaps: [34][256]u8,
    allocator: std.mem.Allocator,

    pub fn load(allocator: std.mem.Allocator, wad_file: *wad.WadFile) !Colormap {
        const colormap_data = (try wad_file.readLumpByName("COLORMAP")) orelse {
            return error.ColormapNotFound;
        };
        defer allocator.free(colormap_data);

        if (colormap_data.len != 34 * 256) {
            return error.InvalidColormapSize;
        }

        var colormap = Colormap{
            .colormaps = undefined,
            .allocator = allocator,
        };

        // Copy data into colormaps array
        for (0..34) |map_idx| {
            @memcpy(&colormap.colormaps[map_idx], colormap_data[map_idx * 256 .. (map_idx + 1) * 256]);
        }

        return colormap;
    }

    pub fn deinit(self: *Colormap) void {
        _ = self;
    }

    /// Get the shaded color index for a given light level
    pub fn getShade(self: *const Colormap, color_idx: u8, light_level: u8) u8 {
        const map_idx = @min(light_level / 8, 33);
        return self.colormaps[map_idx][color_idx];
    }
};

pub const DoomTextureError = error{
    PlaypalNotFound,
    ColormapNotFound,
    InvalidPlaypalSize,
    InvalidColormapSize,
};
