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
    ///
    /// A default `--help, -h` flag is automatically added to every command.
    ///
    /// - `allocator`: The allocator to use for the command and its children.
    /// - `options`: A `CommandOptions` struct defining the command's behavior and metadata.
    ///
    /// Returns an error if memory allocation fails.
    pub fn init(allocator: std.mem.Allocator, options: types.CommandOptions) !*Command {
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
            .shortcut = "h",
            .description = "Shows help information for this command",
            .type = .Bool,
            .default_value = .{ .Bool = false },
        };
        try command.addFlag(help_flag);

        return command;
    }

    /// Deinitializes the command and all its subcommands recursively.
    ///
    /// This function should only be called on the root command. It frees all memory
    /// allocated by the command, its flags, arguments, and all of its subcommands.
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
    ///
    /// The parent command takes ownership of the subcommand's memory. `deinit` should
    /// not be called on the subcommand directly; it will be deinitialized when the
    /// parent's `deinit` is called.
    ///
    /// - `sub`: A pointer to the command to be added as a subcommand.
    ///
    /// Returns an error if memory allocation for the subcommands list fails.
    pub fn addSubcommand(self: *Command, sub: *Command) !void {
        sub.parent = self;
        try self.subcommands.append(sub);
    }

    /// Adds a flag to the command.
    ///
    /// - `flag`: The `Flag` struct to add.
    ///
    /// Returns an error if memory allocation for the flags list fails.
    pub fn addFlag(self: *Command, flag: types.Flag) !void {
        try self.flags.append(flag);
    }

    /// Adds a positional argument to the command's definition.
    ///
    /// - `arg`: The `PositionalArg` struct to add.
    ///
    /// Returns an error if memory allocation for the arguments list fails.
    pub fn addPositional(self: *Command, arg: types.PositionalArg) !void {
        try self.positional_args.append(arg);
    }

    /// Parses arguments and executes the appropriate command.
    /// This is a lower-level function than `run`. It finds the correct subcommand to execute
    /// based on the input arguments, parses all flags and positional values, validates them,
    /// and then invokes the command's `exec` function.
    ///
    /// - `user_args`: A slice of strings representing the command-line arguments (excluding the program name).
    /// - `data`: An optional `anyopaque` pointer to user-defined context data.
    ///
    /// Returns `chilli.Error` on parsing or validation failure, or any error from an `exec` function.
    pub fn execute(self: *Command, user_args: []const []const u8, data: ?*anyopaque) anyerror!void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        var arg_iterator = parser.ArgIterator.init(user_args);

        var current_cmd: *Command = self;
        while (arg_iterator.peek()) |arg| {
            if (std.mem.startsWith(u8, arg, "-")) {
                break;
            }
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

        if (current_cmd.getFlagValue("version")) |flag_val| {
            if (flag_val.Bool) {
                if (self.options.version) |v| {
                    const stdout = std.io.getStdOut().writer();
                    try stdout.print("{s}\n", .{v});
                }
                return;
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
    ///
    /// This function automatically allocates and retrieves command-line arguments from the
    /// process, then calls `execute`. It provides friendly, colored error messages for common
    /// parsing and validation errors and exits the process with a non-zero status code.
    ///
    /// - `data`: An optional `anyopaque` pointer to user-defined context data.
    ///
    /// Propagates any unhandled errors from `execute` or the `exec` function.
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
                error.InvalidCharacter => try stderr.print("{s}Error: Invalid character in integer value.{s}\n", .{ red, reset }),
                error.Overflow => try stderr.print("{s}Error: Integer value is too large or too small.{s}\n", .{ red, reset }),
                error.OutOfMemory => try stderr.print("{s}Error: Out of memory.{s}\n", .{ red, reset }),
                else => {
                    return err;
                },
            }
            std.process.exit(1);
        };
    }

    /// Finds a direct subcommand by its name, alias, or shortcut.
    ///
    /// - `name`: The string identifier for the subcommand.
    ///
    /// Returns a pointer to the `Command` if found, otherwise `null`.
    pub fn findSubcommand(self: *Command, name: []const u8) ?*Command {
        for (self.subcommands.items) |sub| {
            if (std.mem.eql(u8, sub.options.name, name)) return sub;
            if (sub.options.shortcut) |s| {
                if (std.mem.eql(u8, s, name)) return sub;
            }
            if (sub.options.aliases) |a| {
                for (a) |alias| {
                    if (std.mem.eql(u8, alias, name)) return sub;
                }
            }
        }
        return null;
    }

    /// Finds a flag definition by its name or shortcut, searching upwards through parent commands.
    ///
    /// This allows flags defined on a parent command (e.g., a global `--verbose` flag on the root)
    /// to be accessible from any subcommand.
    ///
    /// - `name_or_shortcut`: The name (e.g., "verbose") or shortcut (e.g., "v") of the flag.
    ///
    /// Returns a pointer to the `Flag` definition if found, otherwise `null`.
    pub fn findFlag(self: *Command, name_or_shortcut: []const u8) ?*types.Flag {
        var current: ?*Command = self;
        while (current) |cmd| {
            for (cmd.flags.items) |*flag| {
                if (std.mem.eql(u8, flag.name, name_or_shortcut)) return flag;
                if (flag.shortcut) |s| {
                    if (std.mem.eql(u8, s, name_or_shortcut)) return flag;
                }
            }
            current = cmd.parent;
        }
        return null;
    }

    /// Retrieves the parsed value of a flag for the current command. For internal use.
    pub fn getFlagValue(self: *const Command, name: []const u8) ?types.FlagValue {
        for (self.parsed_flags.items) |flag| {
            if (std.mem.eql(u8, flag.name, name)) return flag.value;
        }
        return null;
    }

    /// Retrieves the parsed value of a positional argument by its index. For internal use.
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
    var sub = try Command.init(allocator, .{ .name = "sub", .description = "", .exec = dummyExec });

    try root.addSubcommand(&sub);
    try std.testing.expectEqual(&sub, root.findSubcommand("sub"));
    try std.testing.expectEqual(root, sub.parent);
}

test "command: findFlag traverses parents" {
    const allocator = std.testing.allocator;
    var root = try Command.init(allocator, .{ .name = "root", .description = "", .exec = dummyExec });
    defer root.deinit();
    var sub = try Command.init(allocator, .{ .name = "sub", .description = "", .exec = dummyExec });
    try root.addSubcommand(&sub);

    try root.addFlag(.{ .name = "global", .type = .Bool, .default_value = .{ .Bool = false }, .description = "" });

    try std.testing.expect(sub.findFlag("global") != null);
}

var exec_called_on: ?[]const u8 = null;
fn trackingExec(ctx: context.CommandContext) !void {
    exec_called_on = ctx.command.options.name;
}

test "command: execute" {
    const allocator = std.testing.allocator;
    var root = try Command.init(allocator, .{ .name = "root", .description = "", .exec = trackingExec });
    defer root.deinit();
    var sub = try Command.init(allocator, .{ .name = "sub", .description = "", .exec = trackingExec });
    try root.addSubcommand(&sub);

    exec_called_on = null;
    try root.execute(&[_][]const u8{}, null);
    try std.testing.expectEqualStrings("root", exec_called_on.?);

    exec_called_on = null;
    try root.execute(&[_][]const u8{"sub"}, null);
    try std.testing.expectEqualStrings("sub", exec_called_on.?);
}
