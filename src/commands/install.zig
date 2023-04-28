const std = @import("std");
const Allocator = std.mem.Allocator;

const Path = @import("../Path.zig");
const ZigVersion = @import("../ZigVersion.zig");
const qol = @import("../qol.zig");

pub fn installCommands(allocator: Allocator, paths: *Path, args: [][]const u8) !void {
    return if (args.len < 1) {
        std.log.err("Missing Parameter: 'version'", .{});
    } else {
        var target_version = args[0];

        var all_versions = try ZigVersion.load(allocator, paths);
        defer for (all_versions) |version| {
            version.deinit(allocator);
        };
        defer allocator.free(all_versions);

        var version_to_install = blk: {
            for (all_versions) |version| {
                if (qol.strEql(target_version, version.name)) break :blk version;
            }

            std.log.err("Invalid Version: {s}", .{target_version});
            return;
        };
        _ = version_to_install;
    };
}
