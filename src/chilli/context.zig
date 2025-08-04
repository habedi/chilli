const std = @import("std");
const types = @import("types.zig");
const command = @import("command.zig");

/// Provides access to command-line data within a command's execution function.
pub const CommandContext = struct {
    allocator: std.mem.Allocator,
    command: *command.Command,
    data: ?*anyopaque,

    /// Retrieves the value of a flag by name with compile-time type checking.
    pub fn getFlag(self: *const CommandContext, comptime name: []const u8, comptime T: type) T {
        // First, check if the flag was provided by the user on the command line.
        if (self.command.getFlagValue(name)) |parsed_value| {
            return switch (T) {
                bool => if (parsed_value == .Bool) parsed_value.Bool else std.debug.panic("Type mismatch for flag '{s}': expected bool, but it was parsed as {s}", .{ name, @tagName(parsed_value) }),
                []const u8 => if (parsed_value == .String) parsed_value.String else std.debug.panic("Type mismatch for flag '{s}': expected string, but it was parsed as {s}", .{ name, @tagName(parsed_value) }),
                else => switch (@typeInfo(T)) {
                    .int => if (parsed_value == .Int) @intCast(parsed_value.Int) else std.debug.panic("Type mismatch for flag '{s}': expected int, but it was parsed as {s}", .{ name, @tagName(parsed_value) }),
                    else => @compileError("Unsupported type for flag '" ++ name ++ "': " ++ @typeName(T)),
                },
            };
        }

        // If not parsed, find the flag's definition to return its default value.
        // This is a programmer error if the flag is not defined at all.
        const flag_def = self.command.findFlag(name) orelse std.debug.panic("Attempted to access an undefined flag: '{s}'", .{name});
        const default_val = flag_def.default_value;

        return switch (T) {
            bool => if (default_val == .Bool) default_val.Bool else std.debug.panic("Default type mismatch for flag '{s}': expected bool, got {s}", .{ name, @tagName(default_val) }),
            []const u8 => if (default_val == .String) default_val.String else std.debug.panic("Default type mismatch for flag '{s}': expected string, got {s}", .{ name, @tagName(default_val) }),
            else => switch (@typeInfo(T)) {
                .int => if (default_val == .Int) @intCast(default_val.Int) else std.debug.panic("Default type mismatch for flag '{s}': expected int, got {s}", .{ name, @tagName(default_val) }),
                else => @compileError("Unsupported type for flag '" ++ name ++ "': " ++ @typeName(T)),
            },
        };
    }

    /// Retrieves the value of a positional argument by its zero-based index.
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
