//! Provides the execution context for a command, giving access to parsed arguments and flags.
const std = @import("std");
const types = @import("types.zig");
const command = @import("command.zig");
const errors = @import("errors.zig");

/// Provides access to command-line data within a command's execution function (`exec`).
/// An instance of `CommandContext` is passed to every `exec` function.
pub const CommandContext = struct {
    /// The allocator for this execution context. For operations that require allocation,
    /// like retrieving environment variables, this allocator should be used. Memory is
    /// valid for the lifetime of the `exec` call.
    allocator: std.mem.Allocator,
    /// A pointer to the command that is being executed.
    command: *command.Command,
    /// A pointer to optional, user-defined data passed to the `run` function.
    data: ?*anyopaque,

    /// Retrieves the value of a flag by name with compile-time type checking.
    /// This function can return an error for invalid runtime values, such as a
    /// malformed environment variable or an out-of-range integer.
    pub fn getFlag(self: *const CommandContext, name: []const u8, comptime T: type) errors.Error!T {
        if (self.command.getFlagValue(name)) |parsed_value| {
            return switch (T) {
                bool => if (parsed_value == .Bool) parsed_value.Bool else std.debug.panic("Type mismatch for flag '{s}': expected bool, but it was parsed as {s}", .{ name, @tagName(parsed_value) }),
                []const u8 => if (parsed_value == .String) parsed_value.String else std.debug.panic("Type mismatch for flag '{s}': expected string, but it was parsed as {s}", .{ name, @tagName(parsed_value) }),
                else => switch (@typeInfo(T)) {
                    .Int => if (parsed_value == .Int)
                        try std.math.cast(T, parsed_value.Int) orelse return errors.Error.IntegerValueOutOfRange
                    else
                        std.debug.panic("Type mismatch for flag '{s}': expected int, but it was parsed as {s}", .{ name, @tagName(parsed_value) }),
                    else => @compileError("Unsupported type for getFlag: " ++ @typeName(T)),
                },
            };
        }

        const flag_def = self.command.findFlag(name) orelse std.debug.panic("Attempted to access an undefined flag: '{s}'", .{name});

        if (flag_def.env_var) |env_name| {
            if (std.process.getEnvVarOwned(self.allocator, env_name) catch null) |env_val_str| {
                const env_value = try flag_def.evaluateValueType(env_val_str);

                return switch (T) {
                    bool => if (env_value == .Bool) env_value.Bool else std.debug.panic("Type mismatch for flag '{s}' from env '{s}': expected bool, got {s}", .{ name, env_name, @tagName(env_value) }),
                    []const u8 => if (env_value == .String) env_value.String else std.debug.panic("Type mismatch for flag '{s}' from env '{s}': expected string, got {s}", .{ name, env_name, @tagName(env_value) }),
                    else => switch (@typeInfo(T)) {
                        .Int => if (env_value == .Int)
                            try std.math.cast(T, env_value.Int) orelse return errors.Error.IntegerValueOutOfRange
                        else
                            std.debug.panic("Type mismatch for flag '{s}' from env '{s}': expected int, got {s}", .{ name, env_name, @tagName(env_value) }),
                        else => @compileError("Unsupported type for getFlag: " ++ @typeName(T)),
                    },
                };
            }
        }

        const default_val = flag_def.default_value;

        return switch (T) {
            bool => if (default_val == .Bool) default_val.Bool else std.debug.panic("Default type mismatch for flag '{s}': expected bool, got {s}", .{ name, @tagName(default_val) }),
            []const u8 => if (default_val == .String) default_val.String else std.debug.panic("Default type mismatch for flag '{s}': expected string, got {s}", .{ name, @tagName(default_val) }),
            else => switch (@typeInfo(T)) {
                .Int => if (default_val == .Int)
                    try std.math.cast(T, default_val.Int) orelse return errors.Error.IntegerValueOutOfRange
                else
                    std.debug.panic("Default type mismatch for flag '{s}': expected int, got {s}", .{ name, @tagName(default_val) }),
                else => @compileError("Unsupported type for getFlag: " ++ @typeName(T)),
            },
        };
    }

    /// Retrieves the value of a single (non-variadic) positional argument by its defined name.
    ///
    /// - `name`: The name of the positional argument to retrieve.
    /// - `T`: The type to which the argument should be parsed.
    ///
    /// Returns the parsed value. Can return an error for invalid values or out-of-range numbers.
    /// Panics if the argument name is not defined, or if the argument is variadic (use `getArgs` instead).
    pub fn getArg(self: *const CommandContext, name: []const u8, comptime T: type) errors.Error!T {
        var arg_def: ?*const types.PositionalArg = null;
        var arg_idx: ?usize = null;

        for (self.command.positional_args.items, 0..) |*item, i| {
            if (std.mem.eql(u8, item.name, name)) {
                arg_def = item;
                arg_idx = i;
                break;
            }
        }

        const found_arg = arg_def orelse std.debug.panic("Attempted to access an undefined positional argument: '{s}'", .{name});
        if (found_arg.variadic) {
            std.debug.panic("Positional argument '{s}' is variadic. Use getArgs() instead.", .{name});
        }

        // Check if a value was parsed for this argument's position
        if (arg_idx.? < self.command.parsed_positionals.items.len) {
            const raw_value = self.command.parsed_positionals.items[arg_idx.?];
            const parsed_value = try found_arg.evaluateValueType(raw_value);

            return switch (T) {
                bool => if (parsed_value == .Bool) parsed_value.Bool else std.debug.panic("Type mismatch for argument '{s}'", .{name}),
                []const u8 => if (parsed_value == .String) parsed_value.String else std.debug.panic("Type mismatch for argument '{s}'", .{name}),
                else => switch (@typeInfo(T)) {
                    .Int => if (parsed_value == .Int)
                        try std.math.cast(T, parsed_value.Int) orelse return errors.Error.IntegerValueOutOfRange
                    else
                        std.debug.panic("Type mismatch for argument '{s}'", .{name}),
                    else => @compileError("Unsupported type for getArg: " ++ @typeName(T)),
                },
            };
        }

        // If no value parsed, use the default value if available
        if (found_arg.default_value) |default_val| {
            return switch (T) {
                bool => if (default_val == .Bool) default_val.Bool else std.debug.panic("Default type mismatch for argument '{s}'", .{name}),
                []const u8 => if (default_val == .String) default_val.String else std.debug.panic("Default type mismatch for argument '{s}'", .{name}),
                else => switch (@typeInfo(T)) {
                    .Int => if (default_val == .Int)
                        try std.math.cast(T, default_val.Int) orelse return errors.Error.IntegerValueOutOfRange
                    else
                        std.debug.panic("Default type mismatch for argument '{s}'", .{name}),
                    else => @compileError("Unsupported type for getArg: " ++ @typeName(T)),
                },
            };
        }

        // This path should not be reached for a required argument due to `validateArgs`.
        // For an optional argument, a default_value should have been provided by the developer.
        std.debug.panic("No value or default value found for argument '{s}'", .{name});
    }

    /// Retrieves all values captured by a variadic positional argument by its defined name.
    ///
    /// - `name`: The name of the variadic positional argument.
    ///
    /// Returns a slice of all captured values. Returns an empty slice if no values were provided.
    /// Panics if the argument name is not defined, or if the argument is not variadic (use `getArg` instead).
    pub fn getArgs(self: *const CommandContext, name: []const u8) []const []const u8 {
        for (self.command.positional_args.items, 0..) |arg_def, i| {
            if (std.mem.eql(u8, arg_def.name, name)) {
                if (!arg_def.variadic) {
                    std.debug.panic("Positional argument '{s}' is not variadic. Use getArg() instead.", .{name});
                }
                const num_parsed = self.command.parsed_positionals.items.len;
                if (num_parsed <= i) {
                    return &.{};
                }
                return self.command.parsed_positionals.items[i..];
            }
        }
        std.debug.panic("Attempted to access an undefined positional argument: '{s}'", .{name});
    }

    /// (DEPRECATED) Retrieves a positional argument by index. Use `getArg` or `getArgs` instead.
    pub fn getPositional(self: *const CommandContext, index: usize) ?[]const u8 {
        return self.command.getPositionalValue(index);
    }

    /// Retrieves the shared, user-defined context data.
    pub fn getContextData(self: *const CommandContext, comptime T: type) ?*T {
        if (self.data) |d| {
            return @alignCast(@ptrCast(d));
        }
        return null;
    }
};

