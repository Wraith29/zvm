const std = @import("std");
const Allocator = std.mem.Allocator;

const size = @import("./size.zig");

const MAX_REQUEST_SIZE: u64 = @trunc(size.fromMegabytes(200));

pub fn get(allocator: Allocator, url: []const u8) ![]const u8 {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var uri = try std.Uri.parse(url);

    var recurse_depth: u8 = 0;

    var request: std.http.Client.Request = request_blk: while (recurse_depth < 10) : (recurse_depth += 1) {
        var res = client.request(.GET, uri, .{ .allocator = allocator }, .{}) catch |err| {
            std.log.err("Request {} Failed. {!}", .{ recurse_depth, err });
            continue;
        };
        break :request_blk res;
    } else {
        return error.RequestFailed;
    };
    defer request.deinit();

    if (recurse_depth == 10) {
        std.log.err("Failed to Request the Data.", .{});
        return error.DownloadError;
    }

    request.start() catch |err| {
        std.log.err("Error Starting the Request {!}", .{err});
        return err;
    };

    request.wait() catch |err| {
        std.log.err("Error Waiting the request {!}", .{err});
        return err;
    };

    request.finish() catch |err| {
        std.log.err("Error Finishing the Request {!}", .{err});
        return err;
    };

    if (request.response.status.class() != .success) {
        std.log.err("Request Failed. {s}", .{request.response.reason});
        return error.UnsucessfulStatusCode;
    }

    var reader = request.reader();

    var contents = try reader.readAllAlloc(allocator, request.response.content_length orelse MAX_REQUEST_SIZE);

    return contents;
}
