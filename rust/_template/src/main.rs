use std::time::Instant;

fn main() {
    let start = Instant::now();
    let limit: usize = 10_000_000;
    let max_idx: usize = (limit - 3) / 2; // 4_999_998
    
    // Ép RAM xuống 625 KB. Dùng Vec để cấp phát động nhanh (Calloc).
    // Mỗi u64 (64-bit) sẽ chứa trạng thái của 64 số lẻ. 0 = Nguyên tố, 1 = Hợp số.
    let qword_count = (max_idx / 64) + 1;
    let mut is_comp = vec![0u64; qword_count];

    let mut i = 0;
    loop {
        let p = 2 * i + 3;
        let p2 = p * p;
        if p2 > limit {
            break;
        }

        // BT (Bit Test): Kiểm tra xem bit thứ 'i' có phải là 0 không
        if (is_comp[i >> 6] & (1 << (i & 63))) == 0 {
            let mut j = (p2 - 3) / 2;
            // VÒNG LẶP LÕI: LLVM sẽ tự động biên dịch dòng này thành vi lệnh BTS
            while j <= max_idx {
                is_comp[j >> 6] |= 1 << (j & 63);
                j += p;
            }
        }
        i += 1;
    }

    // ĐẾM BẰNG PHẦN CỨNG (Hardware POPCNT):
    // count_ones() sẽ gọi thẳng vi lệnh popcnt của CPU, đếm 64 số trong 1 chu kỳ!
    let mut comp_count = 0;
    for &val in &is_comp {
        comp_count += val.count_ones() as usize;
    }

    // Tổng nguyên tố = 1 (số 2) + Tổng số lẻ - Số lượng hợp số
    let prime_count = 1 + (max_idx + 1) - comp_count;
    
    let duration = start.elapsed();

    println!("--- RUST (BITSET + POPCNT ALGORITHM) ---");
    println!("So nguyen to tim duoc (<{}): {}", limit, prime_count);
    println!("Thoi gian chay: {} ms", duration.as_millis());
    
    println!("Nhan Enter de thoat...");
    let mut input = String::new();
    std::io::stdin().read_line(&mut input).unwrap();
}
