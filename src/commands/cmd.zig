const std = @import("std");
const builtin = @import("builtin");

const ZigVersion = @import("../ZigVersion.zig");

const Path = @import("../Path.zig");
const size = @import("../size.zig");
const qol = @import("../qol.zig");

const File = std.fs.File;
const Allocator = std.mem.Allocator;

pub const usage = @import("./usage.zig").usage;
const listCommands = @import("./list.zig").listCommands;
const installCommands = @import("./install.zig").installCommands;

fn createAndGetVersionDirectory(paths: *Path, version: []const u8) ![]const u8 {
    var version_dir = try paths.getVersionPath(version);

    if (!Path.pathExists(version_dir)) {
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

    var request = try client.request(.GET, uri, .{ .allocator = allocator }, .{});
    defer request.deinit();

    var reader = request.reader();

    return reader.readAllAlloc(allocator, size.fromMegabytes(50)) catch |err| switch (err) {
        error.EndOfStream => {
            std.log.err("Unexpected End Of Stream. Trying again", .{});

            // try one more time, if it fails again it will panic

            if (depth < 10)
                return downloadZigVersion(allocator, url, depth + 1)
            else {
                std.log.err("Download attempts exceeded 10. Exiting.", .{});
                return error.DownloadError;
            }
        },
        else => return err,
    };
}

/// Return the Archive File Path
/// User must free memory
fn downloadArchive(allocator: Allocator, version: ZigVersion, archive_fp: []const u8) !void {
    var archive = try downloadZigVersion(allocator, version.version.src.?.tarball, 0);
    defer allocator.free(archive);

    var archive_file = try Path.openFile(archive_fp);
    defer archive_file.close();

    try archive_file.writer().writeAll(archive);
}

/// Decompress the `.tar.xz` file into a `.tar` file
fn decompressArchive(allocator: Allocator, archive_fp: []const u8, tarball_fp: []const u8) !void {
    var archive_file = try std.fs.openFileAbsolute(archive_fp, .{ .mode = .read_only });
    defer archive_file.close();

    var tarball = try std.compress.xz.decompress(allocator, archive_file.reader());
    defer tarball.deinit();

    var tarball_file = try Path.openFile(tarball_fp);
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

// fn installCommands(allocator: Allocator, paths: *Path, args: [][]const u8) !void {
//     return if (args.len < 1) {
//         std.log.err("Missing Parameter: 'version'", .{});
//     } else {
//         var target_version = args[0];

//         var all_versions = try ZigVersion.load(allocator, paths);
//         defer {
//             for (all_versions) |version|
//                 version.deinit(allocator);

//             allocator.free(all_versions);
//         }

//         var version_to_install = blk: {
//             for (all_versions) |version| {
//                 if (qol.strEql(target_version, version.name)) break :blk version;
//             }

//             std.log.err("Invalid Version: {s}", .{target_version});
//             return;
//         };

//         var tmp_version_name = try qol.concat(allocator, &[_][]const u8{ "tmp-", version_to_install.name });
//         defer allocator.free(tmp_version_name);

//         var tmp_version_dir_path = try createAndGetVersionDirectory(paths, tmp_version_name);
//         defer allocator.free(tmp_version_dir_path);

//         std.log.info("Downloading Archive", .{});
//         var archive_fp = try paths.getTmpVersionFileWithExt(version_to_install.name, ".tar.xz");
//         defer allocator.free(archive_fp);
//         try downloadArchive(allocator, version_to_install, archive_fp);

//         std.log.info("Decompressing Archive", .{});
//         var tarball_fp = try paths.getTmpVersionFileWithExt(version_to_install.name, ".tar");
//         defer allocator.free(tarball_fp);
//         try decompressArchive(allocator, archive_fp, tarball_fp);

//         std.log.info("Extracting Tarball", .{});
//         _ = try std.ChildProcess.exec(.{
//             .allocator = allocator,
//             .argv = &[_][]const u8{ "tar", "-xf", tarball_fp, "--directory", tmp_version_dir_path },
//         });

//         // Gonna make the (potentially) stupid assumption that the
//         // First directory in the extraction location
//         // Is the Zig Version we just extracted

//         var iterable_dir = try std.fs.openIterableDirAbsolute(tmp_version_dir_path, .{});
//         var iterator = iterable_dir.iterate();
//         while (try iterator.next()) |sub_path| {
//             switch (sub_path.kind) {
//                 .Directory => {
//                     var extract_path = try qol.concat(allocator, &[_][]const u8{ tmp_version_dir_path, std.fs.path.sep_str, sub_path.name });
//                     defer allocator.free(extract_path);

//                     var version_path = try paths.getVersionPath(version_to_install.name);
//                     defer allocator.free(version_path);
//                     std.log.info("Moving Extracted Files to {s}", .{version_path});
//                     try std.fs.renameAbsolute(extract_path, version_path);

//                     std.log.info("{s}", .{sub_path.name});

//                     break;
//                 },
//                 else => {},
//             }
//         }

//         defer cleanTmp(allocator, paths) catch |err| {
//             std.log.err("Failed to delete {s}, {!}.", .{ tmp_version_dir_path, err });
//         };
//     };
// }

fn cleanTmp(allocator: Allocator, paths: *Path) !void {
    var toolchain_path = try paths.getToolchainPath();
    defer allocator.free(toolchain_path);
    var iter_dir = try std.fs.openIterableDirAbsolute(toolchain_path, .{});
    defer iter_dir.close();
    var iterator = iter_dir.iterate();

    while (try iterator.next()) |sub_path| {
        if (std.mem.startsWith(u8, sub_path.name, "tmp-")) {
            const abs_path = try qol.concat(allocator, &[_][]const u8{ toolchain_path, std.fs.path.sep_str, sub_path.name });
            defer allocator.free(abs_path);
            std.log.info("Deleting {s}.", .{abs_path});

            try std.fs.deleteTreeAbsolute(abs_path);
        }
    }
}

/// Execute the given command
pub fn execute(allocator: Allocator, command: []const u8, args: [][]const u8) !void {
    var paths = try Path.init(allocator);
    defer paths.deinit();

    return if (qol.strEql(command, "list")) {
        return listCommands(allocator, &paths, args);
    } else if (qol.strEql(command, "clean")) {
        return cleanTmp(allocator, &paths);
    } else if (qol.strEql(command, "install")) {
        return installCommands(allocator, &paths, args);
    } else {
        usage();
    };
}
