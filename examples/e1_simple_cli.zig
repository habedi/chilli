const std = @import("std");
const chilli = @import("chilli");

const AppContext = struct {
    config_path: []const u8,
};

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app_context = AppContext{
        .config_path = "", // Will be populated by the root command's exec
    };

    const root_options = chilli.CommandOptions{
        .name = "chilli-app",
        .description = "A simple example CLI using Chilli.",
        .version = "v1.0.0",
        .exec = rootExec,
    };
    var root_command = try chilli.Command.init(allocator, root_options);
    defer root_command.deinit();

    const config_flag = chilli.Flag{
        .name = "config",
        .description = "Path to the configuration file",
        .type = .String,
        .default_value = .{ .String = "/etc/chilli.conf" },
        .env_var = "CHILLI_APP_CONFIG",
    };
    try root_command.addFlag(config_flag);

    // --- `run` subcommand with variadic arguments ---
    const run_options = chilli.CommandOptions{
        .name = "run",
        .description = "Runs a task against a list of files.",
        .exec = runExec,
    };
    var run_command = try chilli.Command.init(allocator, run_options);
    try root_command.addSubcommand(run_command);

    // A required, typed positional argument
    try run_command.addPositional(.{
        .name = "task-name",
        .description = "The name of the task to run.",
        .is_required = true,
        .type = .String, // Explicitly a string
    });
    // A variadic positional argument to capture all remaining values
    try run_command.addPositional(.{
        .name = "files",
        .description = "A list of files to process.",
        .variadic = true,
    });

    try root_command.run(&app_context);
}

fn rootExec(ctx: chilli.CommandContext) anyerror!void {
    const app_ctx = ctx.getContextData(AppContext).?;
    const config_slice = try ctx.getFlag("config", []const u8);

    // The slice from getFlag can point to temporary memory. To safely store it,
    // it must be copied. The context's allocator is valid for this exec call.
    app_ctx.config_path = try ctx.allocator.dupe(u8, config_slice);

    std.debug.print("Welcome to chilli-app!\n", .{});
    std.debug.print("  Using config file: {s}\n\n", .{app_ctx.config_path});
    try ctx.command.printHelp();
}

fn runExec(ctx: chilli.CommandContext) anyerror!void {
    // Access positional arguments by name, now with type safety
    const task_name = try ctx.getArg("task-name", []const u8);
    const files = ctx.getArgs("files"); // Variadic arguments remain string slices

    std.debug.print("Running task '{s}'...\n", .{task_name});

    if (files.len == 0) {
        std.debug.print("No files provided to process.\n", .{});
    } else {
        std.debug.print("Processing {d} files:\n", .{files.len});
        for (files) |file| {
            std.debug.print("  - {s}\n", .{file});
        }
    }
}
