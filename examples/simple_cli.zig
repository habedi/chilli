const std = @import("std");
const chilli = @import("chilli");

const AppContext = struct {
    config_path: []const u8,
    is_dry_run: bool,
};

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app_context = AppContext{
        .config_path = "/etc/chilli.conf",
        .is_dry_run = false,
    };

    const root_options = chilli.CommandOptions{
        .name = "chilli-app",
        .description = "A simple example CLI using Chilli.",
        .version = "v1.0.0",
        .exec = rootExec,
    };
    var root_command = try chilli.Command.init(allocator, root_options);
    defer root_command.deinit();

    const root_dry_run_flag = chilli.Flag{
        .name = "dry-run",
        .shortcut = "d",
        .description = "Performs a dry run without making any changes",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    };
    try root_command.addFlag(root_dry_run_flag);

    const run_options = chilli.CommandOptions{
        .name = "run",
        .description = "Runs a task with a given name.",
        .exec = runExec,
        .section = "Core Commands",
    };
    var run_command = try chilli.Command.init(allocator, run_options);
    // NOTE: Do not deinit a subcommand directly. The parent command's deinit will handle
    // the cleanup of all its children.
    // defer run_command.deinit(); // This was the cause of the double free.

    const verbose_flag = chilli.Flag{
        .name = "verbose",
        .shortcut = "v",
        .description = "Enables verbose logging.",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    };
    try run_command.addFlag(verbose_flag);

    const task_arg = chilli.PositionalArg{
        .name = "task-name",
        .description = "The name of the task to run.",
        .is_required = true,
    };
    try run_command.addPositional(task_arg);

    try root_command.addSubcommand(run_command);

    try root_command.run(&app_context);
}

fn rootExec(ctx: chilli.CommandContext) anyerror!void {
    const app_ctx = ctx.getContextData(AppContext).?;
    app_ctx.is_dry_run = ctx.getFlag("dry-run", bool);

    std.debug.print("Welcome to chilli-app!\n", .{});
    std.debug.print("Dry run mode is: {any}\n", .{app_ctx.is_dry_run});
    std.debug.print("Using config file: {s}\n", .{app_ctx.config_path});
    try ctx.command.printHelp();
}

fn runExec(ctx: chilli.CommandContext) anyerror!void {
    const is_verbose = ctx.getFlag("verbose", bool);
    const task_name = ctx.getPositional(0) orelse "default";

    std.debug.print("Running task '{s}'...\n", .{task_name});
    if (is_verbose) {
        std.debug.print("Verbose logging enabled.\n", .{});
    }

    const app_ctx = ctx.getContextData(AppContext).?;
    std.debug.print("Global dry run setting: {any}\n", .{app_ctx.is_dry_run});
}
