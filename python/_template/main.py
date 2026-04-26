import time

def main():
    start_time = time.perf_counter()
    limit = 10_000_000
    
    is_prime = [True] * (limit + 1)
    is_prime[0] = False
    is_prime[1] = False
    
    p = 2
    while p * p <= limit:
        if is_prime[p]:
            for i in range(p * p, limit + 1, p):
                is_prime[i] = False
        p += 1
        
    count = sum(is_prime)
    end_time = time.perf_counter()
    
    duration_ms = int((end_time - start_time) * 1000)
    
    print("--- PYTHON (Nuitka Compiled) ---")
    print(f"So nguyen to tim duoc (<{limit}): {count}")
    print(f"Thoi gian chay: {duration_ms} ms")
    print("Nhan Enter de thoat...")
    input()

if __name__ == "__main__":
    main()
