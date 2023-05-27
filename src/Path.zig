const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const Path = @This();

allocator: Allocator,
base_path: []const u8,

fn getSubpath(allocator: Allocator, base: []const u8, child: []const u8) ![]const u8 {
    return std.mem.concat(allocator, u8, &[_][]const u8{
        base,
        std.fs.path.sep_str,
        child,
    });
}

pub fn pathExists(path: []const u8) bool {
    std.fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

pub fn openFile(file_path: []const u8, flags: std.fs.File.OpenFlags) !std.fs.File {
    if (!pathExists(file_path)) {
        return try std.fs.createFileAbsolute(file_path, .{ .read = true });
    }

    return try std.fs.openFileAbsolute(file_path, flags);
}

pub fn init(allocator: Allocator) !Path {
    var base = try std.fs.getAppDataDir(allocator, ".zvm");
    if (!pathExists(base)) try std.fs.makeDirAbsolute(base);

    return Path{
        .allocator = allocator,
        .base_path = base,
    };
}

pub fn deinit(self: *const Path) void {
    self.allocator.free(self.base_path);
}

pub fn setup(self: *const Path) !void {
    var toolchain_path = try self.getToolchainPath();
    if (!pathExists(toolchain_path)) try std.fs.makeDirAbsolute(toolchain_path);
    self.allocator.free(toolchain_path);

    var cache_path = try self.getFilePath("cache.json");
    if (!pathExists(cache_path)) (try std.fs.createFileAbsolute(cache_path, .{})).close();
    self.allocator.free(cache_path);

    var settings_path = try self.getFilePath("settings.json");
    if (!pathExists(settings_path)) (try std.fs.createFileAbsolute(settings_path, .{})).close();
    self.allocator.free(settings_path);

    var sym_path = try self.getFilePath("zig");
    defer self.allocator.free(sym_path);
    if (!pathExists(sym_path)) try std.fs.makeDirAbsolute(sym_path);
    if (builtin.os.tag == .windows) {
        var command_string = std.ArrayList(u8).init(self.allocator);

        try std.fmt.format(
            command_string.writer(),
            "{{[System.Environment]::SetEnvironmentVariable(\"ZIG_PATH\", \"{s}\", \"User\")}}",
            .{sym_path},
        );

        var cmd = try command_string.toOwnedSlice();

        std.log.info("Creating ZIG_PATH Environment Variable", .{});
        _ = try std.ChildProcess.exec(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "pwsh", "-Command", cmd },
        });
    }
}

pub fn getFilePath(self: *const Path, file_name: []const u8) ![]const u8 {
    return try getSubpath(self.allocator, self.base_path, file_name);
}

pub fn getVersionPath(self: *const Path, version: []const u8) ![]const u8 {
    var toolchain_path = try self.getToolchainPath();
    defer self.allocator.free(toolchain_path);

    return try getSubpath(self.allocator, toolchain_path, version);
}

pub fn getTmpVersionPath(self: *const Path, version: []const u8) ![]const u8 {
    var tmp_version = try std.mem.concat(self.allocator, u8, &[_][]const u8{ "tmp-", version });
    defer self.allocator.free(tmp_version);
    var tmp_toolchain_path = try self.getTmpToolchainPath();
    defer self.allocator.free(tmp_toolchain_path);

    return try getSubpath(self.allocator, tmp_toolchain_path, tmp_version);
}

pub fn getToolchainPath(self: *const Path) ![]const u8 {
    return try getSubpath(self.allocator, self.base_path, "toolchains");
}

pub fn getTmpToolchainPath(self: *const Path) ![]const u8 {
    var tmp = try getSubpath(self.allocator, self.base_path, "tmp-toolchains");

    if (!pathExists(tmp)) {
        try std.fs.makeDirAbsolute(tmp);
    }

    return tmp;
}
