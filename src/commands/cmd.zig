const std = @import("std");
const builtin = @import("builtin");

const api = @import("../api.zig");
const path = @import("../path.zig");
const size = @import("../size.zig");

const File = std.fs.File;
const ZvmPaths = path.ZvmPaths;
const Allocator = std.mem.Allocator;

const SUPPORTED_VERSIONS = &[_][]const u8{
    "aarch64-linux-gnu",
    "aarch64-linux-musl",
    "aarch64-windows-gnu",
    "aarch64-macos-none",
    "arm-linux-musleabi",
    "arm-linux-musleabihf",
    "i386-linux-musl",
    "i386-windows-gnu",
    "powerpc64le-linux-musl",
    "powerpc64-linux-musl",
    "powerpc-linux-musl",
    "riscv64-linux-musl",
    "x86_64-linux-gnu",
    "x86_64-linux-musl",
    "x86_64-windows-gnu",
    "x86_64-macos-none",
};

/// Simple Wrapper around `std.mem.eql`
inline fn strEql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// Simple Wrapper around `std.mem.concat`
inline fn concat(allocator: Allocator, items: [][]const u8) ![]const u8 {
    return try std.mem.concat(allocator, u8, items);
}

inline fn contains(haystack: []const []const u8, needle: []const u8) bool {
    for (haystack) |string| {
        if (strEql(string, needle)) return true;
    }

    return false;
}

pub const usage = @import("./usage.zig").usage;

fn listCommands(allocator: Allocator, paths: *ZvmPaths, args: [][]const u8) !void {
    return if (args.len < 1) {
        std.log.info("Listing Available Versions", .{});
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

fn createAndGetVersionDirectory(paths: *ZvmPaths, version: []const u8) ![]const u8 {
    var version_dir = try paths.getVersionPath(version);

    if (!path.pathExists(version_dir)) {
        try std.fs.makeDirAbsolute(version_dir);
    }

    return version_dir;
}

fn downloadZigVersion(allocator: Allocator, url: []const u8, depth: u8) ![]const u8 {
    var client = std.http.Client{
        .allocator = allocator,
    };

    defer client.deinit();

    var uri = try std.Uri.parse(url);

    var request = try client.request(uri, .{}, .{});
    defer request.deinit();

    var reader = request.reader();

    return reader.readAllAlloc(allocator, size.fromMegabytes(50)) catch |err| switch (err) {
        error.UnexpectedEndOfStream => {
            std.log.err("Unexpected End Of Stream. Trying again", .{});

            // try one more time, if it fails again it will panic

            if (depth < 10)
                return downloadZigVersion(allocator, url, depth + 1)
            else {
                std.log.err("Download attempts exceeded 10. Exiting.", .{});
                return error.FailedToDownload;
            }
        },
        else => unreachable,
    };
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
fn downloadArchive(allocator: Allocator, version: api.ZigVersion, archive_fp: []const u8) !void {
    var archive = try downloadZigVersion(allocator, version.version.bootstrap.?.tarball, 0);
    defer allocator.free(archive);

    var archive_file = try openFile(archive_fp);
    defer archive_file.close();

    try archive_file.writer().writeAll(archive);
}

/// Decompress the `.tar.xz` file into a `.tar` file
fn decompressArchive(allocator: Allocator, archive_fp: []const u8, tarball_fp: []const u8) !void {
    var archive_file = try std.fs.openFileAbsolute(archive_fp, .{ .mode = .read_only });
    defer archive_file.close();

    var tarball = try std.compress.xz.decompress(allocator, archive_file.reader());
    defer tarball.deinit();

    var tarball_file = try openFile(tarball_fp);
    defer tarball_file.close();

    var tarball_reader = tarball.reader();

    var tarball_contents = try tarball_reader.readAllAlloc(allocator, size.fromMegabytes(400));
    defer allocator.free(tarball_contents);

    try tarball_file.writer().writeAll(tarball_contents);
}

fn cleanup(tmp_dir: []const u8) !void {
    std.log.info("Cleaning Temp Dir", .{});
    try std.fs.deleteTreeAbsolute(tmp_dir);
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

        var tmp_version_name = try concat(allocator, &[_][]const u8{ "tmp-", version_to_install.name });
        defer allocator.free(tmp_version_name);

        var tmp_version_dir_path = try createAndGetVersionDirectory(paths, tmp_version_name);
        defer allocator.free(tmp_version_dir_path);

        std.log.info("Downloading Archive", .{});
        var archive_fp = try paths.getTmpVersionFileWithExt(version_to_install.name, ".tar.xz");
        defer allocator.free(archive_fp);
        try downloadArchive(allocator, version_to_install, archive_fp);

        std.log.info("Decompressing Archive", .{});
        var tarball_fp = try paths.getTmpVersionFileWithExt(version_to_install.name, ".tar");
        defer allocator.free(tarball_fp);
        try decompressArchive(allocator, archive_fp, tarball_fp);

        std.log.info("Extracting Tarball", .{});
        _ = try std.ChildProcess.exec(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "tar", "-xf", tarball_fp, "--directory", tmp_version_dir_path },
        });

        // Gonna make the (potentially) stupid assumption that the
        // First directory in the extraction location
        // Is the Zig Version we just extracted

        var iterable_dir = try std.fs.openIterableDirAbsolute(tmp_version_dir_path, .{});
        var iterator = iterable_dir.iterate();
        while (try iterator.next()) |sub_path| {
            switch (sub_path.kind) {
                .Directory => {
                    var extract_path = try concat(allocator, &[_][]const u8{ tmp_version_dir_path, std.fs.path.sep_str, sub_path.name });
                    defer allocator.free(extract_path);

                    var version_path = try paths.getVersionPath(version_to_install.name);
                    defer allocator.free(version_path);
                    std.log.info("Moving Extracted Files to {s}", .{version_path});
                    try std.fs.renameAbsolute(extract_path, version_path);

                    std.log.info("{s}", .{sub_path.name});

                    break;
                },
                else => {},
            }
        }

        defer cleanToolchains(allocator, paths) catch |err| {
            std.log.err("Failed to delete {s}, {!}.", .{ tmp_version_dir_path, err });
        };
    };
}

fn cleanToolchains(allocator: Allocator, paths: *ZvmPaths) !void {
    var iter_dir = try std.fs.openIterableDirAbsolute(paths.toolchain_path, .{});
    defer iter_dir.close();
    var iterator = iter_dir.iterate();

    while (try iterator.next()) |sub_path| {
        if (std.mem.startsWith(u8, sub_path.name, "tmp-")) {
            const abs_path = try concat(allocator, &[_][]const u8{ paths.toolchain_path, std.fs.path.sep_str, sub_path.name });
            defer allocator.free(abs_path);
            std.log.info("Deleting {s}.", .{abs_path});

            try std.fs.deleteTreeAbsolute(abs_path);
        }
    }
}

/// Execute the given command
pub fn execute(allocator: Allocator, command: []const u8, args: [][]const u8) !void {
    var paths = try ZvmPaths.init(allocator);
    defer paths.deinit();

    return if (strEql(command, "list")) {
        return try listCommands(allocator, &paths, args);
    } else if (strEql(command, "clean")) {
        return try cleanToolchains(allocator, &paths);
    } else if (strEql(command, "install")) {
        return try installCommands(allocator, &paths, args);
    } else {
        usage();
    };
}
