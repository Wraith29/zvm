const std = @import("std");
const commands = @import("./commands/cmd.zig");
const Args = @import("./Args.zig");

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = general_purpose_allocator.deinit();
    var gp_allocator = general_purpose_allocator.allocator();
    var arena = std.heap.ArenaAllocator.init(gp_allocator);
    defer arena.deinit();

    var allocator = arena.allocator();

    std.log.info("Reading cmd args.", .{});
    var args = std.process.argsAlloc(allocator) catch |err| {
        std.log.err("Error Reading Args. {!}", .{err});
        return;
    };
    defer allocator.free(args);

    if (args.len <= 1) {
        return commands.usage();
    }

    var parsed_args = Args.init(allocator);
    defer parsed_args.deinit();

    // Gives everything except for the executable name
    try parsed_args.parse(args[1..]);

    std.log.info("Executing Commands", .{});
    return commands.execute(allocator, &parsed_args) catch |err| {
        std.log.err("Failed To Execute Command. {!}", .{err});
        return;
    };
}

test {
    _ = @import("./list.zig");

    std.testing.refAllDecls(@This());
}
