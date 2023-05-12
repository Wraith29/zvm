const std = @import("std");
const Allocator = std.mem.Allocator;

const ArgParser = @import("../ArgParser.zig").ArgParser;
const Commands = @import("./commands.zig").Commands;
const HttpClient = @import("../HttpClient.zig");
const Path = @import("../Path.zig");
const Cache = @import("../Cache.zig");
const ZigVersion = @import("../ZigVersion.zig");
const qol = @import("../qol.zig");

fn downloadAndWriteZipFile(allocator: Allocator, paths: *const Path, version: ZigVersion) !void {
    var zip_file_path = try qol.concat(allocator, &[_][]const u8{ try paths.getTmpVersionPath(version.name), ".zip" });
    std.log.info("path: {s}", .{zip_file_path});

    std.log.info("Attempting to download: {s}", .{version.version.download.?.tarball});
    var zip_contents = try HttpClient.get(allocator, version.version.download.?.tarball);
    defer allocator.free(zip_contents);

    var zip_file = try Path.openFile(zip_file_path, .{ .mode = .write_only });
    defer zip_file.close();

    std.log.info("Writing Zip Contents To {s}", .{zip_file_path});
    try zip_file.writeAll(zip_contents);
}

fn extractZip(allocator: Allocator, paths: *const Path, version: ZigVersion) !void {
    var out_path = try qol.concat(allocator, &[_][]const u8{ "-o", try paths.getTmpVersionPath(version.name) });
    defer allocator.free(out_path);
    std.log.info("Out Flag: `{s}`", .{out_path});

    var zip_path = try qol.concat(allocator, &[_][]const u8{ try paths.getTmpVersionPath(version.name), ".zip" });
    defer allocator.free(zip_path);
    std.log.info("Extracting Zip At {s}", .{zip_path});

    _ = try std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "7z", "x", out_path, zip_path },
    });
}

fn moveExtractedZipToToolchainPath(allocator: Allocator, paths: *const Path, version: ZigVersion) !void {
    var outer = try paths.getTmpVersionPath(version.name);

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
    std.log.info("Downloading Zip", .{});
    try downloadAndWriteZipFile(allocator, paths, version);
    std.log.info("Extracting Zip", .{});
    try extractZip(allocator, paths, version);
    std.log.info("Moving Zip Out", .{});
    try moveExtractedZipToToolchainPath(allocator, paths, version);
    std.log.info("Removing Temporary Files", .{});
    try cleanUpTempDir(paths);

    var new_zig_path = try paths.getVersionPath(version.name);

    var sym_link_path = try qol.concat(
        allocator,
        &[_][]const u8{
            paths.base_path,
            std.fs.path.sep_str,
            "zig",
        },
    );

    try std.fs.symLinkAbsolute(new_zig_path, sym_link_path, .{ .is_directory = true });
}

pub fn execute(allocator: Allocator, args: *ArgParser(Commands), paths: *const Path) !void {
    return if (args.numArgs() < 1)
        std.log.err("Missing Parameter: 'version'", .{})
    else {
        var target_version = args.args.items[0];

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
