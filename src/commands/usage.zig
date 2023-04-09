const info = @import("std").log.info;

pub fn usage() void {
    info("Usage:", .{});
    info("  zvm help - display this message", .{});
    info("  zvm list [-i, --installed] - list available versions", .{});
}
