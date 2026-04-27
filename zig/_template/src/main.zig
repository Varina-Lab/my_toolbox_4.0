const std = @import("std");

// [TỐI ƯU CỰC ĐẠI - ZERO COST STARTUP]
// Khai báo mảng 625 KB ở vùng nhớ BSS toàn cục (Global).
// Windows sẽ tự động Zero-init (điền toàn số 0) vùng nhớ này khi nạp file EXE vào RAM.
// CPU không tốn bất kỳ 1 chu kỳ (cycle) nào để khởi tạo mảng này khi app chạy!
var is_comp: [78125]u64 = [_]u64{0} ** 78125;

pub fn main() !void {
    var timer = try std.time.Timer.start();
    
    const limit: usize = 10_000_000;
    const max_idx: usize = 4_999_998; // (10_000_000 - 3) / 2

    var i: usize = 0;
    while (true) {
        const p = 2 * i + 3;
        const p2 = p * p;
        if (p2 > limit) break;

        // BT (Bit Test): Lấy chỉ số khối (i >> 6) và chỉ số bit (i & 63)
        if ((is_comp[i >> 6] & (@as(u64, 1) << @as(u6, @intCast(i & 63)))) == 0) {
            var j: usize = (p2 - 3) / 2;
            
            // VÒNG LẶP LÕI (INNER LOOP): Cực kỳ Cache-Friendly
            while (j <= max_idx) : (j += p) {
                is_comp[j >> 6] |= @as(u64, 1) << @as(u6, @intCast(j & 63));
            }
        }
        i += 1;
    }

    // ĐẾM BẰNG PHẦN CỨNG: Gọi vi lệnh POPCNT
    var comp_count: usize = 0;
    for (&is_comp) |val| {
        comp_count += @popCount(val);
    }

    // Tổng nguyên tố = 1 (số 2) + Tổng số lẻ - Số hợp số
    const prime_count = 1 + (max_idx + 1) - comp_count;
    
    const duration = timer.read() / std.time.ns_per_ms;

    const stdout = std.io.getStdOut().writer();
    try stdout.print("--- ZIG (BITSET + BSS + POPCNT) ---\n", .{});
    try stdout.print("So nguyen to tim duoc (<{d}): {d}\n", .{ limit, prime_count });
    try stdout.print("Thoi gian chay: {d} ms\n", .{ duration });
    
    try stdout.print("Nhan Enter de thoat...\n", .{});
    var buf: [1024]u8 = undefined;
    _ = try std.io.getStdIn().reader().readUntilDelimiterOrEof(&buf, '\n');
}
