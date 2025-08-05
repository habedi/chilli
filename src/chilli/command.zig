//! The core module for defining, managing, and executing commands.
const std = @import("std");
const parser = @import("parser.zig");
const context = @import("context.zig");
const utils = @import("utils.zig");
const types = @import("types.zig");
const errors = @import("errors.zig");

/// Represents a single command in a CLI application.
///
/// A `Command` can have its own flags, positional arguments, and an execution function.
/// It can also contain subcommands, forming a nested command structure. Commands are
/// responsible for their own memory management; `deinit` must be called on the root
/// command to free all associated resources, including those of its subcommands.
pub const Command = struct {
    options: types.CommandOptions,
    subcommands: std.ArrayList(*Command),
    flags: std.ArrayList(types.Flag),
    positional_args: std.ArrayList(types.PositionalArg),
    parent: ?*Command,
    allocator: std.mem.Allocator,
    parsed_flags: std.ArrayList(parser.ParsedFlag),
    parsed_positionals: std.ArrayList([]const u8),

    /// Initializes a new command.
    /// Panics if the provided command name is empty.
    pub fn init(allocator: std.mem.Allocator, options: types.CommandOptions) !*Command {
        if (options.name.len == 0) {
            std.debug.panic("Command name cannot be empty.", .{});
        }

        const command = try allocator.create(Command);
        command.* = Command{
            .options = options,
            .subcommands = std.ArrayList(*Command).init(allocator),
            .flags = std.ArrayList(types.Flag).init(allocator),
            .positional_args = std.ArrayList(types.PositionalArg).init(allocator),
            .parent = null,
            .allocator = allocator,
            .parsed_flags = std.ArrayList(parser.ParsedFlag).init(allocator),
            .parsed_positionals = std.ArrayList([]const u8).init(allocator),
        };

        const help_flag = types.Flag{
            .name = "help",
            .shortcut = 'h',
            .description = "Shows help information for this command",
            .type = .Bool,
            .default_value = .{ .Bool = false },
        };
        try command.addFlag(help_flag);

        return command;
    }

    /// Deinitializes the command and all its subcommands recursively.
    pub fn deinit(self: *Command) void {
        for (self.subcommands.items) |sub| {
            sub.deinit();
        }
        self.subcommands.deinit();
        self.flags.deinit();
        self.positional_args.deinit();
        self.parsed_flags.deinit();
        self.parsed_positionals.deinit();
        self.allocator.destroy(self);
    }

    /// Adds a subcommand to this command.
    /// Returns `error.CommandAlreadyHasParent` if the subcommand has already been
    /// added to another command, to prevent double-frees during deinitialization.
    pub fn addSubcommand(self: *Command, sub: *Command) !void {
        if (sub.parent != null) {
            return errors.Error.CommandAlreadyHasParent;
        }
        sub.parent = self;
        try self.subcommands.append(sub);
    }

    /// Adds a flag to the command. Panics if the flag name is empty.
    pub fn addFlag(self: *Command, flag: types.Flag) !void {
        if (flag.name.len == 0) {
            std.debug.panic("Flag name cannot be empty.", .{});
        }
        try self.flags.append(flag);
    }

    /// Adds a positional argument to the command's definition.
    /// Returns `error.VariadicArgumentNotLastError` if you attempt to add an
    /// argument after one that is marked as variadic.
    /// Panics if the argument name is empty or an optional arg lacks a default value.
    pub fn addPositional(self: *Command, arg: types.PositionalArg) !void {
        if (arg.name.len == 0) {
            std.debug.panic("Positional argument name cannot be empty.", .{});
        }
        if (!arg.is_required and !arg.variadic and arg.default_value == null) {
            std.debug.panic("Optional positional argument '{s}' must have a default_value.", .{arg.name});
        }
        if (self.positional_args.items.len > 0) {
            const last_arg = self.positional_args.items[self.positional_args.items.len - 1];
            if (last_arg.variadic) {
                return errors.Error.VariadicArgumentNotLastError;
            }
        }
        try self.positional_args.append(arg);
    }

    /// Parses arguments and executes the appropriate command. This is the core logic loop.
    pub fn execute(self: *Command, user_args: []const []const u8, data: ?*anyopaque) anyerror!void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        var arg_iterator = parser.ArgIterator.init(user_args);

        var current_cmd: *Command = self;
        while (arg_iterator.peek()) |arg| {
            if (std.mem.startsWith(u8, arg, "-")) break;
            if (current_cmd.findSubcommand(arg)) |found_sub| {
                current_cmd = found_sub;
                arg_iterator.next();
            } else {
                break;
            }
        }

        try parser.parseArgsAndFlags(current_cmd, &arg_iterator);
        try parser.validateArgs(current_cmd);

        if (current_cmd.getFlagValue("help")) |flag_val| {
            if (flag_val.Bool) {
                try current_cmd.printHelp();
                return;
            }
        }

        if (self.options.version != null) {
            if (current_cmd.getFlagValue("version")) |flag_val| {
                if (flag_val.Bool) {
                    const stdout = std.io.getStdOut().writer();
                    try stdout.print("{s}\n", .{self.options.version.?});
                    return;
                }
            }
        }

        const ctx = context.CommandContext{
            .allocator = arena_allocator,
            .command = current_cmd,
            .data = data,
        };

        try current_cmd.options.exec(ctx);
    }

    /// The main entry point for running the CLI application.
    /// This function handles process arguments, invokes `execute`, and prints formatted errors.
    pub fn run(self: *Command, data: ?*anyopaque) !void {
        if (self.options.version != null) {
            try self.addFlag(.{
                .name = "version",
                .description = "Print version information and exit",
                .type = .Bool,
                .default_value = .{ .Bool = false },
            });
        }

        var args = try std.process.argsAlloc(self.allocator);
        defer std.process.argsFree(self.allocator, args);

        self.execute(args[1..], data) catch |err| {
            const stderr = std.io.getStdErr().writer();
            const red = utils.styles.RED;
            const reset = utils.styles.RESET;

            switch (err) {
                errors.Error.UnknownFlag => try stderr.print("{s}Error: Unknown flag provided.{s}\n", .{ red, reset }),
                errors.Error.MissingFlagValue => try stderr.print("{s}Error: Flag requires a value but none was provided.{s}\n", .{ red, reset }),
                errors.Error.InvalidFlagGrouping => try stderr.print("{s}Error: Invalid short flag grouping.{s}\n", .{ red, reset }),
                errors.Error.MissingRequiredArgument => try stderr.print("{s}Error: Missing a required argument.{s}\n", .{ red, reset }),
                errors.Error.TooManyArguments => try stderr.print("{s}Error: Too many arguments provided.{s}\n", .{ red, reset }),
                errors.Error.InvalidBoolString => try stderr.print("{s}Error: Invalid value for boolean flag, expected 'true' or 'false'.{s}\n", .{ red, reset }),
                errors.Error.VariadicArgumentNotLastError => try stderr.print("{s}Internal Error: Cannot add another positional argument after a variadic one.{s}\n", .{ red, reset }),
                errors.Error.CommandAlreadyHasParent => try stderr.print("{s}Internal Error: A command was added to multiple parents.{s}\n", .{ red, reset }),
                errors.Error.IntegerValueOutOfRange => try stderr.print("{s}Error: An integer flag value was provided out of the allowed range.{s}\n", .{ red, reset }),
                error.InvalidCharacter => try stderr.print("{s}Error: Invalid character in integer value.{s}\n", .{ red, reset }),
                error.Overflow => try stderr.print("{s}Error: Integer value is too large or too small.{s}\n", .{ red, reset }),
                error.OutOfMemory => try stderr.print("{s}Error: Out of memory.{s}\n", .{ red, reset }),
                else => return err,
            }
            std.process.exit(1);
        };
    }

    /// Finds a direct subcommand by its name, alias, or shortcut.
    pub fn findSubcommand(self: *Command, name: []const u8) ?*Command {
        for (self.subcommands.items) |sub| {
            if (std.mem.eql(u8, sub.options.name, name)) return sub;
            if (sub.options.shortcut) |s| {
                if (name.len == 1 and s == name[0]) return sub;
            }
            if (sub.options.aliases) |a| {
                for (a) |alias| {
                    if (std.mem.eql(u8, alias, name)) return sub;
                }
            }
        }
        return null;
    }

    /// Finds a flag definition by its full name (e.g., "verbose"), searching upwards through parent commands.
    pub fn findFlag(self: *Command, name: []const u8) ?*types.Flag {
        var current: ?*Command = self;
        while (current) |cmd| {
            for (cmd.flags.items) |*flag| {
                if (std.mem.eql(u8, flag.name, name)) return flag;
            }
            current = cmd.parent;
        }
        return null;
    }

    /// Finds a flag definition by its shortcut (e.g., 'v'), searching upwards through parent commands.
    pub fn findFlagByShortcut(self: *Command, shortcut: u8) ?*types.Flag {
        var current: ?*Command = self;
        while (current) |cmd| {
            for (cmd.flags.items) |*flag| {
                if (flag.shortcut) |s| {
                    if (s == shortcut) return flag;
                }
            }
            current = cmd.parent;
        }
        return null;
    }

    /// (Internal) Retrieves the parsed value of a flag for the current command.
    pub fn getFlagValue(self: *const Command, name: []const u8) ?types.FlagValue {
        for (self.parsed_flags.items) |flag| {
            if (std.mem.eql(u8, flag.name, name)) return flag.value;
        }
        return null;
    }

    /// (Internal) Retrieves the parsed value of a positional argument by its index.
    pub fn getPositionalValue(self: *const Command, index: usize) ?[]const u8 {
        if (index < self.parsed_positionals.items.len) return self.parsed_positionals.items[index];
        return null;
    }

    /// Prints a formatted help message for the command to standard output.
    pub fn printHelp(self: *const Command) !void {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("{s}{s}{s}\n", .{ utils.styles.BOLD, self.options.description, utils.styles.RESET });

        if (self.options.version) |version| {
            try stdout.print("{s}Version: {s}{s}\n", .{ utils.styles.DIM, version, utils.styles.RESET });
        }
        try stdout.print("\n", .{});

        try stdout.print("{s}Usage:{s}\n", .{ utils.styles.BOLD, utils.styles.RESET });
        try utils.printUsageLine(self, stdout);

        if (self.positional_args.items.len > 0) {
            try stdout.print("{s}Arguments:{s}\n", .{ utils.styles.BOLD, utils.styles.RESET });
            try utils.printAlignedPositionalArgs(self, stdout);
            try stdout.print("\n", .{});
        }

        if (self.flags.items.len > 0) {
            try stdout.print("{s}Flags:{s}\n", .{ utils.styles.BOLD, utils.styles.RESET });
            try utils.printAlignedFlags(self, stdout);
            try stdout.print("\n", .{});
        }

        if (self.subcommands.items.len > 0) {
            try utils.printSubcommands(self, stdout);
        }
    }
};

