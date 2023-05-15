const std = @import("std");
const Allocator = std.mem.Allocator;
const ArgParser = @import("../ArgParser.zig").ArgParser;
const Cache = @import("../Cache.zig");
const Commands = @import("./commands.zig").Commands;
const Path = @import("../Path.zig");
const qol = @import("../qol.zig");
const ZigVersion = @import("../ZigVersion.zig");

pub fn isAlreadyInstalled(allocator: Allocator, paths: *const Path, version: []const u8) !bool {
    var toolchain_dir = try paths.getToolchainPath();
    defer allocator.free(toolchain_dir);

    var iterable_dir = try std.fs.openIterableDirAbsolute(toolchain_dir, .{});
    defer iterable_dir.close();
    var iterator = iterable_dir.iterate();

    while (try iterator.next()) |entry| {
        if (qol.strEql(entry.name, version)) return true;
    }
    return false;
}

pub fn select(allocator: Allocator, paths: *const Path, version: []const u8) !void {
    var new_path = try paths.getVersionPath(version);
    defer allocator.free(new_path);

    var sym_path = try qol.concat(allocator, &[_][]const u8{ paths.base_path, std.fs.path.sep_str, "zig" });
    defer allocator.free(sym_path);

    if (Path.pathExists(sym_path)) {
        try std.fs.deleteTreeAbsolute(sym_path);
    }

    try std.fs.symLinkAbsolute(new_path, sym_path, .{ .is_directory = true });
}

pub fn getTargetVersion(allocator: Allocator, args: *ArgParser(Commands), paths: *const Path) !ZigVersion {
    var target_version = args.args.items[0];

    var all_versions = try Cache.getZigVersions(allocator, paths);

    var version_to_install: ?ZigVersion = null;

    for (all_versions) |version| {
        if (qol.strEql(target_version, version.name)) {
            version_to_install = version;
            continue;
        }
        version.deinit(allocator);
    }

    if (version_to_install == null) {
        std.log.err("Invalid Version: {s}", .{target_version});
        return error.InvalidVersion;
    }

    return version_to_install.?;
}

pub fn execute(allocator: Allocator, args: *ArgParser(Commands), paths: *const Path) !void {
    var target_version = try getTargetVersion(allocator, args, paths);
    defer target_version.deinit(allocator);

    if (!try isAlreadyInstalled(allocator, paths, target_version.name)) {
        std.log.err("Failed to select {s} as it is not installed.", .{target_version.name});
        std.log.err("Try running: \"{s}\" to install & select it", .{target_version.name});
        return;
    }

    try select(allocator, paths, target_version.name);
}
