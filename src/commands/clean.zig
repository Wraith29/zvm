const std = @import("std");
const Allocator = std.mem.Allocator;

const Path = @import("../Path.zig");

/// TODO: Implement
pub fn cleanup(allocator: Allocator, paths: *const Path) !void {
    _ = paths;
    _ = allocator;
}
