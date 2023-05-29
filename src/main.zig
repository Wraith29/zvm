const std = @import("std");
const cmd = @import("./commands/cmd.zig");
const Commands = @import("./commands/commands.zig").Commands;
const ArgParser = @import("./ArgParser.zig").ArgParser;
const Path = @import("./Path.zig");

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
    defer std.process.argsFree(allocator, args);

    var parsed_args = ArgParser(Commands).init(
        allocator,
        &[_][]const u8{ "usage", "list", "install", "select", "use", "current", "latest", "delete" },
    );
    defer parsed_args.deinit();

    // Gives everything except for the executable name
    try parsed_args.parse(args[1..]);

    const path = try Path.init(allocator);
    defer path.deinit();
    try path.setup();

    return cmd.execute(allocator, &parsed_args, &path) catch |err| {
        std.log.err("Failed To Execute Command. {!}", .{err});
        return;
    };
}

test {
    std.testing.refAllDecls(@This());
    _ = @import("./list.zig");
    _ = @import("./ArgParser.zig");
}
