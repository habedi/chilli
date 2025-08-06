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
        .config_path = "",
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

    const run_options = chilli.CommandOptions{
        .name = "run",
        .description = "Runs a task against a list of files.",
        .exec = runExec,
    };
    var run_command = try chilli.Command.init(allocator, run_options);
    try root_command.addSubcommand(run_command);

    try run_command.addPositional(.{
        .name = "task-name",
        .description = "The name of the task to run.",
        .is_required = true,
        .type = .String,
    });
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

    app_ctx.config_path = try ctx.allocator.dupe(u8, config_slice);
    std.debug.print("Welcome to chilli-app!\n", .{});
    std.debug.print("  Using config file: {s}\n\n", .{app_ctx.config_path});
    try ctx.command.printHelp();
}

fn runExec(ctx: chilli.CommandContext) anyerror!void {
    const task_name = try ctx.getArg("task-name", []const u8);
    const files = ctx.getArgs("files");

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

// Example Invocations
//
// 1. Build the example executable:
//    zig build e1_simple_cli
//
// 2. Run with different arguments:
//
//    // Show the help output for the root command
//    ./zig-out/bin/e1_simple_cli --help
//
//    // Run the 'run' subcommand with a task name and a list of files
//    ./zig-out/bin/e1_simple_cli run build-assets main.js styles.css script.js
//
//    // Use the --config flag from the root command
//    ./zig-out/bin/e1_simple_cli --config ./custom.conf run process-logs
//
//    // Use the environment variable to set the config path
//    CHILLI_APP_CONFIG=~/.config/chilli.conf ./zig-out/bin/e1_simple_cli run check-status
