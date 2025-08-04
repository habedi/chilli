const std = @import("std");
const root = @import("root.zig");

pub fn main() !void {
    const result = root.add(10, 5);
    std.debug.print("Result of add(10, 5) is: {}\n", .{result});

    root.greet("World");

    const args = std.process.argsAlloc(std.heap.page_allocator) catch |err| {
        std.debug.print("Failed to allocate memory for args: {}\n", .{err});
        return err;
    };
    defer std.process.argsFree(std.heap.page_allocator, args);

    std.debug.print("\nCommand line arguments:\n", .{});
    for (args) |arg| {
        std.debug.print("  Arg: {s}\n", .{arg});
    }

    if (args.len < 2) {
        std.debug.print(
            "\nTry running with arguments: ./zig-out/bin/$(BINARY_NAME) arg1 arg2\n",
            .{},
        );
    }
}