fn dummyExec(_: context.CommandContext) !void {}

test "command: addPositional validation" {
    const allocator = std.testing.allocator;
    var cmd = try Command.init(allocator, .{ .name = "test", .description = "", .exec = dummyExec });
    defer cmd.deinit();

    try cmd.addPositional(.{ .name = "a", .is_required = true });
    try cmd.addPositional(.{ .name = "b", .variadic = true });

    try std.testing.expectError(
        error.VariadicArgumentNotLastError,
        cmd.addPositional(.{ .name = "c", .is_required = true }),
    );
}

test "command: init and deinit" {
    const allocator = std.testing.allocator;
    var cmd = try Command.init(allocator, .{
        .name = "test",
        .description = "",
        .exec = dummyExec,
    });
    defer cmd.deinit();
    try std.testing.expectEqualStrings("test", cmd.options.name);
    try std.testing.expect(cmd.findFlag("help") != null);
}

test "command: subcommands" {
    const allocator = std.testing.allocator;
    var root = try Command.init(allocator, .{ .name = "root", .description = "", .exec = dummyExec });
    defer root.deinit();
    const sub = try Command.init(allocator, .{ .name = "sub", .description = "", .exec = dummyExec });

    try root.addSubcommand(sub);
    try std.testing.expect(root.findSubcommand("sub").? == sub);
    try std.testing.expect(sub.parent.? == root);
}

