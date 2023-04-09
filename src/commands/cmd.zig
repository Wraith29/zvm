const std = @import("std");
const log = std.log;

const Allocator = std.mem.Allocator;

/// Simple Wrapper around `std.mem.eql`
inline fn strEql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub const usage = @import("./usage.zig").usage;
pub const version = @import("./version.zig");

/// Execute the given command
pub fn execute(allocator: Allocator, command: []const u8, args: [][]const u8) !void {
    return if (strEql(command, "list")) {
        if (args.len <= 1) {
            var names = try version.getVersionNames(allocator);
            defer allocator.free(names);

            for (names) |name| {
                log.info("{s}", .{name});
            }
        }
    } else {
        usage();
    };
}
