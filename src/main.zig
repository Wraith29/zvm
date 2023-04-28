const std = @import("std");
const commands = @import("./commands/cmd.zig");

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = general_purpose_allocator.deinit();
    var gp_allocator = general_purpose_allocator.allocator();
    var arena = std.heap.ArenaAllocator.init(gp_allocator);
    defer arena.deinit();

    var allocator = arena.allocator();

    var args = std.process.argsAlloc(allocator) catch |err| {
        std.log.err("Error Reading Args. {!}", .{err});
        return;
    };
    defer allocator.free(args);

    if (args.len <= 1) {
        return commands.usage();
    }

    var command = args[1];
    const args_to_pass = if (args.len < 2) try allocator.alloc([]const u8, 0) else args[2..];
    defer allocator.free(args_to_pass);

    return commands.execute(allocator, command, args_to_pass) catch |err| {
        std.log.err("Failed To Execute Command. {!}", .{err});
        return;
    };
}
