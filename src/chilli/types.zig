//! This module defines the core data structures used throughout the Chilli framework.
const std = @import("std");
const context = @import("context.zig");
const utils = @import("utils.zig");
const errors = @import("errors.zig");

/// Enumerates the supported data types for a `Flag`.
pub const FlagType = enum {
    Bool,
    Int,
    String,
};

/// A tagged union that holds the value of a parsed flag.
pub const FlagValue = union(FlagType) {
    Bool: bool,
    Int: i64,
    String: []const u8,
};

/// Defines the configuration for a `Command`.
pub const CommandOptions = struct {
    /// The primary name of the command, used to invoke it.
    name: []const u8,
    /// A short description of the command's purpose, shown in help messages.
    description: []const u8,
    /// The function to execute when this command is run.
    exec: *const fn (ctx: context.CommandContext) anyerror!void,
    /// An optional list of alternative names for the command.
    aliases: ?[]const []const u8 = null,
    /// An optional single-character shortcut for the command.
    shortcut: ?[]const u8 = null,
    /// An optional version string for the command, displayed in its help message.
    version: ?[]const u8 = null,
    /// The name of the section under which this command should be grouped in a parent's help message.
    section: []const u8 = "Commands",
};

/// Defines a command-line flag (e.g., `--verbose` or `-v`).
pub const Flag = struct {
    /// The full name of the flag (e.g., "verbose").
    name: []const u8,
    /// A short description of the flag's purpose, shown in help messages.
    description: []const u8,
    /// An optional single-character shortcut for the flag (e.g., "v").
    shortcut: ?[]const u8 = null,
    /// The data type of the flag's value.
    type: FlagType,
    /// The default value for the flag if it's not provided by the user.
    default_value: FlagValue,
    /// If `true`, the flag will not be shown in help messages.
    hidden: bool = false,

    /// Parses a raw string value into the appropriate `FlagValue` type for this flag.
    /// Returns `errors.Error` if the string cannot be parsed into the flag's target type.
    pub fn evaluateValueType(self: *const Flag, value: []const u8) errors.Error!FlagValue {
        return switch (self.type) {
            .Bool => FlagValue{ .Bool = try utils.parseBool(value) },
            .Int => FlagValue{ .Int = try std.fmt.parseInt(i64, value, 10) },
            .String => FlagValue{ .String = value },
        };
    }
};

/// Defines a positional argument for a command.
pub const PositionalArg = struct {
    /// The name of the argument, used in help messages (e.g., "filename").
    name: []const u8,
    /// A short description of the argument's purpose.
    description: []const u8,
    /// If `true`, the argument must be provided by the user.
    is_required: bool = false,
};

test "types: Flag.evaluateValueType" {
    const bool_flag = Flag{ .name = "b", .type = .Bool, .default_value = .{.Bool=false}, .description = "" };
    const int_flag = Flag{ .name = "i", .type = .Int, .default_value = .{.Int=0}, .description = "" };
    const string_flag = Flag{ .name = "s", .type = .String, .default_value = .{.String=""}, .description = "" };

    // Bool
    try std.testing.expect((try bool_flag.evaluateValueType("true")).Bool);
    try std.testing.expect(!(try bool_flag.evaluateValueType("false")).Bool);
    try std.testing.expectError(errors.Error.InvalidBoolString, bool_flag.evaluateValueType("notabool"));

    // Int
    try std.testing.expectEqual(123, (try int_flag.evaluateValueType("123")).Int);
    try std.testing.expectError(error.InvalidCharacter, int_flag.evaluateValueType("notanint"));

    // String
    try std.testing.expectEqualStrings("hello", (try string_flag.evaluateValueType("hello")).String);
}
