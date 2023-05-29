const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

pub fn execute(allocator: Allocator) !void {
    var result = try std.ChildProcess.exec(.{ .allocator = allocator, .argv = &.{ "zig", "version" } });

    std.log.info("Current Version: {s}", .{result.stdout});
}
