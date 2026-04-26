const std = @import("std");

pub fn main() !void {
    const limit: usize = 10_000_000;
    
    // Dùng ArenaAllocator để cấp phát bộ nhớ cực nhanh
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var is_prime = try allocator.alloc(bool, limit + 1);
    @memset(is_prime, true);
    is_prime[0] = false;
    is_prime[1] = false;

    const start_time = std.time.milliTimestamp();

    var p: usize = 2;
    while (p * p <= limit) : (p += 1) {
        if (is_prime[p]) {
            var i: usize = p * p;
            while (i <= limit) : (i += p) {
                is_prime[i] = false;
            }
        }
    }

    var count: usize = 0;
    for (is_prime) |prime| {
        if (prime) count += 1;
    }

    const end_time = std.time.milliTimestamp();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("--- ZIG ---\n", .{});
    try stdout.print("So nguyen to tim duoc (<{d}): {d}\n", .{ limit, count });
    try stdout.print("Thoi gian chay: {d} ms\n", .{ end_time - start_time });
    
    try stdout.print("Nhan Enter de thoat...\n", .{});
    var buf: [1]u8 = undefined;
    _ = try std.io.getStdIn().reader().read(&buf);
}