fn dummyExec(_: CommandContext) !void {}

test "context: typed getArg" {
    const allocator = std.testing.allocator;
    var cmd = try command.Command.init(allocator, .{ .name = "test", .description = "", .exec = dummyExec });
    defer cmd.deinit();

    try cmd.addPositional(.{ .name = "req_str", .is_required = true });
    try cmd.addPositional(.{ .name = "opt_int", .type = .Int, .default_value = .{ .Int = 123 } });

    try cmd.parsed_positionals.append("hello");

    const ctx = CommandContext{
        .allocator = allocator,
        .command = &cmd,
        .data = null,
    };

    try std.testing.expectEqualStrings("hello", try ctx.getArg("req_str", []const u8));
    try std.testing.expectEqual(123, try ctx.getArg("opt_int", i64));
}

test "context: getFlag" {
    const allocator = std.testing.allocator;
    var cmd = try command.Command.init(allocator, .{
        .name = "test",
        .description = "",
        .exec = dummyExec,
    });
    defer cmd.deinit();

    try cmd.addFlag(.{ .name = "verbose", .type = .Bool, .default_value = .{ .Bool = false }, .description = "" });
    try cmd.addFlag(.{ .name = "count", .type = .Int, .default_value = .{ .Int = 42 }, .description = "" });

    try cmd.parsed_flags.append(.{ .name = "verbose", .value = .{ .Bool = true } });

    const ctx = CommandContext{
        .allocator = allocator,
        .command = &cmd,
        .data = null,
    };

    try std.testing.expect(try ctx.getFlag("verbose", bool));
    try std.testing.expectEqual(42, try ctx.getFlag("count", i32));
}
