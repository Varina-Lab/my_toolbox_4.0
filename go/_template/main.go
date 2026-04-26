package main

import (
	"fmt"
	"time"
)

func main() {
	start := time.Now()
	const limit = 10000000
	
	isPrime := make([]bool, limit+1)
	for i := range isPrime {
		isPrime[i] = true
	}
	isPrime[0], isPrime[1] = false, false

	for p := 2; p*p <= limit; p++ {
		if isPrime[p] {
			for i := p * p; i <= limit; i += p {
				isPrime[i] = false
			}
		}
	}

	count := 0
	for _, p := range isPrime {
		if p {
			count++
		}
	}
	
	duration := time.Since(start)

	fmt.Printf("--- GO ---\n")
	fmt.Printf("So nguyen to tim duoc (<%d): %d\n", limit, count)
	fmt.Printf("Thoi gian chay: %v\n", duration)
	
	fmt.Println("Nhan Enter de thoat...")
	fmt.Scanln()
}
