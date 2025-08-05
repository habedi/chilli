//! Provides the execution context for a command, giving access to parsed arguments and flags.
const std = @import("std");
const types = @import("types.zig");
const command = @import("command.zig");
const errors = @import("errors.zig");

/// (Private) Casts a FlagValue to a specific type T at compile time.
/// Panics on type mismatch, which indicates a developer error.
fn castFlagValueTo(
    value: types.FlagValue,
    comptime T: type,
    comptime entity_kind: []const u8,
    entity_name: []const u8,
    comptime source: []const u8,
) errors.Error!T {
    const panic_msg = "Type mismatch for {s} ''{s}'' from {s}: expected " ++ @typeName(T) ++ ", got {s}";
    return switch (T) {
        bool => if (value == .Bool) value.Bool else std.debug.panic(panic_msg, .{ entity_kind, entity_name, source, @tagName(value) }),
        []const u8 => if (value == .String) value.String else std.debug.panic(panic_msg, .{ entity_kind, entity_name, source, @tagName(value) }),
        else => switch (@typeInfo(T)) {
            .int => {
                if (value == .Int) {
                    if (std.math.cast(T, value.Int)) |casted_value| {
                        return casted_value;
                    } else {
                        return errors.Error.IntegerValueOutOfRange;
                    }
                }
                std.debug.panic(panic_msg, .{ entity_kind, entity_name, source, @tagName(value) });
            },
            .float => {
                if (value == .Float) {
                    const float_val = value.Float;
                    if (@abs(float_val) > std.math.floatMax(T)) {
                        return errors.Error.FloatValueOutOfRange;
                    }
                    return @as(T, @floatCast(float_val));
                }
                std.debug.panic(panic_msg, .{ entity_kind, entity_name, source, @tagName(value) });
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

    pub fn getFlag(self: *const CommandContext, name: []const u8, comptime T: type) errors.Error!T {
        if (self.command.getFlagValue(name)) |parsed_value| {
            return castFlagValueTo(parsed_value, T, "flag", name, "parsed value");
        }
        const flag_def = self.command.findFlag(name) orelse std.debug.panic("Attempted to access an undefined flag: '{s}'", .{name});
        if (flag_def.env_var) |env_name| {
            if (std.process.getEnvVarOwned(self.allocator, env_name) catch null) |env_val_str| {
                const env_value = try types.parseValue(flag_def.type, env_val_str);
                return castFlagValueTo(env_value, T, "flag", name, "env var");
            }
        }
        return castFlagValueTo(flag_def.default_value, T, "flag", name, "default value");
    }

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
        if (arg_idx.? < self.command.parsed_positionals.items.len) {
            const raw_value = self.command.parsed_positionals.items[arg_idx.?];
            const parsed_value = try types.parseValue(found_arg.type, raw_value);
            return castFlagValueTo(parsed_value, T, "argument", name, "parsed value");
        }
        if (found_arg.default_value) |default_val| {
            return castFlagValueTo(default_val, T, "argument", name, "default value");
        }
        std.debug.panic("No value or default value found for argument '{s}'", .{name});
    }

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
