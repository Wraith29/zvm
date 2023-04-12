const std = @import("std");
const commands = @import("./commands/cmd.zig");

const Allocator = std.mem.Allocator;

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = general_purpose_allocator.deinit();
    var allocator = general_purpose_allocator.allocator();

    var args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);

    if (args.len <= 1) {
        return commands.usage();
    }

    var command = args[1];

    return try commands.execute(allocator, command, if (args.len < 2) &[0][]const u8{} else args[2..]);
}
