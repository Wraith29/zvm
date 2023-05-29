const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const Path = @import("../Path.zig");
const ArgParser = @import("../ArgParser.zig").ArgParser;
const Commands = @import("./commands.zig").Commands;
const Cache = @import("../Cache.zig");
const usage = @import("./usage.zig").usage;
const list = @import("./list.zig");
const install = @import("./install.zig");
const versions = @import("./versions.zig");
const current = @import("./current.zig");

/// Execute the given command
pub fn execute(allocator: Allocator, args: *ArgParser(Commands), paths: *const Path) !void {
    if (args.hasFlag("-rc") or args.hasFlag("--reload-cache")) {
        var cache_path = try paths.getFilePath("cache.json");
        try Cache.forceReload(allocator, cache_path);

        allocator.free(cache_path);
    }

    if (args.command == null)
        return usage();

    switch (args.command.?) {
        .list => {
            try list.execute(allocator, args, paths);
        },
        .install => {
            try install.execute(allocator, args, paths);
        },
        .latest => {
            try install.latest(allocator, paths);
        },
        .select => {
            try versions.execute(allocator, args, paths);
        },
        .current => {
            try current.execute(allocator);
        },
        .delete => {
            try versions.delete(allocator, args, paths);
        },
        else => {
            usage();
        },
    }
}
