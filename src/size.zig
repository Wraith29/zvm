const std = @import("std");

pub inline fn fromMegabytes(mb: f64) f64 {
    return mb * 1024 * 1024;
}

pub inline fn toMegabytes(bytes: f64) f64 {
    return bytes / 1024 / 1024;
}
