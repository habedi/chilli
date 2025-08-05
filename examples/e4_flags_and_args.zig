const std = @import("std");
const chilli = @import("chilli");

fn exec(ctx: chilli.CommandContext) !void {
    const count = try ctx.getFlag("count", i32);
    const message = try ctx.getFlag("message", []const u8);
    const force = try ctx.getFlag("force", bool);

    const required_arg = try ctx.getArg("required-arg", []const u8);
    const optional_arg = try ctx.getArg("optional-arg", []const u8);
    const variadic_args = ctx.getArgs("variadic-args");

    std.debug.print("Flags:\n", .{});
    std.debug.print("  --count: {d}\n", .{count});
    std.debug.print("  --message: {s}\n", .{message});
    std.debug.print("  --force: {}\n", .{force});

    std.debug.print("\nArguments:\n", .{});
    std.debug.print("  required-arg: {s}\n", .{required_arg});
    std.debug.print("  optional-arg: {s}\n", .{optional_arg});
    std.debug.print("  variadic-args: {s}\n", .{variadic_args});
}

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var root_cmd = try chilli.Command.init(allocator, .{
        .name = "flags-args-demo",
        .description = "Demonstrates various flags and arguments.",
        .exec = exec,
    });
    defer root_cmd.deinit();

    try root_cmd.addFlag(.{
        .name = "count",
        .shortcut = 'c',
        .description = "A number of times to do something.",
        .type = .Int,
        .default_value = .{ .Int = 1 },
    });

    try root_cmd.addFlag(.{
        .name = "message",
        .description = "A message to print.",
        .type = .String,
        .default_value = .{ .String = "default message" },
    });

    try root_cmd.addFlag(.{
        .name = "force",
        .shortcut = 'f',
        .description = "Force an operation.",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    });

    try root_cmd.addPositional(.{
        .name = "required-arg",
        .description = "A required argument (now optional for 'make run' to succeed).",
        .is_required = false,
        .default_value = .{ .String = "default-required-val" },
    });

    try root_cmd.addPositional(.{
        .name = "optional-arg",
        .description = "An optional argument.",
        .is_required = false,
        .default_value = .{ .String = "default value" },
    });

    try root_cmd.addPositional(.{
        .name = "variadic-args",
        .description = "Any number of additional arguments.",
        .variadic = true,
    });

    try root_cmd.run(null);
}
