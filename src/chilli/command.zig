const std = @import("std");
const parser = @import("parser.zig");
const context = @import("context.zig");
const utils = @import("utils.zig");
const types = @import("types.zig");

/// Represents a single command in a CLI application.
pub const Command = struct {
    options: types.CommandOptions,
    subcommands: std.ArrayList(*Command),
    flags: std.ArrayList(types.Flag),
    positional_args: std.ArrayList(types.PositionalArg),
    parent: ?*Command,
    allocator: std.mem.Allocator,
    parsed_flags: std.ArrayList(parser.ParsedFlag),
    parsed_positionals: std.ArrayList([]const u8),

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

    pub fn addSubcommand(self: *Command, sub: *Command) !void {
        sub.parent = self;
        try self.subcommands.append(sub);
    }

    pub fn addFlag(self: *Command, flag: types.Flag) !void {
        try self.flags.append(flag);
    }

    pub fn addPositional(self: *Command, arg: types.PositionalArg) !void {
        try self.positional_args.append(arg);
    }

    pub fn execute(self: *Command, user_args: []const []const u8, data: ?*anyopaque) anyerror!void {
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

        const ctx = context.CommandContext{
            .allocator = self.allocator,
            .command = current_cmd,
            .data = data,
        };

        try current_cmd.options.exec(ctx);
    }

    pub fn run(self: *Command, data: ?*anyopaque) !void {
        var args = try std.process.argsAlloc(self.allocator);
        defer std.process.argsFree(self.allocator, args);

        self.execute(args[1..], data) catch |err| {
            const stderr = std.io.getStdErr().writer();
            const red = utils.styles.RED;
            const reset = utils.styles.RESET;

            switch (err) {
                error.UnknownFlag => {
                    try stderr.print("{s}Error: Unknown flag provided.{s}\n", .{ red, reset });
                },
                error.MissingFlagValue => {
                    try stderr.print(
                        "{s}Error: Flag requires a value but none was provided.{s}\n",
                        .{ red, reset },
                    );
                },
                error.MissingRequiredArgument => {
                    try stderr.print(
                        "{s}Error: Missing a required argument.{s}\n",
                        .{ red, reset },
                    );
                },
                else => {
                    // This is not a parsing error we want to handle gracefully.
                    // It's likely a bug in the user's code or the library. Propagate it.
                    return err;
                },
            }
            // For handled parsing errors, exit gracefully with an error code.
            std.process.exit(1);
        };
    }

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

    pub fn getFlagValue(self: *const Command, name: []const u8) ?types.FlagValue {
        for (self.parsed_flags.items) |flag| {
            if (std.mem.eql(u8, flag.name, name)) return flag.value;
        }
        return null;
    }

    pub fn getPositionalValue(self: *const Command, index: usize) ?[]const u8 {
        if (index < self.parsed_positionals.items.len) return self.parsed_positionals.items[index];
        return null;
    }

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
