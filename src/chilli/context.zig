//! Provides the execution context for a command, giving access to parsed arguments and flags.
const std = @import("std");
const types = @import("types.zig");
const command = @import("command.zig");

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
    ///
    /// This function is the primary way to access flag values. It resolves the value
    /// using the following precedence:
    /// 1. Value provided on the command line.
    /// 2. Value from the environment variable specified in the flag's `env_var` field (if any).
    /// 3. The flag's defined default value.
    ///
    /// - `name`: The comptime string name of the flag to retrieve.
    /// - `T`: The comptime type to retrieve the flag value as (e.g., `bool`, `i64`, `[]const u8`).
    ///
    /// Panics if the flag is not defined, or if the requested type `T` does not match the
    /// flag's actual type. Also panics if an environment variable provides a malformed value.
    pub fn getFlag(self: *const CommandContext, comptime name: []const u8, comptime T: type) T {
        if (self.command.getFlagValue(name)) |parsed_value| {
            return switch (T) {
                bool => if (parsed_value == .Bool) parsed_value.Bool else std.debug.panic("Type mismatch for flag '{s}': expected bool, but it was parsed as {s}", .{ name, @tagName(parsed_value) }),
                []const u8 => if (parsed_value == .String) parsed_value.String else std.debug.panic("Type mismatch for flag '{s}': expected string, but it was parsed as {s}", .{ name, @tagName(parsed_value) }),
                else => switch (@typeInfo(T)) {
                    .Int => if (parsed_value == .Int) @intCast(parsed_value.Int) else std.debug.panic("Type mismatch for flag '{s}': expected int, but it was parsed as {s}", .{ name, @tagName(parsed_value) }),
                    else => @compileError("Unsupported type for flag '" ++ name ++ "': " ++ @typeName(T)),
                },
            };
        }

        const flag_def = self.command.findFlag(name) orelse std.debug.panic("Attempted to access an undefined flag: '{s}'", .{name});

        if (flag_def.env_var) |env_name| {
            if (std.process.getEnvVarOwned(self.allocator, env_name) catch null) |env_val_str| {
                const env_value = flag_def.evaluateValueType(env_val_str) catch |err| {
                    std.debug.panic(
                        \\Error parsing environment variable "{s}" for flag "{s}": {s}
                    , .{ env_name, name, @errorName(err) });
                };

                return switch (T) {
                    bool => if (env_value == .Bool) env_value.Bool else std.debug.panic("Type mismatch for flag '{s}' from env '{s}': expected bool, got {s}", .{ name, env_name, @tagName(env_value) }),
                    []const u8 => if (env_value == .String) env_value.String else std.debug.panic("Type mismatch for flag '{s}' from env '{s}': expected string, got {s}", .{ name, env_name, @tagName(env_value) }),
                    else => switch (@typeInfo(T)) {
                        .Int => if (env_value == .Int) @intCast(env_value.Int) else std.debug.panic("Type mismatch for flag '{s}' from env '{s}': expected int, got {s}", .{ name, env_name, @tagName(env_value) }),
                        else => @compileError("Unsupported type for flag '" ++ name ++ "': " ++ @typeName(T)),
                    },
                };
            }
        }

        const default_val = flag_def.default_value;

        return switch (T) {
            bool => if (default_val == .Bool) default_val.Bool else std.debug.panic("Default type mismatch for flag '{s}': expected bool, got {s}", .{ name, @tagName(default_val) }),
            []const u8 => if (default_val == .String) default_val.String else std.debug.panic("Default type mismatch for flag '{s}': expected string, got {s}", .{ name, @tagName(default_val) }),
            else => switch (@typeInfo(T)) {
                .Int => if (default_val == .Int) @intCast(default_val.Int) else std.debug.panic("Default type mismatch for flag '{s}': expected int, got {s}", .{ name, @tagName(default_val) }),
                else => @compileError("Unsupported type for flag '" ++ name ++ "': " ++ @typeName(T)),
            },
        };
    }

    /// Retrieves the value of a positional argument by its zero-based index.
    ///
    /// - `index`: The zero-based index of the positional argument.
    ///
    /// Returns the argument's value as a string slice, or `null` if the argument was not provided.
    pub fn getPositional(self: *const CommandContext, index: usize) ?[]const u8 {
        return self.command.getPositionalValue(index);
    }

    /// Retrieves the shared, user-defined context data.
    ///
    /// This allows you to pass a custom struct containing application state (e.g., configuration,
    /// database connections) from the root of your application down to any command's `exec` function.
    ///
    /// - `T`: The comptime type of the context data struct to cast to.
    ///
    /// Returns a typed pointer to the context data, or `null` if no context data was provided to `run`.
    pub fn getContextData(self: *const CommandContext, comptime T: type) ?*T {
        if (self.data) |d| {
            return @alignCast(@ptrCast(d));
        }
        return null;
    }
};

fn dummyExec(_: CommandContext) !void {}

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

    try std.testing.expect(ctx.getFlag("verbose", bool));
    try std.testing.expectEqual(42, ctx.getFlag("count", i32));
}

test "context: getPositional" {
    const allocator = std.testing.allocator;
    var cmd = try command.Command.init(allocator, .{
        .name = "test",
        .description = "",
        .exec = dummyExec,
    });
    defer cmd.deinit();

    try cmd.parsed_positionals.append("hello");

    const ctx = CommandContext{
        .allocator = allocator,
        .command = &cmd,
        .data = null,
    };

    try std.testing.expectEqualStrings("hello", ctx.getPositional(0).?);
    try std.testing.expect(ctx.getPositional(1) == null);
}

test "context: getContextData" {
    const allocator = std.testing.allocator;
    var cmd = try command.Command.init(allocator, .{
        .name = "test",
        .description = "",
        .exec = dummyExec,
    });
    defer cmd.deinit();

    const MyContext = struct { value: i32 };
    var my_ctx_data = MyContext{ .value = 99 };

    const ctx = CommandContext{
        .allocator = allocator,
        .command = &cmd,
        .data = &my_ctx_data,
    };

    const retrieved_ctx = ctx.getContextData(MyContext).?;
    try std.testing.expectEqual(99, retrieved_ctx.value);
}
