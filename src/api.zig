const std = @import("std");

const path = @import("./path.zig");
const size = @import("./size.zig");

const Allocator = std.mem.Allocator;

const API_URL = "https://ziglang.org/download/index.json";
const MAX_REQUEST_SIZE = size.fromMegabytes(50);
const MAX_CACHE_SIZE = size.fromMegabytes(5);

const Download = struct {
    tarball: []const u8,
    shasum: []const u8,
    size: []const u8,
};

const VersionDetails = struct {
    version: ?[]const u8 = null,
    date: ?[]const u8 = null,
    docs: ?[]const u8 = null,
    src: ?Download = null,
    bootstrap: ?Download = null,
};

pub const ZigVersion = struct {
    name: []const u8,
    version: VersionDetails,

    pub fn deinit(self: *const ZigVersion, allocator: Allocator) void {
        allocator.free(self.name);
        std.json.parseFree(VersionDetails, self.version, .{ .allocator = allocator });
    }
};

const Cache = struct {
    cache_date: i64, // Unix timestamp of cache time
    versions: []ZigVersion,

    fn deinit(self: *Cache, allocator: Allocator) void {
        for (self.versions) |version| {
            version.deinit(allocator);
        }
    }
};

pub const ZigVersionArrayList = std.ArrayList(ZigVersion);

/// Returns the content as a string
fn makeApiRequest(allocator: Allocator, url: []const u8) ![]const u8 {
    var http_client = std.http.Client{
        .allocator = allocator,
    };
    defer http_client.deinit();

    var uri = try std.Uri.parse(url);

    var recurse_depth: u8 = 0;

    var request: ?std.http.Client.Request = null;
    defer request.?.deinit();

    while (request == null and recurse_depth < 10) : (recurse_depth += 1) {
        request = http_client.request(uri, .{}, .{}) catch |err| {
            std.log.err("Request {} failed. {!}", .{ recurse_depth, err });
            continue;
        };
        std.log.info("Successfully Received Request", .{});
    }

    if (recurse_depth == 10 or request == null) {
        std.log.err("Failed to retrieve data.", .{});
        return error.RequestFailed;
    }

    var reader = request.?.reader();
    return try reader.readAllAlloc(allocator, MAX_REQUEST_SIZE);
}

/// Populates the cache with the latest info
fn populateCache(allocator: Allocator, cache_path: []const u8) !Cache {
    std.log.info("Repopulating Cache", .{});

    var api_str = try makeApiRequest(allocator, API_URL);
    defer allocator.free(api_str);

    var json_parser = std.json.Parser.init(allocator, false);
    defer json_parser.deinit();

    std.log.info("Parsing Json Object", .{});
    var json_object = try json_parser.parse(api_str);
    defer json_object.deinit();

    var zig_versions = ZigVersionArrayList.init(allocator);

    switch (json_object.root) {
        .Object => |obj| {
            var iterator = obj.iterator();
            while (iterator.next()) |value| {
                var name_buffer = try allocator.alloc(u8, value.key_ptr.*.len);
                std.mem.copy(u8, name_buffer, value.key_ptr.*);

                var string = std.ArrayList(u8).init(allocator);

                try value.value_ptr.jsonStringify(.{}, string.writer());

                var json_blob = try string.toOwnedSlice();
                defer allocator.free(json_blob);

                var token_stream = std.json.TokenStream.init(json_blob);

                var version_details = try std.json.parse(VersionDetails, &token_stream, .{
                    .allocator = allocator,
                    .ignore_unknown_fields = true,
                });

                var version = ZigVersion{
                    .name = name_buffer,
                    .version = version_details,
                };

                try zig_versions.append(version);
            }
        },
        else => unreachable,
    }

    var versions = try zig_versions.toOwnedSlice();

    var cache_object = Cache{
        .cache_date = std.time.milliTimestamp(),
        .versions = versions,
    };

    var json_string = std.ArrayList(u8).init(allocator);

    var string_writer = json_string.writer();

    try std.json.stringify(cache_object, .{}, string_writer);

    var cache_file = try path.openFile(cache_path, .{ .mode = .write_only });
    defer cache_file.close();

    std.log.info("Writing Cache to File {s}", .{cache_path});
    var string = try json_string.toOwnedSlice();
    defer allocator.free(string);

    try cache_file.writer().writeAll(string);
    std.log.info("Cache Written", .{});

    return cache_object;
}

/// Load the cache from the file
fn loadCacheFile(allocator: Allocator, cache_path: []const u8) !Cache {
    std.log.info("Loading Cache", .{});

    var cache_file = try path.openFile(cache_path, .{});
    defer cache_file.close();

    var contents = try cache_file.reader().readAllAlloc(allocator, MAX_CACHE_SIZE);
    defer allocator.free(contents);

    var token_stream = std.json.TokenStream.init(contents);
    return try std.json.parse(Cache, &token_stream, .{ .allocator = allocator });
}

pub fn getZigVersions(allocator: Allocator, paths: *path.ZvmPaths) ![]ZigVersion {
    std.log.info("Loading Version Info", .{});

    var cache_path = try paths.getCachePath();
    defer allocator.free(cache_path);

    var cache = loadCacheFile(allocator, cache_path) catch try populateCache(allocator, cache_path);

    if (cache.cache_date + std.time.ms_per_hour < std.time.milliTimestamp()) {
        std.log.info("Cache out of Date, Reloading", .{});
        cache = try populateCache(allocator, cache_path);
    }

    std.log.info("Cache Versions Loaded", .{});
    return cache.versions;
}
