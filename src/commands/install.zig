const std = @import("std");
const Allocator = std.mem.Allocator;

const Args = @import("../Args.zig");
const HttpClient = @import("../HttpClient.zig");
const Path = @import("../Path.zig");
const Cache = @import("../Cache.zig");
const ZigVersion = @import("../ZigVersion.zig");
const qol = @import("../qol.zig");

fn installVersion(allocator: Allocator, paths: *const Path, version: ZigVersion) !void {
    var tmp_version_name = try paths.getTmpVersionPath(version.name);
    defer allocator.free(tmp_version_name);

    var zip_file_path_base = try paths.getTmpVersionPath(version.name);
    defer allocator.free(zip_file_path_base);

    var zip_file_path = try qol.concat(allocator, &[_][]const u8{ zip_file_path_base, ".zip" });
    defer allocator.free(zip_file_path);

    std.log.info("Zip File: {s}", .{zip_file_path});

    var zip_file = try Path.openFile(zip_file_path, .{ .mode = .write_only });

    std.log.info("Attempting to download: {s}", .{version.version.download.?.tarball});
    var zip_contents = try HttpClient.get(allocator, version.version.download.?.tarball);

    try zip_file.writeAll(zip_contents);
}

pub fn installCommands(allocator: Allocator, args: *Args, paths: *const Path) !void {
    return if (args.lenCommands() < 1)
        std.log.err("Missing Parameter: 'version'", .{})
    else {
        var target_version = args.commands.items[1];

        std.log.info("Loading Versions", .{});
        var all_versions = try Cache.getZigVersions(allocator, paths);
        defer {
            for (all_versions) |version| {
                version.deinit(allocator);
            }
            allocator.free(all_versions);
        }

        var version_to_install = blk: {
            for (all_versions) |version| {
                if (qol.strEql(target_version, version.name)) break :blk version;
            }

            std.log.err("Invalid Version: {s}", .{target_version});
            return;
        };

        try paths.ensureToolchainDirExists();

        std.log.info("Installing Version: {s}", .{version_to_install.name});
        return installVersion(allocator, paths, version_to_install);
    };
}
