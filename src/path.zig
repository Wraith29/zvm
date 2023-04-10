const std = @import("std");

const Allocator = std.mem.Allocator;

/// Absolute Path
pub fn dirExists(path: []const u8) bool {
    std.fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

fn getSubpath(allocator: Allocator, base: []const u8, sub: []const u8) ![]const u8 {
    return try std.mem.concat(allocator, u8, &[_][]const u8{ base, std.fs.path.sep_str, sub });
}

pub const ZvmPaths = struct {
    allocator: Allocator,
    base_path: []const u8,
    toolchain_path: []const u8,

    pub fn init(allocator: Allocator) !ZvmPaths {
        var base_path = try std.fs.getAppDataDir(allocator, ".zvm");
        if (!dirExists(base_path)) try std.fs.makeDirAbsolute(base_path);

        var toolchain_path = try getSubpath(allocator, base_path, "toolchains");
        if (!dirExists(toolchain_path)) try std.fs.makeDirAbsolute(toolchain_path);

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
};
