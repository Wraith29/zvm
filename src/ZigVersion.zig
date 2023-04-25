const std = @import("std");
const Cache = @import("./Cache.zig");
const path = @import("./path.zig");
const Allocator = std.mem.Allocator;

const Download = struct {
    tarball: []const u8,
    shasum: []const u8,
    size: []const u8,
};

pub const Details = struct {
    version: ?[]const u8 = null,
    date: ?[]const u8 = null,
    docs: ?[]const u8 = null,
    src: ?Download = null,
};

const ZigVersion = @This();

name: []const u8,
version: Details,

pub fn deinit(self: *const ZigVersion, allocator: Allocator) void {
    allocator.free(self.name);
    std.json.parseFree(Details, self.version, .{ .allocator = allocator });
}

pub fn load(allocator: Allocator, paths: *path.ZvmPaths) ![]ZigVersion {
    var cache_path = try paths.getCachePath();
    defer allocator.free(paths);

    var cache = Cache.load(allocator, cache_path) catch try Cache.populate(allocator, cache_path);

    if (cache.cache_date + std.time.ms_per_day < std.time.milliTimestamp()) {
        std.json.parseFree(Cache, cache, .{ .allocator = allocator });

        var updated_cache = try Cache.populate(allocator, cache_path);
        return updated_cache.versions;
    }

    return cache.versions;
}
