const std = @import("std");
const log = std.log;
const http = std.http;
const data = @import("../data.zig");

const path = @import("../path.zig");

const ZvmPaths = path.ZvmPaths;
const Allocator = std.mem.Allocator;

/// Simple Wrapper around `std.mem.eql`
inline fn strEql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

inline fn asMegabytes(bits: u64) u64 {
    return bits / 1000 / 1000;
}

inline fn fromMegabytes(bits: usize) usize {
    return bits * 1000 * 1000;
}

pub const usage = @import("./usage.zig").usage;

fn isValidVersion(target: []const u8, versions: []data.Zig) bool {
    for (versions) |v| {
        if (strEql(v.name, target)) return true;
    }

    return false;
}

fn listCommands(allocator: Allocator, paths: ZvmPaths, args: [][]const u8) !void {
    return if (args.len < 1) {
        var versions = try data.getZigVersions(allocator);
        defer {
            for (versions) |version| {
                version.deinit(allocator);
            }
            allocator.free(versions);
        }

        log.info("Versions:", .{});
        for (versions) |version| {
            log.info("  {s}", .{version.name});
        }
    } else if (strEql(args[0], "-i") or strEql(args[0], "--installed")) {
        std.log.info("Installed Versions:", .{});

        var tc_dir = try std.fs.openIterableDirAbsolute(paths.toolchain_path, .{});
        var iter = tc_dir.iterate();

        while (try iter.next()) |pth| {
            log.info("  {s}", .{pth.name});
        }
    };
}

fn createAndGetVersionDirectory(allocator: Allocator, paths: ZvmPaths, version: []const u8) ![]const u8 {
    var version_dir = try std.mem.concat(allocator, u8, &[_][]const u8{
        paths.toolchain_path,
        std.fs.path.sep_str,
        "zig-",
        version,
    });

    if (!path.pathExists(version_dir)) {
        try std.fs.makeDirAbsolute(version_dir);
    }

    log.info("{s}", .{version_dir});

    return version_dir;
}

fn downloadZigVersion(allocator: Allocator, url: []const u8) ![]const u8 {
    var client = http.Client{
        .allocator = allocator,
    };

    defer client.deinit();

    var uri = try std.Uri.parse(url);

    var request = try client.request(uri, .{}, .{});
    defer request.deinit();

    var reader = request.reader();

    return reader.readAllAlloc(allocator, fromMegabytes(50));
}

fn installCommands(allocator: Allocator, paths: ZvmPaths, args: [][]const u8) !void {
    return if (args.len < 1) {
        log.err("Missing Parameter: 'version'", .{});
    } else {
        var target_version = args[0];

        var all_versions = try data.getZigVersions(allocator);
        defer {
            for (all_versions) |version|
                version.deinit(allocator);

            allocator.free(all_versions);
        }

        var version_to_install = blk: {
            for (all_versions) |version| {
                if (strEql(target_version, version.name)) break :blk version;
            }

            log.err("Invalid Version: {s}", .{target_version});
            return;
        };

        var version_dir = try createAndGetVersionDirectory(allocator, paths, target_version);
        defer allocator.free(version_dir);

        var src_tar = try downloadZigVersion(allocator, version_to_install.version.src.?.tarball);
        defer allocator.free(src_tar);

        var src_tar_file = try std.mem.concat(allocator, u8, &[_][]const u8{
            version_dir,
            std.fs.path.sep_str,
            "zig-",
            version_to_install.name,
            ".tar.xz",
        });
        defer allocator.free(src_tar_file);

        if (!path.pathExists(src_tar_file)) {
            log.info("Trying to create file: {s}", .{src_tar_file});
            var f = try std.fs.createFileAbsolute(src_tar_file, .{});
            f.close();
        }

        var file = try std.fs.openFileAbsolute(src_tar_file, .{ .mode = .write_only });
        defer file.close();

        try file.writeAll(src_tar);
        var writer = file.writer();

        try writer.writeAll(src_tar);
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
