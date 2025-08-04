const std = @import("std");
const context = @import("context.zig");
const utils = @import("utils.zig");

pub const FlagType = enum {
    Bool,
    Int,
    String,
};

pub const FlagValue = union(FlagType) {
    Bool: bool,
    Int: i64,
    String: []const u8,
};

/// Options for defining a command.
pub const CommandOptions = struct {
    name: []const u8,
    description: []const u8,
    exec: *const fn (ctx: context.CommandContext) anyerror!void,
    aliases: ?[]const []const u8 = null,
    shortcut: ?[]const u8 = null,
    version: ?[]const u8 = null,
    section: []const u8 = "Commands",
};

/// A flag, which is a named parameter like `--verbose` or `-v`.
pub const Flag = struct {
    name: []const u8,
    description: []const u8,
    shortcut: ?[]const u8 = null,
    type: FlagType,
    default_value: FlagValue,
    hidden: bool = false,

    pub fn evaluateValueType(self: *const Flag, value: []const u8) !FlagValue {
        return switch (self.type) {
            .Bool => FlagValue{ .Bool = try utils.parseBool(value) },
            .Int => FlagValue{ .Int = try std.fmt.parseInt(i64, value, 10) },
            .String => FlagValue{ .String = value },
        };
    }
};

/// A positional argument, which is a value specified by its order.
pub const PositionalArg = struct {
    name: []const u8,
    description: []const u8,
    is_required: bool = false,
};
