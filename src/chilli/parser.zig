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
    /// Returns `null` if no more arguments are available.
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

/// Parses command-line arguments from an iterator, populating the command's
/// `parsed_flags` and `parsed_positionals` fields.
/// This function handles long flags (`--name`), short flags (`-n`), grouped flags (`-nv`),
/// flags with values (`--name=value` or `-n value`), and positional arguments.
///
/// It returns `errors.Error` on parsing failures, such as encountering an unknown flag or a
/// missing value for a flag that requires one.
pub fn parseArgsAndFlags(cmd: *command.Command, iterator: *ArgIterator) errors.Error!void {
    while (iterator.peek()) |arg| {
        if (std.mem.startsWith(u8, arg, "--")) {
            // Long flag (--flag, --flag=value)
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
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            // Short flag (-f, -fvalue, -f value, -fv)
            const shortcuts = arg[1..];
            iterator.next();

            for (shortcuts, 0..) |shortcut, i| {
                const flag = cmd.findFlag(&[_]u8{shortcut}) orelse return errors.Error.UnknownFlag;

                if (flag.type == .Bool) {
                    try cmd.parsed_flags.append(.{ .name = flag.name, .value = .{ .Bool = true } });
                } else {
                    const value: []const u8 = if (shortcuts.len > i + 1)
                        shortcuts[i + 1 ..]
                    else
                        iterator.peek() orelse return errors.Error.MissingFlagValue;

                    if (shortcuts.len <= i + 1) {
                        iterator.next();
                    }

                    try cmd.parsed_flags.append(.{
                        .name = flag.name,
                        .value = try flag.evaluateValueType(value),
                    });
                    break;
                }
            }
        } else {
            try cmd.parsed_positionals.append(arg);
            iterator.next();
        }
    }
}

/// Validates that all required positional arguments have been provided and that there are
/// no excess arguments.
///
/// Returns `errors.Error.MissingRequiredArgument` or `errors.Error.TooManyArguments` on failure.
pub fn validateArgs(cmd: *command.Command) errors.Error!void {
    for (cmd.positional_args.items, 0..) |expected_arg, i| {
        if (expected_arg.is_required and i >= cmd.parsed_positionals.items.len) {
            return errors.Error.MissingRequiredArgument;
        }
    }
    if (cmd.parsed_positionals.items.len > cmd.positional_args.items.len) {
        return errors.Error.TooManyArguments;
    }
}
