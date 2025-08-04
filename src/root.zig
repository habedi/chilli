const std = @import("std");

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn greet(name: []const u8) void {
    std.debug.print("Hello, {s}!\n", .{name});
}

test "basic addition" {
    const result = add(2, 3);
    try std.testing.expectEqual(@as(i32, 5), result);
}

test "addition with negative numbers" {
    try std.testing.expectEqual(@as(i32, -1), add(2, -3));
    try std.testing.expectEqual(@as(i32, -5), add(-2, -3));
}
