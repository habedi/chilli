const std = @import("std");
const testing = std.testing;
const template_zig_project = @import("template_zig_project");

test "addition function from external test" {
    const expected: i32 = 100;
    const actual = template_zig_project.add(75, 25);
    try testing.expectEqual(expected, actual);
}

test "greet function test" {
    template_zig_project.greet("Test Runner");
    try testing.expect(true);
}
