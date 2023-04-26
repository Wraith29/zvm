const std = @import("std");
const Allocator = std.mem.Allocator;

/// Simple Wrapper around `std.mem.eql`
pub inline fn strEql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// Simple Wrapper around `std.mem.concat`
pub inline fn concat(allocator: Allocator, items: []const []const u8) ![]const u8 {
    return try std.mem.concat(allocator, u8, items);
}

pub inline fn contains(haystack: []const []const u8, needle: []const u8) bool {
    for (haystack) |string| {
        if (strEql(string, needle)) return true;
    }

    return false;
}
