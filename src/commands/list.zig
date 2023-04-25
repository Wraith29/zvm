const std = @import("std");
const path = @import("../path.zig");
const qol = @import("../qol.zig");
const ZigVersion = @import("../ZigVersion.zig");

const Allocator = std.mem.Allocator;

pub fn listCommands(
    allocator: Allocator,
    paths: *path.ZvmPaths,
    args: []const []const u8,
) !void {
    return if (args.len < 1) {
        std.log.info("Listing Available Versions", .{});
        var versions = try ZigVersion.load(allocator, paths);
        defer {
            for (versions) |version| {
                version.deinit(allocator);
            }
            allocator.free(versions);
        }

        std.log.info("Versions:", .{});
        for (versions) |version| {
            std.log.info("  {s}", .{version.name});
        }
    } else if (qol.strEql(args[0], "-i") or qol.strEql(args[0], "--installed")) {
        std.log.info("Installed Versions:", .{});

        var tc_dir = try std.fs.openIterableDirAbsolute(paths.toolchain_path, .{});
        var iter = tc_dir.iterate();

        while (try iter.next()) |pth| {
            std.log.info("  {s}", .{pth.name});
        }
    };
}
