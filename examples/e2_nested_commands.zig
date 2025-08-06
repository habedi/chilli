const std = @import("std");
const chilli = @import("chilli");

fn rootExec(ctx: chilli.CommandContext) !void {
    try ctx.command.printHelp();
}

fn dbMigrateExec(ctx: chilli.CommandContext) !void {
    _ = ctx;
    std.debug.print("Running database migrations...\n", .{});
}

fn dbSeedExec(ctx: chilli.CommandContext) !void {
    const file = try ctx.getArg("file", []const u8);
    std.debug.print("Seeding database from file: {s}\n", .{file});
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var root_cmd = try chilli.Command.init(allocator, .{
        .name = "app",
        .description = "An application with nested commands.",
        .exec = rootExec,
    });
    defer root_cmd.deinit();

    var db_cmd = try chilli.Command.init(allocator, .{
        .name = "db",
        .description = "Manage the application database.",
        .exec = rootExec,
    });
    try root_cmd.addSubcommand(db_cmd);

    const db_migrate_cmd = try chilli.Command.init(allocator, .{
        .name = "migrate",
        .description = "Run database migrations.",
        .exec = dbMigrateExec,
    });
    try db_cmd.addSubcommand(db_migrate_cmd);

    var db_seed_cmd = try chilli.Command.init(allocator, .{
        .name = "seed",
        .description = "Seed the database with initial data.",
        .exec = dbSeedExec,
    });
    try db_cmd.addSubcommand(db_seed_cmd);

    try db_seed_cmd.addPositional(.{
        .name = "file",
        .description = "The seed file to use.",
        .is_required = true,
    });

    try root_cmd.run(null);
}

// Example Invocations
//
// 1. Build the example executable:
//    zig build e2_nested_commands
//
// 2. Run with different arguments:
//
//    // Show help for the root 'app' command
//    ./zig-out/bin/e2_nested_commands --help
//
//    // Show help for the 'db' subcommand
//    ./zig-out/bin/e2_nested_commands db --help
//
//    // Execute the 'db migrate' command
//    ./zig-out/bin/e2_nested_commands db migrate
//
//    // Execute the 'db seed' command with its required file argument
//    ./zig-out/bin/e2_nested_commands db seed data/seeds.sql
