const std = @import("std");
const fs = std.fs;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- Library Setup ---
    const lib_source = b.path("src/lib.zig");

    const lib = b.addStaticLibrary(.{
        .name = "chilli",
        .root_source_file = lib_source,
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const lib_module = b.createModule(.{
        .root_source_file = lib_source,
    });

    // --- Test Setup ---
    const lib_unit_tests = b.addTest(.{
        .root_source_file = lib_source,
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // --- Example Setup ---
    const examples_path = "examples";
    var examples_dir = fs.cwd().openDir(examples_path, .{ .iterate = true }) catch @panic("Can't open 'examples' directory");
    defer examples_dir.close();

    var dir_iter = examples_dir.iterate();
    while (dir_iter.next() catch @panic("Failed to iterate examples")) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;

        const exe_name = fs.path.stem(entry.name);
        const exe_path = b.fmt("{s}/{s}", .{ examples_path, entry.name });

        const exe = b.addExecutable(.{
            .name = exe_name,
            .root_source_file = b.path(exe_path),
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("chilli", lib_module);
        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        const run_step_name = b.fmt("run-{s}", .{exe_name});
        const run_step_desc = b.fmt("Run the {s} example", .{exe_name});
        const run_step = b.step(run_step_name, run_step_desc);
        run_step.dependOn(&run_cmd.step);
    }
}
