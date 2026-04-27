extrn GetTickCount:proc
extrn GetStdHandle:proc
extrn WriteConsoleA:proc
extrn ReadConsoleA:proc
extrn ExitProcess:proc
extrn wsprintfA:proc

.data
    ; Chuỗi định dạng dồn chung 1 khối để tối ưu dung lượng
    fmt_out db "--- ASSEMBLY (PURE WIN32 API) ---", 10
            db "So nguyen to tim duoc (<%d): %d", 10
            db "Thoi gian chay: %d ms", 10
            db "Nhan Enter de thoat...", 10, 0
    
    limit EQU 10000000

.data?
    is_prime db 10000001 dup(?)
    str_buf  db 256 dup(?)       ; Buffer chứa chuỗi sau khi format
    written  dd ?                ; Biến hứng số byte đã ghi/đọc

.code
main proc
    ; Căn lề Stack 16-byte và cấp phát Shadow Space + Stack Arguments
    sub rsp, 48h

    ; Bắt đầu bấm giờ
    call GetTickCount
    mov r10, rax            ; r10 = start_time

    ; Khởi tạo mảng
    lea r8, is_prime
    mov rcx, limit
init_loop:
    mov byte ptr [r8 + rcx], 1
    dec rcx
    jns init_loop

    mov byte ptr [r8], 0
    mov byte ptr [r8 + 1], 0

    ; Sàng Eratosthenes
    mov r9, 2
outer_loop:
    mov rax, r9
    imul rax, r9
    cmp rax, limit
    jg count_primes

    cmp byte ptr [r8 + r9], 1
    jne next_p

    mov r11, rax
inner_loop:
    cmp r11, limit
    jg next_p
    mov byte ptr [r8 + r11], 0
    add r11, r9
    jmp inner_loop

next_p:
    inc r9
    jmp outer_loop

count_primes:
    xor r11, r11            ; r11 = count = 0
    mov rcx, limit
count_loop:
    cmp byte ptr [r8 + rcx], 1
    jne skip_inc
    inc r11
skip_inc:
    dec rcx
    jns count_loop

    ; Dừng bấm giờ
    call GetTickCount
    sub rax, r10
    mov r10, rax            ; r10 = duration (ms)

    ; Format chuỗi bằng wsprintfA (Tương đương sprintf của Windows)
    ; wsprintfA(str_buf, fmt_out, limit, count, duration)
    lea rcx, str_buf        ; Arg 1: Buffer đích
    lea rdx, fmt_out        ; Arg 2: Format string
    mov r8, limit           ; Arg 3: limit
    mov r9, r11             ; Arg 4: count
    mov [rsp + 20h], r10    ; Arg 5 (Đẩy vào Stack): duration
    call wsprintfA
    mov rbx, rax            ; Lưu chiều dài chuỗi trả về vào rbx

    ; Lấy Handle của Console Output (-11)
    mov rcx, -11
    call GetStdHandle
    mov rdi, rax            ; rdi = hConsoleOutput

    ; In ra màn hình bằng WriteConsoleA
    mov rcx, rdi            ; Arg 1: Handle
    lea rdx, str_buf        ; Arg 2: Buffer
    mov r8, rbx             ; Arg 3: Chiều dài (từ rbx)
    lea r9, written         ; Arg 4: Biến nhận số byte đã ghi
    mov qword ptr [rsp + 20h], 0 ; Arg 5: null
    call WriteConsoleA

    ; Lấy Handle của Console Input (-10) để chờ người dùng bấm phím
    mov rcx, -10
    call GetStdHandle
    
    ; Đọc 1 ký tự (Dừng màn hình)
    mov rcx, rax            ; Arg 1: Handle input
    lea rdx, str_buf        ; Arg 2: Buffer (dùng tạm str_buf)
    mov r8, 1               ; Arg 3: Đọc 1 ký tự
    lea r9, written         ; Arg 4: Biến nhận số byte đã đọc
    mov qword ptr [rsp + 20h], 0
    call ReadConsoleA

    ; Thoát chương trình
    xor ecx, ecx
    call ExitProcess
main endp
end