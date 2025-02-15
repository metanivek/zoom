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
        std.debug.print("Usage: {s} <wad_file> [lump_name] [--dump]\n", .{args.next().?});
        return error.InvalidArguments;
    };

    // Load WAD file
    var wad_file = try wad.WadFile.init(allocator, wad_path);
    defer wad_file.deinit();

    // Print WAD header information
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\nWAD File Analysis: {s}\n", .{wad_path});
    try stdout.print("==============================\n", .{});
    try stdout.print("\nHeader Information:\n", .{});
    try stdout.print("-----------------\n", .{});
    try stdout.print("Type: {s}\n", .{if (wad_file.header.isIWAD()) "IWAD (Internal WAD)" else "PWAD (Patch WAD)"});
    try stdout.print("Number of lumps: {d}\n", .{wad_file.header.num_lumps});
    try stdout.print("Directory offset: 0x{X} ({d})\n", .{ wad_file.header.dir_pointer, wad_file.header.dir_pointer });

    // Get optional lump name
    const lump_name = args.next();
    if (lump_name) |name| {
        // Find lump by name
        for (wad_file.directory, 0..) |*entry, i| {
            if (std.mem.eql(u8, entry.getName(), name)) {
                std.debug.print("\nLump Information:\n", .{});
                std.debug.print("-----------------\n", .{});
                std.debug.print("Index: {d}\n", .{i});
                std.debug.print("Name: {s}\n", .{entry.getName()});
                std.debug.print("Size: {d} bytes\n", .{entry.size});
                std.debug.print("Offset: 0x{X:0>8} ({d})\n", .{ entry.file_pos, entry.file_pos });

                // Check if --dump flag is present
                const dump_flag = args.next();
                if (dump_flag != null and std.mem.eql(u8, dump_flag.?, "--dump")) {
                    const data = try wad_file.readLump(entry);
                    defer allocator.free(data);

                    // Print header bytes if present
                    if (data.len >= 8) {
                        std.debug.print("\nHeader bytes:\n", .{});
                        std.debug.print("Width: {X:0>2}{X:0>2} ({d})\n", .{ data[1], data[0], std.mem.readInt(i16, data[0..2], .little) });
                        std.debug.print("Height: {X:0>2}{X:0>2} ({d})\n", .{ data[3], data[2], std.mem.readInt(i16, data[2..4], .little) });
                        std.debug.print("Left offset: {X:0>2}{X:0>2} ({d})\n", .{ data[5], data[4], std.mem.readInt(i16, data[4..6], .little) });
                        std.debug.print("Top offset: {X:0>2}{X:0>2} ({d})\n", .{ data[7], data[6], std.mem.readInt(i16, data[6..8], .little) });
                    }

                    // Print rest of data in hex
                    std.debug.print("\nData dump:\n", .{});
                    var offset: usize = 0;
                    while (offset < data.len) : (offset += 16) {
                        // Print offset
                        std.debug.print("{X:0>4}: ", .{offset});

                        // Print hex bytes
                        var byte_idx: usize = 0;
                        while (byte_idx < 16 and offset + byte_idx < data.len) : (byte_idx += 1) {
                            std.debug.print("{X:0>2} ", .{data[offset + byte_idx]});
                        }

                        // Print ASCII representation
                        while (byte_idx < 16) : (byte_idx += 1) {
                            std.debug.print("   ", .{});
                        }
                        std.debug.print(" | ", .{});
                        byte_idx = 0;
                        while (byte_idx < 16 and offset + byte_idx < data.len) : (byte_idx += 1) {
                            const c = data[offset + byte_idx];
                            if (std.ascii.isPrint(c)) {
                                std.debug.print("{c}", .{c});
                            } else {
                                std.debug.print(".", .{});
                            }
                        }
                        std.debug.print("\n", .{});
                    }

                    // If this looks like a patch, analyze the post data
                    if (data.len >= 8) {
                        const width = std.mem.readInt(i16, data[0..2], .little);
                        const height = std.mem.readInt(i16, data[2..4], .little);
                        if (width > 0 and width <= 4096 and height > 0 and height <= 4096) {
                            std.debug.print("\nPatch Analysis:\n", .{});
                            std.debug.print("-----------------\n", .{});
                            std.debug.print("Width: {d}\n", .{width});
                            std.debug.print("Height: {d}\n", .{height});
                            std.debug.print("Left offset: {d}\n", .{std.mem.readInt(i16, data[4..6], .little)});
                            std.debug.print("Top offset: {d}\n", .{std.mem.readInt(i16, data[6..8], .little)});

                            // Analyze first column
                            if (data.len >= 12) {
                                const first_col_offset = std.mem.readInt(u32, data[8..12], .little);
                                const col_start = 8 + @as(usize, @intCast(width)) * 4 + first_col_offset;
                                if (col_start < data.len) {
                                    std.debug.print("\nFirst Column Data (at offset 0x{X:0>8} ({d})):\n", .{ col_start, col_start });
                                    var pos = col_start;
                                    var post_count: u32 = 0;
                                    while (pos + 2 <= data.len and post_count < 100) : (post_count += 1) {
                                        const top_delta = data[pos];
                                        if (top_delta == 0xFF) {
                                            std.debug.print("End of column marker (0xFF) at offset 0x{X:0>8} ({d})\n", .{ pos, pos });
                                            break;
                                        }
                                        const length = data[pos + 1];
                                        std.debug.print("Post {d}: top_delta={d}, length={d}\n", .{ post_count, top_delta, length });
                                        if (pos + 2 + length + 2 > data.len) {
                                            std.debug.print("Warning: Post data would exceed lump size\n", .{});
                                            break;
                                        }
                                        std.debug.print("  Padding1: 0x{X:0>2}\n", .{data[pos + 2]});
                                        std.debug.print("  Pixels: ", .{});
                                        for (data[pos + 3 .. pos + 3 + length]) |pixel| {
                                            std.debug.print("{X:0>2} ", .{pixel});
                                        }
                                        std.debug.print("\n  Padding2: 0x{X:0>2}\n", .{data[pos + 3 + length]});
                                        pos = (std.math.add(usize, pos, (std.math.add(usize, 4, length) catch {
                                            std.debug.print("Warning: Integer overflow in post data\n", .{});
                                            return;
                                        })) catch {
                                            std.debug.print("Warning: Integer overflow in post data\n", .{});
                                            return;
                                        });
                                    }
                                }
                            }
                        }
                    }
                }
                break;
            }
        }
    } else {
        // Print directory entries
        std.debug.print("\nDirectory Listing:\n", .{});
        std.debug.print("-----------------\n", .{});
        std.debug.print("Index  Name     Size       Offset     \n", .{});
        std.debug.print("-----  ----     ----       ------     \n", .{});

        for (wad_file.directory, 0..) |*entry, i| {
            std.debug.print("{d:4}   {s: <8} {d:10} 0x{X:08} ({d})\n", .{
                i,
                entry.getName(),
                entry.size,
                entry.file_pos,
                entry.file_pos,
            });
        }
    }
}
