const std = @import("std");

const api = @import("../api.zig");
const path = @import("../path.zig");

const File = std.fs.File;
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

fn isValidVersion(target: []const u8, versions: []api.ZigVersion) bool {
    for (versions) |v| {
        if (strEql(v.name, target)) return true;
    }

    return false;
}

fn listCommands(allocator: Allocator, paths: *ZvmPaths, args: [][]const u8) !void {
    return if (args.len < 1) {
        var versions = try api.getZigVersions(allocator, paths);
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
    } else if (strEql(args[0], "-i") or strEql(args[0], "--installed")) {
        std.log.info("Installed Versions:", .{});

        var tc_dir = try std.fs.openIterableDirAbsolute(paths.toolchain_path, .{});
        var iter = tc_dir.iterate();

        while (try iter.next()) |pth| {
            std.log.info("  {s}", .{pth.name});
        }
    };
}

fn createAndGetVersionDirectory(allocator: Allocator, paths: *ZvmPaths, version: []const u8) ![]const u8 {
    var version_dir = try std.mem.concat(allocator, u8, &[_][]const u8{
        paths.toolchain_path,
        std.fs.path.sep_str,
        version,
    });

    if (!path.pathExists(version_dir)) {
        try std.fs.makeDirAbsolute(version_dir);
    }

    std.log.info("{s}", .{version_dir});

    return version_dir;
}

fn getVersionFilePath(allocator: Allocator, paths: *ZvmPaths, version: []const u8, ext: []const u8) ![]const u8 {
    return try std.mem.concat(
        allocator,
        u8,
        &[_][]const u8{ paths.version_path.?, std.fs.path.sep_str, version, ext },
    );
}

fn downloadZigVersion(allocator: Allocator, url: []const u8) ![]const u8 {
    var client = std.http.Client{
        .allocator = allocator,
    };

    defer client.deinit();

    var uri = try std.Uri.parse(url);

    var request = try client.request(uri, .{}, .{});
    defer request.deinit();

    var reader = request.reader();

    return reader.readAllAlloc(allocator, fromMegabytes(50));
}

/// If `file_path` doesn't exist, creates it
fn openFile(file_path: []const u8) !File {
    if (!path.pathExists(file_path)) {
        return try std.fs.createFileAbsolute(file_path, .{ .read = true });
    }

    return try std.fs.openFileAbsolute(file_path, .{ .mode = .read_write });
}

/// Return the Archive File Path
/// User must free memory
fn downloadArchive(allocator: Allocator, version: api.ZigVersion, paths: *ZvmPaths) ![]const u8 {
    var archive = try downloadZigVersion(allocator, version.version.bootstrap.?.tarball);
    defer allocator.free(archive);
    var archive_file_path = try getVersionFilePath(allocator, paths, version.name, ".tar.xz");

    var archive_file = try openFile(archive_file_path);
    defer archive_file.close();

    try archive_file.writer().writeAll(archive);

    return archive_file_path;
}

/// Decompress the `.tar.xz` file into a `.tar` file
fn decompressArchive(allocator: Allocator, version: api.ZigVersion, paths: *ZvmPaths, archive_fp: []const u8) ![]const u8 {
    var archive_file = try std.fs.openFileAbsolute(archive_fp, .{ .mode = .read_only });
    defer archive_file.close();

    var tarball = try std.compress.xz.decompress(allocator, archive_file.reader());
    defer tarball.deinit();

    var tarball_fp = try getVersionFilePath(allocator, paths, version.name, ".tar");

    var tarball_file = try openFile(tarball_fp);
    defer tarball_file.close();

    var tarball_reader = tarball.reader();

    var tarball_contents = try tarball_reader.readAllAlloc(allocator, fromMegabytes(400));
    defer allocator.free(tarball_contents);

    try tarball_file.writer().writeAll(tarball_contents);

    return tarball_fp;
}

fn cleanup(archive_fp: []const u8, tarball_fp: []const u8) !void {
    try std.fs.deleteFileAbsolute(archive_fp);
    try std.fs.deleteFileAbsolute(tarball_fp);
}

fn installCommands(allocator: Allocator, paths: *ZvmPaths, args: [][]const u8) !void {
    return if (args.len < 1) {
        std.log.err("Missing Parameter: 'version'", .{});
    } else {
        var target_version = args[0];

        var all_versions = try api.getZigVersions(allocator, paths);
        defer {
            for (all_versions) |version|
                version.deinit(allocator);

            allocator.free(all_versions);
        }

        var version_to_install = blk: {
            for (all_versions) |version| {
                if (strEql(target_version, version.name)) break :blk version;
            }

            std.log.err("Invalid Version: {s}", .{target_version});
            return;
        };

        var version_dir_path = try createAndGetVersionDirectory(allocator, paths, target_version);
        defer allocator.free(version_dir_path);

        paths.version_path = version_dir_path;

        var archive_fp = try downloadArchive(allocator, version_to_install, paths);
        defer allocator.free(archive_fp);

        var tarball_fp = try decompressArchive(allocator, version_to_install, paths, archive_fp);
        defer allocator.free(tarball_fp);

        var tarball_file = try std.fs.openFileAbsolute(tarball_fp, .{ .mode = .read_only });
        defer tarball_file.close();

        var version_dir = try std.fs.openDirAbsolute(version_dir_path, .{});

        try std.tar.pipeToFileSystem(version_dir, tarball_file.reader(), .{});

        try cleanup(archive_fp, tarball_fp);
    };
}

/// Execute the given command
pub fn execute(allocator: Allocator, command: []const u8, args: [][]const u8) !void {
    var paths = try ZvmPaths.init(allocator);
    defer paths.deinit();

    return if (strEql(command, "list")) {
        return listCommands(allocator, &paths, args);
    } else if (strEql(command, "install")) {
        return installCommands(allocator, &paths, args);
    } else {
        usage();
    };
}
