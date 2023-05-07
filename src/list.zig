const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn List(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,
        items: []T,
        index: usize,
        capacity: usize,

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                .items = &[_]T{},
                .index = 0,
                .capacity = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
        }

        pub fn append(self: *Self, value: T) !void {
            if (self.index >= self.capacity) {
                try self.increaseCapacity();
            }

            self.items[self.index] = value;
            self.index += 1;
        }

        pub fn contains(self: *Self, value: T, eql_fn: *const fn (T, T) bool) bool {
            for (self.items) |item| {
                if (eql_fn(value, item)) return true;
            }
            return false;
        }

        pub fn len(self: *Self) usize {
            return self.index;
        }

        fn increaseCapacity(self: *Self) !void {
            self.capacity = try std.math.ceilPowerOfTwo(usize, self.capacity + 1);
            self.items = try self.allocator.realloc(self.items, self.capacity);
        }
    };
}

test "List - Basic" {
    const allocator = std.testing.allocator;

    var my_list = List(u8).init(allocator);
    defer my_list.deinit();

    try my_list.append(1);
}
