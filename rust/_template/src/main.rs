use std::time::Instant;

fn main() {
    let start = Instant::now();
    let limit = 10_000_000;
    
    // Khởi tạo mảng boolean, mặc định là true
    let mut is_prime = vec![true; limit + 1];
    is_prime[0] = false;
    is_prime[1] = false;

    let mut p = 2;
    while p * p <= limit {
        if is_prime[p] {
            let mut i = p * p;
            while i <= limit {
                is_prime[i] = false;
                i += p;
            }
        }
        p += 1;
    }

    let count = is_prime.iter().filter(|&&p| p).count();
    let duration = start.elapsed();

    println!("--- RUST ---");
    println!("So nguyen to tim duoc (<{}): {}", limit, count);
    println!("Thoi gian chay: {:?}", duration);
    
    // Dừng màn hình để xem kết quả khi nhấp đúp file exe
    println!("Nhan Enter de thoat...");
    let mut input = String::new();
    std::io::stdin().read_line(&mut input).unwrap();
}
