const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // register the flag so `-Denable-coverage=true` is valid
    const coverageOpt = b.option(bool, "enable-coverage", "Enable coverage instrumentation");
    const coverage = coverageOpt orelse false;
    _ = coverage; // autofix

    const lib = b.addStaticLibrary(.{
        .name = "template_zig_project",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "template-zig-project",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const run_artifact = b.addRunArtifact(exe);
    if (b.args) |args| run_artifact.addArgs(args);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_artifact.step);

    const test_step = b.step("test", "Run unit tests");

    {
        const lib_tests = b.addTest(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        lib_tests.root_module.addImport("template_zig_project", lib.root_module);
        const lib_run = b.addRunArtifact(lib_tests);
        test_step.dependOn(&lib_run.step);
        const lib_install = b.addInstallArtifact(lib_tests, .{ .dest_sub_path = "test-root" });
        test_step.dependOn(&lib_install.step);
    }

    {
        const ext_tests = b.addTest(.{
            .root_source_file = b.path("tests/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        ext_tests.root_module.addImport("template_zig_project", lib.root_module);
        const ext_run = b.addRunArtifact(ext_tests);
        test_step.dependOn(&ext_run.step);
        const ext_install = b.addInstallArtifact(ext_tests, .{ .dest_sub_path = "test-ext" });
        test_step.dependOn(&ext_install.step);
    }

    const doc_step = b.step("doc", "Generate documentation");
    const doc_cmd = b.addSystemCommand(&[_][]const u8{
        "zig", "doc", "--output-dir", "doc", "src/root.zig",
    });
    doc_step.dependOn(&doc_cmd.step);
}
