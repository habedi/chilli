//! Provides the execution context for a command, giving access to parsed arguments and flags.
const std = @import("std");
const types = @import("types.zig");
const command = @import("command.zig");
const errors = @import("errors.zig");

/// (Private) Describes the source of a value for error reporting.
const ValueSource = enum {
    parsed,
    environment,
    default,
};

/// (Private) Casts a FlagValue to a specific type T at compile time.
/// Panics on type mismatch, which indicates a developer error.
fn castFlagValueTo(
    value: types.FlagValue,
    comptime T: type,
    comptime entity_kind: []const u8,
    entity_name: []const u8,
    source: ValueSource,
) errors.Error!T {
    const panic_msg = "Type mismatch for {s} ''{s}'' from {s} value: expected " ++ @typeName(T) ++ ", got {s}";
    const source_str = @tagName(source);

    return switch (T) {
        bool => if (value == .Bool) value.Bool else std.debug.panic(panic_msg, .{ entity_kind, entity_name, source_str, @tagName(value) }),
        []const u8 => if (value == .String) value.String else std.debug.panic(panic_msg, .{ entity_kind, entity_name, source_str, @tagName(value) }),
        else => switch (@typeInfo(T)) {
            .int => {
                if (value == .Int) {
                    if (std.math.cast(T, value.Int)) |casted_value| {
                        return casted_value;
                    } else {
                        return errors.Error.IntegerValueOutOfRange;
                    }
                }
                std.debug.panic(panic_msg, .{ entity_kind, entity_name, source_str, @tagName(value) });
            },
            .float => {
                if (value == .Float) {
                    const float_val = value.Float;
                    if (@abs(float_val) > std.math.floatMax(T)) {
                        return errors.Error.FloatValueOutOfRange;
                    }
                    return @as(T, @floatCast(float_val));
                }
                std.debug.panic(panic_msg, .{ entity_kind, entity_name, source_str, @tagName(value) });
            },
            else => @compileError("Unsupported type for getFlag/getArg: " ++ @typeName(T)),
        },
    };
}

/// Provides access to command-line data within a command's execution function (`exec`).
pub const CommandContext = struct {
    allocator: std.mem.Allocator,
    command: *command.Command,
    data: ?*anyopaque,

    /// Retrieves the value for a flag, searching parsed values, then environment
    /// variables, and finally falling back to the default value.
    pub fn getFlag(self: *const CommandContext, name: []const u8, comptime T: type) errors.Error!T {
        // 1. Check for a parsed value from the command line.
        if (self.command.getFlagValue(name)) |parsed_value| {
            return castFlagValueTo(parsed_value, T, "flag", name, .parsed);
        }

        // 2. Find the flag definition.
        const flag_def = self.command.findFlag(name) orelse
            std.debug.panic("Attempted to access an undefined flag: '{s}'", .{name});

        // 3. Check for a value from an environment variable.
        if (flag_def.env_var) |env_name| {
            if (std.process.getEnvVarOwned(self.allocator, env_name) catch null) |env_val_str| {
                defer self.allocator.free(env_val_str);
                const env_value = try types.parseValue(flag_def.type, env_val_str);
                return castFlagValueTo(env_value, T, "flag", name, .environment);
            }
        }

        // 4. Fall back to the default value.
        return castFlagValueTo(flag_def.default_value, T, "flag", name, .default);
    }

    /// Retrieves the value for a positional argument, searching parsed values
    /// and then falling back to the default value if available.
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

        const found_arg = arg_def orelse
            std.debug.panic("Attempted to access an undefined positional argument: '{s}'", .{name});

        if (found_arg.variadic) {
            std.debug.panic("Positional argument '{s}' is variadic. Use getArgs() instead.", .{name});
        }

        // 1. Check for a parsed value from the command line.
        if (arg_idx.? < self.command.parsed_positionals.items.len) {
            const raw_value = self.command.parsed_positionals.items[arg_idx.?];
            const parsed_value = try types.parseValue(found_arg.type, raw_value);
            return castFlagValueTo(parsed_value, T, "argument", name, .parsed);
        }

        // 2. Fall back to the default value.
        if (found_arg.default_value) |default_val| {
            return castFlagValueTo(default_val, T, "argument", name, .default);
        }

        // This path should ideally not be reached if validation is correct.
        // A required argument without a parsed value would fail validation earlier.
        // An optional argument must have a default value (enforced in `addPositional`).
        std.debug.panic("No value or default value found for argument '{s}'", .{name});
    }

    /// Retrieves all values for a variadic positional argument.
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

    /// Retrieves a pointer to the shared application context data.
    pub fn getContextData(self: *const CommandContext, comptime T: type) ?*T {
        if (self.data) |d| {
            return @alignCast(@ptrCast(d));
        }
        return null;
    }
};

