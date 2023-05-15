const std = @import("std");

pub const Commands = enum {
    list,
    install,
    usage,
    select,
    unknown,

    pub fn fromString(string: []const u8) Commands {
        return if (std.mem.eql(u8, string, "install"))
            .install
        else if (std.mem.eql(u8, string, "list"))
            .list
        else if (std.mem.eql(u8, string, "usage"))
            .usage
        else if (std.mem.eql(u8, string, "use") or std.mem.eql(u8, string, "select"))
            .select
        else
            .unknown;
    }
};
