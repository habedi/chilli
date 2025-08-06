const std = @import("std");
const chilli = @import("chilli");
const Command = chilli.Command;
const CommandOptions = chilli.CommandOptions;
const CommandContext = chilli.CommandContext;
const PositionalArg = chilli.PositionalArg;

fn addExec(ctx: CommandContext) !void {
    const a = try ctx.getArg("a", f64);
    const b = try ctx.getArg("b", f64);
    const result = a + b;
    std.debug.print("{d} + {d} = {d}\n", .{ a, b, result });
}

fn subtractExec(ctx: CommandContext) !void {
    const a = try ctx.getArg("a", f64);
    const b = try ctx.getArg("b", f64);
    const result = a - b;
    std.debug.print("{d} - {d} = {d}\n", .{ a, b, result });
}

fn multiplyExec(ctx: CommandContext) !void {
    const a = try ctx.getArg("a", f64);
    const b = try ctx.getArg("b", f64);
    const result = a * b;
    std.debug.print("{d} * {d} = {d}\n", .{ a, b, result });
}

fn calculatorRootExec(_: CommandContext) !void {
    std.debug.print("Please provide a subcommand (add, subtract, multiply) or use --help.\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var root_cmd = try Command.init(allocator, CommandOptions{
        .name = "calculator",
        .description = "A simple CLI calculator.",
        .exec = calculatorRootExec,
    });
    defer root_cmd.deinit();

    var add_cmd = try Command.init(allocator, CommandOptions{
        .name = "add",
        .description = "Adds two numbers.",
        .exec = addExec,
    });
    try add_cmd.addPositional(PositionalArg{ .name = "a", .description = "First number", .is_required = true, .type = .Float });
    try add_cmd.addPositional(PositionalArg{ .name = "b", .description = "Second number", .is_required = true, .type = .Float });

    var subtract_cmd = try Command.init(allocator, CommandOptions{
        .name = "subtract",
        .description = "Subtracts two numbers.",
        .exec = subtractExec,
    });
    try subtract_cmd.addPositional(PositionalArg{ .name = "a", .description = "First number", .is_required = true, .type = .Float });
    try subtract_cmd.addPositional(PositionalArg{ .name = "b", .description = "Second number", .is_required = true, .type = .Float });

    var multiply_cmd = try Command.init(allocator, CommandOptions{
        .name = "multiply",
        .description = "Multiplies two numbers.",
        .exec = multiplyExec,
    });
    try multiply_cmd.addPositional(PositionalArg{ .name = "a", .description = "First number", .is_required = true, .type = .Float });
    try multiply_cmd.addPositional(PositionalArg{ .name = "b", .description = "Second number", .is_required = true, .type = .Float });

    try root_cmd.addSubcommand(add_cmd);
    try root_cmd.addSubcommand(subtract_cmd);
    try root_cmd.addSubcommand(multiply_cmd);

    try root_cmd.run(null);
}
