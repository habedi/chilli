//! Handles the parsing of command-line arguments into flags and positional values.
const std = @import("std");
const command = @import("command.zig");
const utils = @import("utils.zig");
const types = @import("types.zig");
const errors = @import("errors.zig");

/// A simple forward-only iterator over a slice of string arguments.
pub const ArgIterator = struct {
    args: []const []const u8,
    index: usize,

    /// Initializes a new iterator for the given argument slice.
    pub fn init(args: []const []const u8) ArgIterator {
        return ArgIterator{ .args = args, .index = 0 };
    }

    /// Peeks at the next argument without consuming it.
    pub fn peek(self: *const ArgIterator) ?[]const u8 {
        if (self.index >= self.args.len) return null;
        return self.args[self.index];
    }

    /// Consumes the next argument, advancing the iterator.
    pub fn next(self: *ArgIterator) void {
        self.index += 1;
    }
};

/// An internal struct to hold a parsed flag and its value.
pub const ParsedFlag = struct {
    name: []const u8,
    value: types.FlagValue,
};

/// Parses command-line arguments from an iterator.
pub fn parseArgsAndFlags(cmd: *command.Command, iterator: *ArgIterator) errors.Error!void {
    var parsing_flags = true;
    while (iterator.peek()) |arg| {
        if (parsing_flags) {
            if (std.mem.eql(u8, arg, "--")) {
                parsing_flags = false;
                iterator.next();
                continue;
            }

            if (std.mem.startsWith(u8, arg, "--")) {
                const arg_body = arg[2..];
                var flag_name: []const u8 = arg_body;
                var value: ?[]const u8 = null;

                if (std.mem.indexOfScalar(u8, arg_body, '=')) |eq_idx| {
                    flag_name = arg_body[0..eq_idx];
                    value = arg_body[eq_idx + 1 ..];
                }

                const flag = cmd.findFlag(flag_name) orelse return errors.Error.UnknownFlag;

                if (flag.type == .Bool) {
                    const flag_value = if (value) |v| try utils.parseBool(v) else true;
                    try cmd.parsed_flags.append(.{
                        .name = flag_name,
                        .value = .{ .Bool = flag_value },
                    });
                    iterator.next();
                } else {
                    iterator.next();
                    const val = value orelse iterator.peek() orelse return errors.Error.MissingFlagValue;
                    if (value == null) {
                        iterator.next();
                    }
                    try cmd.parsed_flags.append(.{
                        .name = flag_name,
                        .value = try flag.evaluateValueType(val),
                    });
                }
                continue;
            }

            if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
                const shortcuts = arg[1..];
                iterator.next();

                for (shortcuts, 0..) |shortcut, i| {
                    const flag = cmd.findFlag(&[_]u8{shortcut}) orelse return errors.Error.UnknownFlag;

                    if (flag.type == .Bool) {
                        try cmd.parsed_flags.append(.{ .name = flag.name, .value = .{ .Bool = true } });
                    } else {
                        var value: []const u8 = undefined;
                        var value_from_next_arg = false;

                        if (shortcuts.len > i + 1) {
                            value = shortcuts[i + 1 ..];
                            if (value.len > 0 and value[0] == '=') {
                                value = value[1..];
                            }
                        } else {
                            value = iterator.peek() orelse return errors.Error.MissingFlagValue;
                            value_from_next_arg = true;
                        }

                        if (value_from_next_arg) {
                            iterator.next();
                        }

                        try cmd.parsed_flags.append(.{
                            .name = flag.name,
                            .value = try flag.evaluateValueType(value),
                        });
                        break;
                    }
                }
                continue;
            }
        }

        try cmd.parsed_positionals.append(arg);
        iterator.next();
    }
}

/// Validates that all required positional arguments have been provided and that there are
/// no excess arguments unless a variadic argument is defined.
pub fn validateArgs(cmd: *command.Command) errors.Error!void {
    const num_defined = cmd.positional_args.items.len;
    const num_parsed = cmd.parsed_positionals.items.len;

    if (num_defined == 0) {
        if (num_parsed > 0) return errors.Error.TooManyArguments;
        return;
    }

    const last_arg_def = cmd.positional_args.items[num_defined - 1];
    const has_variadic = last_arg_def.variadic;

    var required_count: usize = 0;
    for (cmd.positional_args.items) |arg_def| {
        if (arg_def.is_required) {
            required_count += 1;
        }
    }
    if (num_parsed < required_count) {
        return errors.Error.MissingRequiredArgument;
    }

    if (!has_variadic and num_parsed > num_defined) {
        return errors.Error.TooManyArguments;
    }
}

const context = @import("context.zig");
fn dummyExec(_: context.CommandContext) !void {}

test "parser: short flag with equals" {
    const allocator = std.testing.allocator;
    var cmd = try command.Command.init(allocator, .{
        .name = "test",
        .description = "",
        .exec = dummyExec,
    });
    defer cmd.deinit();

    try cmd.addFlag(.{
        .name = "output",
        .shortcut = "o",
        .description = "Output file",
        .type = .String,
        .default_value = .{ .String = "" },
    });

    var it = ArgIterator.init(&[_][]const u8{"-o=test.txt"});
    try parseArgsAndFlags(&cmd, &it);

    try std.testing.expectEqual(1, cmd.parsed_flags.items.len);
    try std.testing.expectEqualStrings("output", cmd.parsed_flags.items[0].name);

    const value = cmd.parsed_flags.items[0].value;
    switch (value) {
        .String => |s| try std.testing.expectEqualStrings("test.txt", s),
        else => std.testing.panic("Expected string value, got {any}", .{value}),
    }
}
