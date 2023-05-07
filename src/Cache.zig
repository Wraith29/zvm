const std = @import("std");

const Allocator = std.mem.Allocator;

const HttpClient = @import("./HttpClient.zig");
const ZigVersion = @import("./ZigVersion.zig");
const Path = @import("./Path.zig");
const Architecture = @import("./Architecture.zig");
const size = @import("./size.zig");

const INDEX_URL = "https://ziglang.org/download/index.json";
const MAX_CACHE_SIZE = size.fromMegabytes(5);
const Cache = @This();

/// Unix Timestamp of when Cache was last loaded
cache_date: i64,
/// The Versions loaded in the Cache
versions: []ZigVersion,

pub fn forceReload(allocator: Allocator, cache_path: []const u8) !void {
    _ = try Cache.populate(allocator, cache_path);
}

pub fn populate(allocator: Allocator, cache_path: []const u8) !Cache {
    const computer_architecture = comptime Architecture.getComputerArchitecture() catch |err| {
        std.log.err("Unsupported Computer Architecture. {!}", .{err});
    };

    std.log.info("Requesting Version Data from {s}", .{INDEX_URL});
    const json_string = HttpClient.get(allocator, INDEX_URL) catch |err| {
        std.log.err("Unable to load version info from {s}. {!}", .{ INDEX_URL, err });
        return error.CacheLoadError;
    };
    defer allocator.free(json_string);

    var parser = std.json.Parser.init(allocator, false);
    defer parser.deinit();

    std.log.info("Parsing Version Info", .{});
    var json_obj = try parser.parse(json_string);
    defer json_obj.deinit();

    var versions = std.ArrayList(ZigVersion).init(allocator);

    switch (json_obj.root) {
        .Object => |obj| {
            var iterator = obj.iterator();
            while (iterator.next()) |value| {
                var name_buf = try allocator.alloc(u8, value.key_ptr.*.len);
                @memcpy(name_buf, value.key_ptr.*);

                var string = std.ArrayList(u8).init(allocator);

                try value.value_ptr.jsonStringify(.{}, string.writer());

                var download_object = switch (value.value_ptr.*) {
                    .Object => |inner| blk: {
                        if (inner.contains(computer_architecture)) {
                            var download_obj = inner.get(computer_architecture).?;
                            var download_string = std.ArrayList(u8).init(allocator);
                            try download_obj.jsonStringify(.{}, download_string.writer());

                            var download_blob = try download_string.toOwnedSlice();
                            defer allocator.free(download_blob);

                            var download_tokens = std.json.TokenStream.init(download_blob);
                            var download = try std.json.parse(ZigVersion.Download, &download_tokens, .{
                                .allocator = allocator,
                                .ignore_unknown_fields = true,
                            });

                            break :blk download;
                        }
                        break :blk null;
                    },
                    else => null,
                };

                var json_blob = try string.toOwnedSlice();
                defer allocator.free(json_blob);

                var token_stream = std.json.TokenStream.init(json_blob);

                var details = try std.json.parse(ZigVersion.Details, &token_stream, .{
                    .allocator = allocator,
                    .ignore_unknown_fields = true,
                });

                details.download = download_object;

                var version = ZigVersion{
                    .name = name_buf,
                    .version = details,
                };
                try versions.append(version);
            }
        },
        else => unreachable,
    }

    var cache_versions = try versions.toOwnedSlice();

    var cache_obj = Cache{
        .cache_date = std.time.milliTimestamp(),
        .versions = cache_versions,
    };

    var out_string = std.ArrayList(u8).init(allocator);

    var string_writer = out_string.writer();

    try std.json.stringify(cache_obj, .{}, string_writer);

    var cache_file = try Path.openFile(cache_path, .{ .mode = .write_only });
    defer cache_file.close();

    var out_blob = try out_string.toOwnedSlice();
    defer allocator.free(out_blob);

    try cache_file.writeAll(out_blob);

    return cache_obj;
}

pub fn load(allocator: Allocator, cache_path: []const u8) !Cache {
    var cache_file = Path.openFile(cache_path, .{}) catch |err| {
        std.log.err("Failed to open Cache File {!}", .{err});
        return err;
    };
    defer cache_file.close();

    var contents = cache_file.reader().readAllAlloc(allocator, MAX_CACHE_SIZE) catch |err| {
        std.log.err("Failed to read Cache. {!}", .{err});
        return err;
    };
    defer allocator.free(contents);

    var token_stream = std.json.TokenStream.init(contents);

    return try std.json.parse(Cache, &token_stream, .{
        .allocator = allocator,
        .ignore_unknown_fields = true,
        .allow_trailing_data = true,
    });
}

pub fn getZigVersions(allocator: Allocator, paths: *const Path) ![]ZigVersion {
    var cache_path = try paths.getCachePath();
    defer allocator.free(cache_path);

    std.log.info("Reading Cache From {s}", .{cache_path});
    var cache = Cache.load(allocator, cache_path) catch |err| blk: {
        std.log.err("Cache Load Failed. Repopulating. {!}", .{err});
        break :blk try Cache.populate(allocator, cache_path);
    };

    if (cache.cache_date + std.time.ms_per_day < std.time.milliTimestamp()) {
        std.log.info("Cache out of date, reloading", .{});
        std.json.parseFree(Cache, cache, .{ .allocator = allocator });

        var updated_cache = try Cache.populate(allocator, cache_path);

        return updated_cache.versions;
    }

    return cache.versions;
}
