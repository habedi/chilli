const std = @import("std");
const chilli = @import("chilli");

const DownloadContext = struct {
    client: std.http.Client,
    allocator: std.mem.Allocator,
};

fn rootExec(ctx: chilli.CommandContext) !void {
    try ctx.command.printHelp();
}

fn downloadExec(ctx: chilli.CommandContext) !void {
    const url = try ctx.getArg("url", []const u8);
    const output_path_arg = try ctx.getArg("output", []const u8);
    const verbose = try ctx.getFlag("verbose", bool);

    var download_ctx = ctx.getContextData(DownloadContext).?;

    const output_path = if (output_path_arg.len > 0)
        try download_ctx.allocator.dupe(u8, output_path_arg)
    else
        try getFilenameFromUrl(download_ctx.allocator, url);
    defer download_ctx.allocator.free(output_path);

    if (verbose) {
        std.debug.print("Downloading: {s}\n", .{url});
        std.debug.print("Output file: {s}\n", .{output_path});
    }

    // Parse URI and create request
    const uri = try std.Uri.parse(url);
    var req = try download_ctx.client.request(.GET, uri, .{});
    defer req.deinit();

    // Send request
    try req.sendBodiless();

    // Receive response headers
    var redirect_buf: [1024]u8 = undefined;
    var response = try req.receiveHead(&redirect_buf);

    if (response.head.status != .ok) {
        std.debug.print("Error: HTTP {d} - {s}\n", .{ @intFromEnum(response.head.status), @tagName(response.head.status) });
        return error.HttpRequestFailed;
    }

    // Read response body
    var buf: [8192]u8 = undefined;
    var body_reader = response.reader(&buf);

    var response_body: std.ArrayList(u8) = .{};
    defer response_body.deinit(ctx.app_allocator);

    try body_reader.appendRemainingUnlimited(ctx.app_allocator, &response_body);

    if (verbose) {
        std.debug.print("Downloaded {d} bytes\n", .{response_body.items.len});
    }

    // Write to file
    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();
    try file.writeAll(response_body.items);

    std.debug.print("Download complete: {s} ({d} bytes)\n", .{ output_path, response_body.items.len });
}

fn getFilenameFromUrl(allocator: std.mem.Allocator, url: []const u8) ![]const u8 {
    const uri = std.Uri.parse(url) catch
        return allocator.dupe(u8, "downloaded_file");

    const path_str = switch (uri.path) {
        .raw => |raw| raw,
        .percent_encoded => |encoded| encoded,
    };

    const filename = if (std.mem.lastIndexOfScalar(u8, path_str, '/')) |idx|
        path_str[idx + 1 ..]
    else
        path_str;

    if (filename.len == 0) {
        return allocator.dupe(u8, "downloaded_file");
    }

    return allocator.dupe(u8, filename);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var download_ctx = DownloadContext{
        .client = client,
        .allocator = allocator,
    };

    var root_cmd = try chilli.Command.init(allocator, .{
        .name = "downloader",
        .description = "A simple file downloader using HTTP.",
        .exec = rootExec,
    });
    defer root_cmd.deinit();

    try root_cmd.addFlag(.{
        .name = "verbose",
        .shortcut = 'v',
        .description = "Enable verbose output",
        .type = .Bool,
        .default_value = .{ .Bool = false },
    });

    var download_cmd = try chilli.Command.init(allocator, .{
        .name = "download",
        .description = "Download a file from a URL.",
        .exec = downloadExec,
    });

    try download_cmd.addPositional(.{
        .name = "url",
        .description = "The URL to download from.",
        .is_required = true,
    });

    try download_cmd.addPositional(.{
        .name = "output",
        .description = "Output filename (auto-detected if not provided).",
        .is_required = false,
        .default_value = .{ .String = "" },
    });

    try root_cmd.addSubcommand(download_cmd);

    try root_cmd.run(&download_ctx);
}

// Example Invocations
//
// 1. Build the example executable:
//    zig build e6_file_downloader
//
// 2. Run with different arguments:
//
//    // Show the help message
//    ./zig-out/bin/e6_file_downloader --help
//
//    // Download a file, letting the program determine the output filename
//    ./zig-out/bin/e6_file_downloader download https://ziglang.org/zig-logo.svg
//
//    // Download a file with verbose logging and a specified output filename
//    ./zig-out/bin/e6_file_downloader -v download https://ziglang.org/documentation/master/std/std.zig zig_std.zig
