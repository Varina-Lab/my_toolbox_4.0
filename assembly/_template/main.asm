extrn printf:proc
extrn GetTickCount:proc
extrn getchar:proc
extrn ExitProcess:proc

.data
    ; Các chuỗi định dạng (Format strings) để in ra màn hình
    fmt_hdr   db "--- ASSEMBLY (MASM64) ---", 10, 0
    fmt_res   db "So nguyen to tim duoc (<%d): %d", 10, 0
    fmt_time  db "Thoi gian chay: %d ms", 10, 0
    fmt_pause db "Nhan Enter de thoat...", 10, 0

    limit EQU 10000000

.data?
    ; Khai báo mảng 10 triệu byte chưa khởi tạo (nằm trong RAM, không làm nặng file exe)
    is_prime db 10000001 dup(?)

.code
main proc
    ; Căn lề Stack 16-byte và cấp phát Shadow Space (Chuẩn gọi hàm x64 của Windows)
    sub rsp, 28h

    ; Lấy thời gian bắt đầu (ms)
    call GetTickCount
    mov r10, rax            ; r10 = start_time

    ; Khởi tạo mảng is_prime = 1 (True)
    lea r8, is_prime
    mov rcx, limit
init_loop:
    mov byte ptr [r8 + rcx], 1
    dec rcx
    jns init_loop           ; Lặp cho đến khi rcx < 0

    ; is_prime[0] và is_prime[1] = 0 (False)
    mov byte ptr [r8], 0
    mov byte ptr [r8 + 1], 0

    ; Thuật toán Sàng nguyên tố (Sieve of Eratosthenes)
    mov r9, 2               ; r9 = p = 2
outer_loop:
    mov rax, r9
    imul rax, r9            ; rax = p * p
    cmp rax, limit
    jg count_primes         ; Nếu p*p > limit thì dừng sàng

    cmp byte ptr [r8 + r9], 1
    jne next_p

    ; Vòng lặp xóa các bội số (inner loop)
    mov r11, rax            ; r11 = i = p * p
inner_loop:
    cmp r11, limit
    jg next_p
    mov byte ptr [r8 + r11], 0  ; is_prime[i] = 0
    add r11, r9             ; i += p
    jmp inner_loop

next_p:
    inc r9                  ; p++
    jmp outer_loop

count_primes:
    ; Đếm số lượng số nguyên tố
    xor r11, r11            ; r11 = count = 0
    mov rcx, limit
count_loop:
    cmp byte ptr [r8 + rcx], 1
    jne skip_inc
    inc r11                 ; count++
skip_inc:
    dec rcx
    jns count_loop

    ; Tính thời gian chạy
    call GetTickCount
    sub rax, r10            ; rax = Hiện tại - Bắt đầu
    mov r10, rax            ; Lưu thời gian (ms) vào r10

    ; In Header
    lea rcx, fmt_hdr
    call printf

    ; In Kết quả (printf("%s", limit, count))
    lea rcx, fmt_res
    mov rdx, limit
    mov r8, r11
    call printf

    ; In Thời gian
    lea rcx, fmt_time
    mov rdx, r10
    call printf

    ; Dừng màn hình chờ người dùng
    lea rcx, fmt_pause
    call printf
    call getchar

    ; Thoát chương trình sạch sẽ
    xor ecx, ecx
    call ExitProcess
main endp
end
