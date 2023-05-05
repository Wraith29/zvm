const builtin = @import("builtin");

pub fn getComputerArchitecture() ![]const u8 {
    const arch = switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        else => return error.UnsupportedArchitecture,
    };

    const os = switch (builtin.os.tag) {
        .windows => "windows",
        else => return error.UnsupportedOs,
    };

    return arch ++ "-" ++ os;
}
