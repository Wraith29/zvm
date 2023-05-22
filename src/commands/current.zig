const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const Commands = @import("./commands.zig").Commands;
const ArgParser = @import("../ArgParser.zig").ArgParser;
const Path = @import("../Path.zig");

pub fn execute(allocator: Allocator, args: *ArgParser(Commands), paths: *const Path) !void {
    _ = paths;
    _ = args;
    _ = allocator;
}
