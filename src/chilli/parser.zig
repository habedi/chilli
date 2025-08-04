const std = @import("std");
const command = @import("command.zig");
const utils = @import("utils.zig");
const types = @import("types.zig");

pub const ArgIterator = struct {
    args: []const []const u8,
    index: usize,

    pub fn init(args: []const []const u8) ArgIterator {
        return ArgIterator{ .args = args, .index = 0 };
    }

    pub fn peek(self: *const ArgIterator) ?[]const u8 {
        if (self.index >= self.args.len) return null;
        return self.args[self.index];
    }

    pub fn next(self: *ArgIterator) void {
        self.index += 1;
    }
};

pub const ParsedFlag = struct {
    name: []const u8,
    value: types.FlagValue,
};

pub const ParseError = error{
UnknownFlag,
MissingFlagValue,
InvalidFlagGrouping,
MissingRequiredArgument,
} || types.Flag.EvaluateError;

pub fn parseArgsAndFlags(cmd: *command.Command, iterator: *ArgIterator) !void {
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

            const flag = cmd.findFlag(flag_name) orelse return error.UnknownFlag;

            if (flag.type == .Bool) {
                const flag_value = if (value) |v| try utils.parseBool(v) else true;
                try cmd.parsed_flags.append(.{
                    .name = flag_name,
                    .value = .{ .Bool = flag_value },
                });
                iterator.next();
            } else {
                iterator.next();
                const val = value orelse iterator.peek() orelse return error.MissingFlagValue;
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
                const flag = cmd.findFlag(&[_]u8{shortcut}) orelse return error.UnknownFlag;

                if (flag.type == .Bool) {
                    try cmd.parsed_flags.append(.{ .name = flag.name, .value = .{ .Bool = true } });
                } else {
                    // This is a non-boolean flag, so it expects a value.
                    const value: []const u8 = if (shortcuts.len > i + 1)
                        // Value is attached (e.g., -fvalue)
                        shortcuts[i + 1 ..]
                    else
                        // Value is the next argument (e.g., -f value)
                        iterator.peek() orelse return error.MissingFlagValue;

                    if (shortcuts.len <= i + 1) {
                        iterator.next();
                    }

                    try cmd.parsed_flags.append(.{
                        .name = flag.name,
                        .value = try flag.evaluateValueType(value),
                    });

                    // A non-boolean flag must be the last one in a group.
                    break;
                }
            }
        } else {
            try cmd.parsed_positionals.append(arg);
            iterator.next();
        }
    }
}

pub fn validateArgs(cmd: *command.Command) !void {
    for (cmd.positional_args.items, 0..) |expected_arg, i| {
        if (expected_arg.is_required and i >= cmd.parsed_positionals.items.len) {
            return error.MissingRequiredArgument;
        }
    }
}
