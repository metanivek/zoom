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

    // Create a module for shared code
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Main game executable
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("zoom_lib", lib_mod);

    const exe = b.addExecutable(.{
        .name = "zoom",
        .root_module = exe_mod,
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

    // Add a step to generate test WAD
    const gen_test_wad_step = b.step("gen-test-wad", "Generate test WAD file");
    const gen_test_wad_run = b.addRunArtifact(gen_test_wad);
    gen_test_wad_step.dependOn(&gen_test_wad_run.step);

    // Add a step to generate textures
    const gen_textures_step = b.step("gen-textures", "Generate wall textures");
    const gen_textures_run = b.addRunArtifact(gen_textures);
    gen_textures_step.dependOn(&gen_textures_run.step);

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
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
