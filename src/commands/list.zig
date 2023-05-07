const std = @import("std");

const Args = @import("../Args.zig");
const qol = @import("../qol.zig");
const Path = @import("../Path.zig");
const Cache = @import("../Cache.zig");

const Allocator = std.mem.Allocator;

fn listAvailableVersions(allocator: Allocator, paths: *const Path) !void {
    std.log.info("Listing Available Versions", .{});
    var versions = try Cache.getZigVersions(allocator, paths);
    defer {
        for (versions) |version| version.deinit(allocator);
        allocator.free(versions);
    }

    std.log.info("Versions: ", .{});
    for (versions) |version|
        std.log.info("  {s}", .{version.name});
}

fn listInstalledVersions(allocator: Allocator, paths: *const Path) !void {
    std.log.info("Installed Versions: ", .{});
    var toolchain_path = try paths.getToolchainPath();
    defer allocator.free(toolchain_path);
    var tc_dir = try std.fs.openIterableDirAbsolute(toolchain_path, .{});
    var iter = tc_dir.iterate();

    while (try iter.next()) |pth| {
        std.log.info("  {s}", .{pth.name});
    }
}

pub fn listCommands(
    allocator: Allocator,
    args: *Args,
    paths: *const Path,
) !void {
    if (args.hasFlag("-rc") or args.hasFlag("--reload-cache")) {
        std.log.info("Reload Cache Flag Detected. Reloading", .{});
        var cache_path = try paths.getCachePath();
        try Cache.forceReload(allocator, cache_path);
        allocator.free(cache_path);
    }

    return if (args.hasFlag("-i") or args.hasFlag("--installed"))
        listInstalledVersions(allocator, paths)
    else
        listAvailableVersions(allocator, paths);
}
