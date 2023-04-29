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

    std.log.info("Waiting the request", .{});
    request.wait() catch |err| {
        std.log.err("err waiting the request {!}", .{err});
    };
    std.log.info("Request Waited", .{});

    std.log.info("Received Request", .{});

    // var zon_file = try std.fs.cwd().openFile("./req.zon", .{ .mode = .write_only });
    // defer zon_file.close();
    // var writer = zon_file.writer();

    // try std.json.stringify(&request, .{ .whitespace = .{ .indent = .{ .Space = 4 } } }, writer);

    var reader = request.reader();

    // var idx: u64 = 0;
    // while (idx < request.response.content_length orelse MAX_REQUEST_SIZE) : (idx += 100) {
    //     var buf: [100]u8 = undefined;

    //     var read_size = try reader.read(&buf);
    //     std.log.info("{s}", .{buf[0..read_size]});
    // }

    var contents = try reader.readAllAlloc(allocator, request.response.content_length orelse MAX_REQUEST_SIZE);
    return contents;
}
