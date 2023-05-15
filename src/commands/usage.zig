const _info = @import("std").log.info;

fn info(comptime msg: []const u8) void {
    _info(msg, .{});
}

pub fn usage() void {
    info(
        \\
        \\Usage:
        \\  zvm help                   - display this message
        \\  zvm list [-i, --installed] - list available versions
        \\  zvm install <version>      - install the specified version
        \\  zvm select <version>       - select the specified version
        \\
        \\Flags:
        \\  -rc --reload-cache         - forces a cache reload (default: 1 day)
    );
}
