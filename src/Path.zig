const std = @import("std");
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

fn pathExists(path: []const u8) bool {
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

pub fn getVersionPath(self: *const Path, version: []const u8) ![]const u8 {
    var toolchain_path = try self.getToolchainPath();
    defer self.allocator.free(toolchain_path);

    return try getSubpath(self.allocator, toolchain_path, version);
}

pub fn getTmpVersionPath(self: *const Path, version: []const u8) ![]const u8 {
    var tmp_version = try std.mem.concat(self.allocator, u8, &[_][]const u8{ "tmp-", version });

    return try self.getVersionPath(tmp_version);
}

pub fn getToolchainPath(self: *const Path) ![]const u8 {
    return try getSubpath(self.allocator, self.base_path, "toolchains");
}

pub fn getCachePath(self: *const Path) ![]const u8 {
    return try getSubpath(self.allocator, self.base_path, "cache.json");
}
