const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const Path = @import("../Path.zig");
const Args = @import("../Args.zig");
const qol = @import("../qol.zig");

pub const usage = @import("./usage.zig").usage;
const listCommands = @import("./list.zig").listCommands;
const installCommands = @import("./install.zig").installCommands;

/// Execute the given command
pub fn execute(allocator: Allocator, args: *Args) !void {
    var main_command = args.commands.items[0];

    const paths = try Path.init(allocator);
    defer paths.deinit();

    for (args.flags.items) |flag| std.log.info("Flag: {s}", .{flag});

    return if (qol.strEql(main_command, "list"))
        listCommands(allocator, args, &paths)
    else if (qol.strEql(main_command, "install"))
        installCommands(allocator, args, &paths)
    else
        usage();
}
