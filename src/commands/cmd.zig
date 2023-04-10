const std = @import("std");
const log = std.log;
const data = @import("../data.zig");

const ZvmPaths = @import("../path.zig").ZvmPaths;
const Allocator = std.mem.Allocator;

/// Simple Wrapper around `std.mem.eql`
inline fn strEql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub const usage = @import("./usage.zig").usage;

fn listCommands(allocator: Allocator, paths: ZvmPaths, args: [][]const u8) !void {
    return if (args.len < 1) {
        var versions = try data.getZigVersions(allocator);
        defer for (versions) |version| {
            version.deinit(allocator);
        };
        defer allocator.free(versions);

        log.info("Versions:", .{});
        for (versions) |version| {
            log.info("  {s}", .{version.name});
        }
    } else if (strEql(args[0], "-i") or strEql(args[0], "--installed")) {
        std.log.info("Installed Versions:", .{});

        var tc_dir = try std.fs.openIterableDirAbsolute(paths.toolchain_path, .{});
        var iter = tc_dir.iterate();

        while (try iter.next()) |path| {
            log.info("  {s}", .{path.name});
        }
    };
}

fn installCommands(allocator: Allocator, paths: ZvmPaths, args: [][]const u8) !void {
    _ = paths;
    _ = allocator;
    return if (args.len < 1) {
        log.err("Missing Parameter: 'version'", .{});
    } else {
        var version = args[0];
        log.info("Installing Version: {s}", .{version});
    };
}

/// Execute the given command
pub fn execute(allocator: Allocator, command: []const u8, args: [][]const u8) !void {
    var paths = try ZvmPaths.init(allocator);
    defer paths.deinit();

    return if (strEql(command, "list")) {
        return listCommands(allocator, paths, args);
    } else if (strEql(command, "install")) {
        return installCommands(allocator, paths, args);
    } else {
        usage();
    };
}
