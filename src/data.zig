const std = @import("std");
const http = std.http;
const net = std.net;
const log = std.log;
const json = std.json;

const Allocator = std.mem.Allocator;

const API_URL = "https://ziglang.org/download/index.json";
const MAX_BUFFER_LEN = 50_000;

const Distribution = struct {
    tarball: []const u8,
    shasum: []const u8,
    size: []const u8,
};

const Version = struct {
    version: ?[]const u8 = null,
    date: ?[]const u8 = null,
    docs: ?[]const u8 = null,
    src: ?Distribution = null,
    bootstrap: ?Distribution = null,
};

/// All member functions are on *const as they are usually accessed via a list
pub const Zig = struct {
    name: []const u8,
    version: Version,

    /// Call this with the same allocator
    /// that was used to init the struct
    pub fn deinit(self: *const Zig, allocator: Allocator) void {
        allocator.free(self.name);
        json.parseFree(Version, self.version, .{ .allocator = allocator });
    }

    pub fn dump(self: *const Zig) void {
        log.info("Zig Version {s}", .{self.name});
        log.info("Released On {s}", .{self.version.date.?});
    }
};

const ZigArrayList = std.ArrayList(Zig);

fn getApiContent(allocator: Allocator) ![]const u8 {
    var http_client = http.Client{
        .allocator = allocator,
    };
    defer http_client.deinit();

    var uri = try std.Uri.parse(API_URL);

    var depth: u8 = 0;

    var request: ?http.Client.Request = null;
    defer request.?.deinit();

    while (depth < 10) : (depth += 1) {
        request = http_client.request(uri, .{}, .{}) catch |err| {
            log.err("Request {} failed. {!}.", .{ depth, err });
            continue;
        };
        break;
    }

    if (depth == 10 or request == null) {
        log.err("Failed to retrieve data.", .{});
        return error.RequestFailed;
    }

    var reader = request.?.reader();

    return try reader.readAllAlloc(allocator, MAX_BUFFER_LEN);
}

pub fn getZigVersions(allocator: Allocator) !ZigArrayList.Slice {
    var raw_json = try getApiContent(allocator);
    defer allocator.free(raw_json);

    var json_parser = json.Parser.init(allocator, false);
    defer json_parser.deinit();

    var base_obj = try json_parser.parse(raw_json);
    defer base_obj.deinit();

    var result = ZigArrayList.init(allocator);

    switch (base_obj.root) {
        .Object => |obj| {
            var iter = obj.iterator();
            while (iter.next()) |value| {
                var name_buf = try allocator.alloc(u8, value.key_ptr.*.len);
                std.mem.copy(u8, name_buf, value.key_ptr.*);

                var str = std.ArrayList(u8).init(allocator);

                try value.value_ptr.jsonStringify(.{}, str.writer());

                var json_blob = try str.toOwnedSlice();
                defer allocator.free(json_blob);

                var token_stream = json.TokenStream.init(json_blob);
                var version_details = try json.parse(Version, &token_stream, .{
                    .allocator = allocator,
                    .ignore_unknown_fields = true,
                });

                var version = Zig{
                    .name = name_buf,
                    .version = version_details,
                };

                try result.append(version);
            }
        },
        else => unreachable,
    }

    return try result.toOwnedSlice();
}
