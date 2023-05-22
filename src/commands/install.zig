const std = @import("std");
const Allocator = std.mem.Allocator;

const ArgParser = @import("../ArgParser.zig").ArgParser;
const Commands = @import("./commands.zig").Commands;
const HttpClient = @import("../HttpClient.zig");
const Path = @import("../Path.zig");
const Cache = @import("../Cache.zig");
const ZigVersion = @import("../ZigVersion.zig");
const versions = @import("./versions.zig");
const qol = @import("../qol.zig");

fn downloadAndWriteZipFile(allocator: Allocator, paths: *const Path, version: ZigVersion) !void {
    var zip_file_path = try qol.concat(allocator, &[_][]const u8{ try paths.getTmpVersionPath(version.name), ".zip" });
    defer allocator.free(zip_file_path);

    std.log.info("Downloading {s}", .{version.version.download.?.tarball});
    var zip_contents = try HttpClient.get(allocator, version.version.download.?.tarball);
    defer allocator.free(zip_contents);
    std.log.info("Downloaded", .{});

    var zip_file = try Path.openFile(zip_file_path, .{ .mode = .write_only });
    defer zip_file.close();

    try zip_file.writeAll(zip_contents);
}

fn extractZip(allocator: Allocator, paths: *const Path, version: ZigVersion) !void {
    var tmp_version_path = try paths.getTmpVersionPath(version.name);
    defer allocator.free(tmp_version_path);
    if (!Path.pathExists(tmp_version_path)) try std.fs.makeDirAbsolute(tmp_version_path);

    var out_path = try qol.concat(allocator, &[_][]const u8{ "-o", tmp_version_path });
    defer allocator.free(out_path);
    std.log.info("Output Path: {s}", .{out_path});

    var zip_path = try qol.concat(allocator, &[_][]const u8{ try paths.getTmpVersionPath(version.name), ".zip" });
    defer allocator.free(zip_path);
    std.log.info("Zip Path: {s}", .{zip_path});

    std.log.info("Extracting {s}", .{zip_path});
    _ = std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "7z", "x", out_path, zip_path },
    }) catch |err| {
        if (err == error.FileNotFound) {
            std.log.err("7z not found on your system, please install it and add it to your Path.", .{});
            return error.MissingRequiredTool;
        }

        std.log.err("Failed to extract Zip {!}", .{err});
        return err;
    };
}

fn moveExtractedZipToToolchainPath(allocator: Allocator, paths: *const Path, version: ZigVersion) !void {
    std.log.info("Getting the temporary version path", .{});
    var outer = try paths.getTmpVersionPath(version.name);

    std.log.info("Opening {s}", .{outer});
    var outer_dir_iter = try std.fs.openIterableDirAbsolute(outer, .{});
    defer outer_dir_iter.close();

    var iter = outer_dir_iter.iterate();
    var first = (try iter.next()).?;

    var out_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    var full_path = try outer_dir_iter.dir.realpath(first.name, &out_buf);

    var full_path_iter_dir = try std.fs.openIterableDirAbsolute(full_path, .{});
    defer full_path_iter_dir.close();
    var full_path_iter = full_path_iter_dir.iterate();

    var version_path = try paths.getVersionPath(version.name);
    if (!Path.pathExists(version_path)) {
        try std.fs.makeDirAbsolute(version_path);
    } else {
        // Deleting and then re-making the directory so that it's empty
        try std.fs.deleteTreeAbsolute(version_path);
        try std.fs.makeDirAbsolute(version_path);
    }

    while (try full_path_iter.next()) |sub_path| {
        var full_old_path = try qol.concat(allocator, &[_][]const u8{ full_path, std.fs.path.sep_str, sub_path.name });
        defer allocator.free(full_old_path);
        var full_new_path = try qol.concat(allocator, &[_][]const u8{ version_path, std.fs.path.sep_str, sub_path.name });
        defer allocator.free(full_new_path);

        try std.fs.renameAbsolute(full_old_path, full_new_path);
    }
}

fn cleanUpTempDir(paths: *const Path) !void {
    var tmp_toolchain_path = try paths.getTmpToolchainPath();

    try std.fs.deleteTreeAbsolute(tmp_toolchain_path);
}

fn installVersion(allocator: Allocator, paths: *const Path, version: ZigVersion) !void {
    try downloadAndWriteZipFile(allocator, paths, version);
    try extractZip(allocator, paths, version);
    try moveExtractedZipToToolchainPath(allocator, paths, version);
    try cleanUpTempDir(paths);
    try versions.select(allocator, paths, version.name);
}

fn isAlreadyInstalled(allocator: Allocator, paths: *const Path, version: []const u8) !bool {
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

pub fn execute(allocator: Allocator, args: *ArgParser(Commands), paths: *const Path) !void {
    return if (args.numArgs() < 1)
        std.log.err("Missing Parameter: 'version'", .{})
    else {
        var target_version = try versions.getTargetVersion(allocator, args, paths);
        defer target_version.deinit(allocator);

        if (try versions.isAlreadyInstalled(allocator, paths, target_version.name)) {
            std.log.info("{s} is already installed.", .{target_version.name});
            try versions.select(allocator, paths, target_version.name);
            return;
        }

        std.log.info("Installing {s}", .{target_version.name});
        return installVersion(allocator, paths, target_version);
    };
}
