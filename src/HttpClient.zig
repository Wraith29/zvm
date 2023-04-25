const std = @import("std");
const Allocator = std.mem.Allocator;

const size = @import("./size.zig");

const MAX_REQUEST_SIZE = size.fromMegabytes(100);

pub fn get(allocator: Allocator, url: []const u8) ![]const u8 {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var uri = try std.Uri.parse(url);

    var recurse_depth: u8 = 0;

    var request = request_blk: while (recurse_depth < 10) : (recurse_depth += 1) {
        var res = client.request(.GET, uri, .{ .allocator = allocator }, .{}) catch |err| {
            std.log.err("Request {} Failed. {!}", .{ recurse_depth, err });
            continue;
        };
        break :request_blk res;
    } else {
        return error.RequestFailed;
    };

    if (recurse_depth == 10) {
        std.log.err("Failed to Request the Data.", .{});
        return error.DownloadError;
    }

    var reader = request.reader();
    return reader.readAllAlloc(allocator, MAX_REQUEST_SIZE) catch |err| {
        std.log.err("Failed to Read the Request. {!}", .{err});
        return error.ReadError;
    };
}
