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

    // Determine output filename
    const output_path = if (std.mem.eql(u8, output_path_arg, "")) blk: {
        const filename = try getFilenameFromUrl(ctx.allocator, url);
        defer ctx.allocator.free(filename);
        break :blk try ctx.allocator.dupe(u8, filename);
    } else try ctx.allocator.dupe(u8, output_path_arg);
    defer ctx.allocator.free(output_path);

    if (verbose) {
        std.debug.print("Downloading: {s}\n", .{url});
        std.debug.print("Output file: {s}\n", .{output_path});
    }

    // Parse the URL
    const uri = std.Uri.parse(url) catch |err| {
        std.debug.print("Error: Invalid URL: {any}\n", .{err});
        return;
    };

    // Create HTTP request
    var req = download_ctx.client.open(.GET, uri, .{
        .server_header_buffer = try ctx.allocator.alloc(u8, 16 * 1024),
    }) catch |err| {
        std.debug.print("Error: Failed to create request: {any}\n", .{err});
        return;
    };
    defer req.deinit();

    // Send request and wait for response
    req.send() catch |err| {
        std.debug.print("Error: Failed to send request: {any}\n", .{err});
        return;
    };

    req.finish() catch |err| {
        std.debug.print("Error: Failed to finish request: {any}\n", .{err});
        return;
    };

    req.wait() catch |err| {
        std.debug.print("Error: Failed to receive response: {any}\n", .{err});
        return;
    };

    if (req.response.status != .ok) {
        std.debug.print("Error: HTTP {d} - {s}\n", .{ @intFromEnum(req.response.status), @tagName(req.response.status) });
        return;
    }

    // Create output file
    const file = std.fs.cwd().createFile(output_path, .{}) catch |err| {
        std.debug.print("Error: Failed to create output file: {any}\n", .{err});
        return;
    };
    defer file.close();

    // Read and write response body
    var buffer: [8192]u8 = undefined;
    var total_bytes: u64 = 0;

    while (true) {
        const bytes_read = req.readAll(buffer[0..]) catch |err| {
            std.debug.print("Error: Failed to read response: {any}\n", .{err});
            return;
        };

        if (bytes_read == 0) break;

        file.writeAll(buffer[0..bytes_read]) catch |err| {
            std.debug.print("Error: Failed to write to file: {any}\n", .{err});
            return;
        };

        total_bytes += bytes_read;

        if (verbose) {
            std.debug.print("Downloaded: {d} bytes\r", .{total_bytes});
        }
    }

    if (verbose) {
        std.debug.print("\n", .{});
    }

    std.debug.print("Download complete: {s} ({d} bytes)\n", .{ output_path, total_bytes });
}

fn getFilenameFromUrl(allocator: std.mem.Allocator, url: []const u8) ![]const u8 {
    const uri = std.Uri.parse(url) catch return "downloaded_file";

    // Extract the path string from the Uri.Component
    const path_str = switch (uri.path) {
        .raw => |raw| raw,
        .percent_encoded => |encoded| encoded,
    };

    const filename = if (std.mem.lastIndexOfScalar(u8, path_str, '/')) |idx|
        path_str[idx + 1 ..]
    else
        path_str;

    if (filename.len == 0) {
        return try allocator.dupe(u8, "downloaded_file");
    }

    return try allocator.dupe(u8, filename);
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
