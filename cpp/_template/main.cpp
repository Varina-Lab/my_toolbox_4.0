#include <iostream>
#include <vector>
#include <chrono>
#include <string>

int main() {
    auto start = std::chrono::high_resolution_clock::now();
    const int limit = 10000000;
    
    std::vector<char> is_prime(limit + 1, 1);
    is_prime[0] = 0;
    is_prime[1] = 0;

    for (int p = 2; p * p <= limit; p++) {
        if (is_prime[p]) {
            for (int i = p * p; i <= limit; i += p)
                is_prime[i] = 0;
        }
    }

    int count = 0;
    for (int i = 0; i <= limit; i++) {
        if (is_prime[i]) count++;
    }

    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end - start);

    std::cout << "--- C++ ---\n";
    std::cout << "So nguyen to tim duoc (<" << limit << "): " << count << "\n";
    std::cout << "Thoi gian chay: " << duration.count() << " ms\n";
    std::cout << "Nhan Enter de thoat...\n";
    
    std::string dummy;
    std::getline(std::cin, dummy);
    return 0;
}
