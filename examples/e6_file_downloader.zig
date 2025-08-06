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

    const uri = std.Uri.parse(url) catch |err| {
        std.debug.print("Error: Invalid URL: {any}\n", .{err});
        return;
    };

    var server_header_buffer: [16 * 1024]u8 = undefined;
    var req = download_ctx.client.open(.GET, uri, .{
        .server_header_buffer = &server_header_buffer,
    }) catch |err| {
        std.debug.print("Error: Failed to create request: {any}\n", .{err});
        return;
    };
    defer req.deinit();

    try req.send();
    try req.finish();
    try req.wait();

    if (req.response.status != .ok) {
        std.debug.print("Error: HTTP {d} - {s}\n", .{ @intFromEnum(req.response.status), @tagName(req.response.status) });
        return;
    }

    const file = std.fs.cwd().createFile(output_path, .{}) catch |err| {
        std.debug.print("Error: Failed to create output file: {any}\n", .{err});
        return;
    };
    defer file.close();

    var buffer: [8192]u8 = undefined;
    var total_bytes: u64 = 0;

    // CORRECTED: Use a while(true) loop and break when read() returns 0.
    while (true) {
        const bytes_read = req.reader().read(&buffer) catch |err| {
            if (err == error.EndOfStream) break;
            std.debug.print("Error: Failed to read response: {any}\n", .{err});
            return;
        };

        if (bytes_read == 0) break;

        try file.writeAll(buffer[0..bytes_read]);
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
