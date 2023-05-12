const std = @import("std");

pub const Commands = enum {
    list,
    install,
    usage,
    unknown,

    pub fn fromString(string: []const u8) Commands {
        return if (std.mem.eql(u8, string, "install"))
            .install
        else if (std.mem.eql(u8, string, "list"))
            .list
        else if (std.mem.eql(u8, string, "usage"))
            .usage
        else
            .unknown;
    }
};
