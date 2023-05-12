const std = @import("std");
const Allocator = std.mem.Allocator;
const StringList = @import("./list.zig").List([]const u8);
const qol = @import("./qol.zig");

/// T should be an enum
/// which is the commands
pub fn ArgParser(comptime T: type) type {
    return struct {
        const Self = @This();

        valid_commands: []const []const u8,
        command: ?T,
        args: StringList,
        flags: StringList,

        pub fn init(allocator: Allocator, valid_commands: []const []const u8) Self {
            var args = StringList.init(allocator);
            var flags = StringList.init(allocator);

            return .{
                .valid_commands = valid_commands,
                .command = null,
                .args = args,
                .flags = flags,
            };
        }

        pub fn deinit(self: *Self) void {
            self.args.deinit();
            self.flags.deinit();
        }

        fn isValidCommand(self: *Self, cmd: []const u8) bool {
            for (self.valid_commands) |valid_cmd| {
                if (std.mem.eql(u8, cmd, valid_cmd)) return true;
            }

            return false;
        }

        pub fn parse(self: *Self, args: []const []const u8) !void {
            var cmd_found = false;

            for (args) |arg| {
                if (std.mem.startsWith(u8, arg, "-") or std.mem.startsWith(u8, arg, "--")) {
                    try self.flags.append(arg);
                    continue;
                }

                if (!cmd_found) {
                    if (!self.isValidCommand(arg)) return error.InvalidCommand;
                    if (!@hasDecl(T, "fromString")) @compileError("Missing `fromString` method on `T`");

                    self.command = T.fromString(arg);
                    cmd_found = true;
                    continue;
                }

                try self.args.append(arg);
            }

            if (!cmd_found) self.command = null;
        }

        pub fn hasFlag(self: *Self, flag: []const u8) bool {
            return self.flags.contains(flag, qol.strEql);
        }

        pub fn numArgs(self: *Self) usize {
            return self.args.len();
        }
    };
}
