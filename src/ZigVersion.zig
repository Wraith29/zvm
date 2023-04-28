const std = @import("std");
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
