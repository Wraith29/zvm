const std = @import("std");

pub inline fn fromMegabytes(mb: f64) f64 {
    return mb * 1024 * 1024;
}

pub inline fn toMegabytes(bites: f64) f64 {
    return bites / 1024 / 1024;
}
