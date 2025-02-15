const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Main game executable
    const exe = b.addExecutable(.{
        .name = "zoom",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkSystemLibrary("SDL2");
    exe.linkLibC();
    b.installArtifact(exe);

    // Texture generator executable
    const gen_textures = b.addExecutable(.{
        .name = "gen_textures",
        .root_source_file = b.path("src/gen_textures.zig"),
        .target = target,
        .optimize = optimize,
    });
    gen_textures.linkSystemLibrary("SDL2");
    gen_textures.linkLibC();
    b.installArtifact(gen_textures);

    // Texture viewer executable
    const texture_viewer = b.addExecutable(.{
        .name = "texture_viewer",
        .root_source_file = b.path("src/texture_viewer.zig"),
        .target = target,
        .optimize = optimize,
    });
    texture_viewer.linkSystemLibrary("SDL2");
    texture_viewer.linkSystemLibrary("SDL2_ttf");
    texture_viewer.linkLibC();
    b.installArtifact(texture_viewer);

    // WAD reader executable
    const wad_reader = b.addExecutable(.{
        .name = "wad_reader",
        .root_source_file = b.path("src/wad_reader.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(wad_reader);

    // Test WAD generator executable
    const gen_test_wad = b.addExecutable(.{
        .name = "gen_test_wad",
        .root_source_file = b.path("src/gen_test_wad.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(gen_test_wad);

    // Lump viewer executable
    const lump_viewer = b.addExecutable(.{
        .name = "lump_viewer",
        .root_source_file = b.path("src/lump_viewer.zig"),
        .target = target,
        .optimize = optimize,
    });
    lump_viewer.linkSystemLibrary("SDL2");
    lump_viewer.linkSystemLibrary("SDL2_ttf");
    lump_viewer.linkLibC();
    b.installArtifact(lump_viewer);

    // Add a step to generate test WAD
    const gen_test_wad_step = b.step("gen-test-wad", "Generate test WAD file");
    const gen_test_wad_run = b.addRunArtifact(gen_test_wad);
    gen_test_wad_step.dependOn(&gen_test_wad_run.step);

    // Add a step to generate textures
    const gen_textures_step = b.step("gen-textures", "Generate wall textures");
    const gen_textures_run = b.addRunArtifact(gen_textures);
    gen_textures_step.dependOn(&gen_textures_run.step);

    // Add a step to run wad reader
    const wad_reader_step = b.step("wad-reader", "Run WAD reader");
    const wad_reader_run = b.addRunArtifact(wad_reader);
    if (b.args) |args| {
        wad_reader_run.addArgs(args);
    }
    wad_reader_step.dependOn(&wad_reader_run.step);

    // Add a step to run texture viewer
    const texture_viewer_step = b.step("view-textures", "Run texture viewer");
    const texture_viewer_run = b.addRunArtifact(texture_viewer);
    if (b.args) |args| {
        texture_viewer_run.addArgs(args);
    }
    texture_viewer_step.dependOn(&texture_viewer_run.step);

    // Add a step to run lump viewer
    const lump_viewer_step = b.step("view-lump", "Run lump viewer");
    const lump_viewer_run = b.addRunArtifact(lump_viewer);
    if (b.args) |args| {
        lump_viewer_run.addArgs(args);
    }
    lump_viewer_step.dependOn(&lump_viewer_run.step);

    // Run step for the game
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the game");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.linkSystemLibrary("SDL2");
    unit_tests.linkLibC();

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
