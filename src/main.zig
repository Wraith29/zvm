const std = @import("std");
const data = @import("./data.zig");
const commands = @import("./commands/cmd.zig");

const Allocator = std.mem.Allocator;

/// Checks if a directory exists by opening it
fn dirExists(path: []const u8) bool {
    var dir = std.fs.openDirAbsolute(path, .{}) catch return false;
    dir.close();
    return true;
}

fn ensureAppDataDirectoryExists(allocator: Allocator) !void {
    var dir_path = try std.fs.getAppDataDir(allocator, ".zvm");
    defer allocator.free(dir_path);

    if (!dirExists(dir_path)) try std.fs.makeDirAbsolute(dir_path);
}

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = general_purpose_allocator.deinit();
    var allocator = general_purpose_allocator.allocator();

    try ensureAppDataDirectoryExists(allocator);

    var args = try std.process.argsAlloc(allocator);
    defer allocator.free(args);

    if (args.len <= 1) {
        return commands.usage();
    }

    var command = args[1];
    _ = command;

    var versions = try data.getZigVersions(allocator);
    defer allocator.free(versions);

    // return try commands.execute(allocator, command, args[1..]);
}
