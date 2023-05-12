const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const Path = @import("../Path.zig");
const ArgParser = @import("../ArgParser.zig").ArgParser;
const Commands = @import("./commands.zig").Commands;
const Cache = @import("../Cache.zig");
const usage = @import("./usage.zig").usage;

// pub const usage = @import("./usage.zig").usage;
// const listCommands = @import("./list.zig").listCommands;
// const installCommands = @import("./install.zig").installCommands;

/// Execute the given command
pub fn execute(allocator: Allocator, args: *ArgParser(Commands)) !void {
    const paths = try Path.init(allocator);
    defer paths.deinit();

    if (args.hasFlag("-rc") or args.hasFlag("--reload-cache")) {
        var cache_path = try paths.getCachePath();
        try Cache.forceReload(allocator, cache_path);

        allocator.free(cache_path);
    }

    if (args.command == null)
        return usage();

    switch (args.command.?) {
        .list => {
            try @import("./list.zig").execute(allocator, args, &paths);
        },
        .install => {
            try @import("./install.zig").execute(allocator, args, &paths);
        },
        else => {
            usage();
        },
    }
}