// Tests for the `context` module

const testing = std.testing;
const process = std.process;

fn dummyExec(_: CommandContext) !void {}

test "context: getFlag from environment variable" {
    const allocator = testing.allocator;
    var cmd = try command.Command.init(allocator, .{ .name = "test", .description = "", .exec = dummyExec });
    defer cmd.deinit();

    try cmd.addFlag(.{
        .name = "config",
        .type = .String,
        .default_value = .{ .String = "default.conf" },
        .env_var = "TEST_APP_CONFIG",
        .description = "",
    });

    const ctx = CommandContext{ .allocator = allocator, .command = &cmd, .data = null };

    // Set env var and check if getFlag reads it
    try process.setEnvVar("TEST_APP_CONFIG", "env.conf");
    defer process.unsetEnvVar("TEST_APP_CONFIG") catch {};

    const config_path = try ctx.getFlag("config", []const u8);
    try testing.expectEqualStrings("env.conf", config_path);
}

test "context: getFlag integer range error" {
    const allocator = testing.allocator;
    var cmd = try command.Command.init(allocator, .{ .name = "test", .description = "", .exec = dummyExec });
    defer cmd.deinit();
    try cmd.addFlag(.{ .name = "count", .type = .Int, .default_value = .{ .Int = 0 }, .description = "" });

    // Parsed value is 70000, which does not fit in i16
    try cmd.parsed_flags.append(.{ .name = "count", .value = .{ .Int = 70000 } });

    const ctx = CommandContext{ .allocator = allocator, .command = &cmd, .data = null };
    try testing.expectError(errors.Error.IntegerValueOutOfRange, ctx.getFlag("count", i16));
}

test "context: getArgs for variadic" {
    const allocator = testing.allocator;
    var cmd = try command.Command.init(allocator, .{ .name = "test", .description = "", .exec = dummyExec });
    defer cmd.deinit();
    try cmd.addPositional(.{ .name = "command", .is_required = true, .description = "" });
    try cmd.addPositional(.{ .name = "files", .variadic = true, .description = "" });

    try cmd.parsed_positionals.appendSlice(&[_][]const u8{ "run", "file1.zig", "file2.zig" });

    const ctx = CommandContext{ .allocator = allocator, .command = &cmd, .data = null };
    const files = ctx.getArgs("files");

    try testing.expectEqual(@as(usize, 2), files.len);
    try testing.expectEqualStrings("file1.zig", files[0]);
    try testing.expectEqualStrings("file2.zig", files[1]);
}

test "context: typed getArg" {
    const allocator = std.testing.allocator;
    var cmd = try command.Command.init(allocator, .{ .name = "test", .description = "", .exec = dummyExec });
    defer cmd.deinit();
    try cmd.addPositional(.{ .name = "req_str", .is_required = true, .description = "" });
    try cmd.addPositional(.{ .name = "opt_int", .description = "", .type = .Int, .default_value = .{ .Int = 123 } });
    try cmd.parsed_positionals.append("hello");
    const ctx = CommandContext{
        .allocator = allocator,
        .command = &cmd,
        .data = null,
    };
    try std.testing.expectEqualStrings("hello", try ctx.getArg("req_str", []const u8));
    try std.testing.expectEqual(@as(i64, 123), try ctx.getArg("opt_int", i64));
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
    try cmd.addFlag(.{ .name = "pi", .type = .Float, .default_value = .{ .Float = 3.14 }, .description = "" });
    try cmd.parsed_flags.append(.{ .name = "verbose", .value = .{ .Bool = true } });
    const ctx = CommandContext{
        .allocator = allocator,
        .command = &cmd,
        .data = null,
    };
    try std.testing.expect(try ctx.getFlag("verbose", bool));
    try std.testing.expectEqual(@as(i32, 42), try ctx.getFlag("count", i32));
    try std.testing.expectEqual(@as(f64, 3.14), try ctx.getFlag("pi", f64));
}
