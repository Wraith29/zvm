const std = @import("std");

pub const Commands = enum {
    list,
    install,
    usage,
    select,
    current,
    latest,
    unknown,

    pub fn fromString(command: []const u8) Commands {
        return if (std.mem.eql(u8, command, "install"))
            .install
        else if (std.mem.eql(u8, command, "list"))
            .list
        else if (std.mem.eql(u8, command, "usage"))
            .usage
        else if (std.mem.eql(u8, command, "use") or std.mem.eql(u8, command, "select"))
            .select
        else if (std.mem.eql(u8, command, "current"))
            .current
        else if (std.mem.eql(u8, command, "latest"))
            .latest
        else
            .unknown;
    }
};
