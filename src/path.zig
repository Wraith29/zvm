const std = @import("std");

const Allocator = std.mem.Allocator;

/// Absolute Path
pub fn pathExists(path: []const u8) bool {
    std.fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

fn getSubpath(allocator: Allocator, base: []const u8, sub: []const u8) ![]const u8 {
    return try std.mem.concat(allocator, u8, &[_][]const u8{ base, std.fs.path.sep_str, sub });
}

pub fn openFile(fp: []const u8, flags: std.fs.File.OpenFlags) !std.fs.File {
    std.fs.accessAbsolute(fp, flags) catch {
        return try std.fs.createFileAbsolute(fp, .{ .read = true });
    };

    return try std.fs.openFileAbsolute(fp, flags);
}

pub const ZvmPaths = struct {
    allocator: Allocator,
    base_path: []const u8,
    toolchain_path: []const u8,
    version_path: ?[]const u8 = null,

    pub fn init(allocator: Allocator) !ZvmPaths {
        var base_path = try std.fs.getAppDataDir(allocator, ".zvm");
        if (!pathExists(base_path)) try std.fs.makeDirAbsolute(base_path);

        var toolchain_path = try getSubpath(allocator, base_path, "toolchains");
        if (!pathExists(toolchain_path)) try std.fs.makeDirAbsolute(toolchain_path);

        return ZvmPaths{
            .allocator = allocator,
            .base_path = base_path,
            .toolchain_path = toolchain_path,
        };
    }

    pub fn deinit(self: *ZvmPaths) void {
        self.allocator.free(self.base_path);
        self.allocator.free(self.toolchain_path);
    }

    pub fn getCachePath(self: *ZvmPaths) ![]const u8 {
        return try std.mem.concat(self.allocator, u8, &[_][]const u8{
            self.base_path,
            std.fs.path.sep_str,
            "cache.json",
        });
    }
};
