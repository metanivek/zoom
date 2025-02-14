const std = @import("std");
const wad = @import("wad.zig");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get WAD file path from command line arguments
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip program name
    _ = args.next();

    // Get WAD file path
    const wad_path = args.next() orelse {
        std.debug.print("Usage: {s} <wad_file>\n", .{args.next().?});
        return error.InvalidArguments;
    };

    // Load WAD file
    var wad_file = try wad.WadFile.init(allocator, wad_path);
    defer wad_file.deinit();

    // Print WAD header information
    std.debug.print("\nWAD File Analysis: {s}\n", .{wad_path});
    std.debug.print("==============================\n", .{});
    std.debug.print("\nHeader Information:\n", .{});
    std.debug.print("-----------------\n", .{});
    std.debug.print("Type: {s}\n", .{if (wad_file.header.isIWAD()) "IWAD (Internal WAD)" else "PWAD (Patch WAD)"});
    std.debug.print("Number of lumps: {d}\n", .{wad_file.header.num_lumps});
    std.debug.print("Directory offset: 0x{X}\n", .{wad_file.header.dir_pointer});

    // Print directory entries
    std.debug.print("\nDirectory Listing:\n", .{});
    std.debug.print("-----------------\n", .{});
    std.debug.print("Index  Name     Size       Offset     \n", .{});
    std.debug.print("-----  ----     ----       ------     \n", .{});

    for (wad_file.directory, 0..) |*entry, i| {
        std.debug.print("{d:4}   {s: <8} {d:10} 0x{X:08}\n", .{
            i,
            entry.getName(),
            entry.size,
            entry.file_pos,
        });
    }

    // Print detailed lump information if requested
    const should_dump = args.next() orelse "";
    if (std.mem.eql(u8, should_dump, "--dump")) {
        std.debug.print("\nLump Contents:\n", .{});
        std.debug.print("-------------\n", .{});

        for (wad_file.directory) |*entry| {
            const name = entry.getName();
            const data = wad_file.readLump(entry) catch |err| {
                std.debug.print("Error reading lump {s}: {any}\n", .{ name, err });
                continue;
            };
            defer allocator.free(data);

            std.debug.print("\nLump: {s}\n", .{name});
            std.debug.print("Size: {d} bytes\n", .{data.len});
            std.debug.print("First 64 bytes (hex):\n", .{});

            // Print up to 64 bytes in hex format
            const bytes_to_show = @min(data.len, 64);
            var i: usize = 0;
            while (i < bytes_to_show) : (i += 1) {
                if (i % 16 == 0) std.debug.print("\n{X:04}: ", .{i});
                std.debug.print("{X:02} ", .{data[i]});
            }
            std.debug.print("\n", .{});

            // Try to print as text if it looks like text
            var is_text = true;
            for (data) |byte| {
                if (byte < 32 and byte != '\n' and byte != '\r' and byte != '\t') {
                    is_text = false;
                    break;
                }
            }

            if (is_text) {
                std.debug.print("\nContents (as text):\n", .{});
                std.debug.print("------------------\n", .{});
                std.debug.print("{s}\n", .{data});
            }
        }
    }
}