test "command: findFlag traverses parents" {
    const allocator = std.testing.allocator;
    var root = try Command.init(allocator, .{ .name = "root", .description = "", .exec = dummyExec });
    defer root.deinit();
    var sub = try Command.init(allocator, .{ .name = "sub", .description = "", .exec = dummyExec });
    try root.addSubcommand(sub);

    try root.addFlag(.{ .name = "global", .shortcut = 'g', .type = .Bool, .default_value = .{ .Bool = false }, .description = "" });

    try std.testing.expect(sub.findFlag("global") != null);
    try std.testing.expect(sub.findFlagByShortcut('g') != null);
}

var exec_called_on: ?[]const u8 = null;
fn trackingExec(ctx: context.CommandContext) !void {
    exec_called_on = ctx.command.options.name;
}

test "command: execute" {
    const allocator = std.testing.allocator;
    var root = try Command.init(allocator, .{ .name = "root", .description = "", .exec = trackingExec });
    defer root.deinit();
    const sub = try Command.init(allocator, .{ .name = "sub", .description = "", .exec = trackingExec });
    try root.addSubcommand(sub);

    exec_called_on = null;
    try root.execute(&[_][]const u8{}, null);
    try std.testing.expectEqualStrings("root", exec_called_on.?);

    exec_called_on = null;
    try root.execute(&[_][]const u8{"sub"}, null);
    try std.testing.expectEqualStrings("sub", exec_called_on.?);
}
