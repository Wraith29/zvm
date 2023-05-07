const std = @import("std");
const Allocator = std.mem.Allocator;
const StringList = @import("./List.zig").List([]const u8);
const qol = @import("./qol.zig");

const Args = @This();

commands: StringList,
flags: StringList,

pub fn init(allocator: Allocator) Args {
    var commands = StringList.init(allocator);
    var flags = StringList.init(allocator);

    return .{ .commands = commands, .flags = flags };
}

pub fn deinit(self: *Args) void {
    self.commands.deinit();
    self.flags.deinit();
}

pub fn parse(self: *Args, args: [][]const u8) !void {
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "-") or std.mem.startsWith(u8, arg, "--")) {
            try self.flags.append(arg);
            continue;
        }
        try self.commands.append(arg);
    }
}

pub fn lenCommands(self: *Args) usize {
    return self.commands.len();
}

pub fn hasCommand(self: *Args, cmd: []const u8) bool {
    return self.commands.contains(cmd, qol.strEql);
}

pub fn lenFlags(self: *Args) usize {
    return self.flags.len();
}

pub fn hasFlag(self: *Args, flag: []const u8) bool {
    return self.flags.contains(flag, qol.strEql);
}
