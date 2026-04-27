extrn GetStdHandle:proc
extrn WriteConsoleA:proc
extrn ReadConsoleA:proc
extrn ExitProcess:proc
extrn QueryPerformanceCounter:proc
extrn QueryPerformanceFrequency:proc

.data
    limit EQU 10000000

    ; Các chuỗi kết thúc bằng Null (0) để copy siêu tốc
    msg_header db "--- ASSEMBLY (EXTREME OPTIMIZED) ---", 10, "So nguyen to tim duoc (<10000000): ", 0
    msg_time   db 10, "Thoi gian chay: ", 0
    msg_ms     db " ms", 10, "Nhan Enter de thoat...", 10, 0

.data?
    is_prime db 10000001 dup(?)
    str_buf  db 512 dup(?)
    freq     dq ?
    start_t  dq ?
    end_t    dq ?
    written  dd ?

.code
main proc
    ; Chuẩn gọi hàm x64: Cấp phát 72 bytes cho Shadow Space và Stack Alignment
    sub rsp, 48h

    ; 1. Lấy tần số đồng hồ CPU (Microseconds precision)
    lea rcx, freq
    call QueryPerformanceFrequency

    ; 2. Bắt đầu đếm giờ
    lea rcx, start_t
    call QueryPerformanceCounter

    ; 3. [TỐI ƯU CỰC ĐẠI]: Khởi tạo 10 triệu byte bằng vi lệnh phần cứng (REP STOSB)
    lea rdi, is_prime
    mov rcx, limit + 1
    mov al, 1
    rep stosb                   ; Điền toàn bộ mảng bằng 1 siêu tốc

    ; Gán 0 và 1 không phải là số nguyên tố
    lea r8, is_prime
    mov byte ptr [r8], 0
    mov byte ptr [r8 + 1], 0

    ; 4. [TỐI ƯU LÔ-GIC]: Thuật toán Sàng nguyên tố
    mov r9, 2                   ; r9 = p = 2
outer_loop:
    mov rax, r9
    imul rax, r9                ; rax = p * p
    cmp rax, limit
    jg count_primes             ; p * p > limit => Dừng sàng

    cmp byte ptr [r8 + r9], 0
    je next_p                   ; Bỏ qua nếu không phải số nguyên tố

    mov r11, rax                ; r11 = i = p * p
inner_loop:                     ; Vòng lặp tối giản (ít chỉ thị nhất có thể)
    mov byte ptr [r8 + r11], 0  ; is_prime[i] = 0
    add r11, r9                 ; i += p
    cmp r11, limit
    jle inner_loop              ; Rẽ nhánh hiệu năng cao

next_p:
    inc r9                      ; p++
    jmp outer_loop

count_primes:
    ; 5. [TỐI ƯU ĐẾM]: Vì mảng chỉ chứa 0 và 1, thay vì so sánh, ta CỘNG DỒN thẳng vào bộ đếm
    xor r11, r11                ; r11 = count = 0
    lea rsi, is_prime
    mov rcx, limit + 1
count_loop:
    movzx rax, byte ptr [rsi]   ; Đọc 1 byte không làm rác thanh ghi
    add r11, rax                ; count += giá trị byte (0 hoặc 1)
    inc rsi
    dec rcx
    jnz count_loop

    ; 6. Dừng đếm giờ
    lea rcx, end_t
    call QueryPerformanceCounter

    ; 7. Tính toán mili-giây: (end - start) * 1000 / freq
    mov rax, end_t
    sub rax, start_t
    mov rcx, 1000
    mul rcx                     ; rdx:rax = rax * 1000
    div qword ptr [freq]        ; rax = rax / freq
    mov r10, rax                ; r10 = Thời gian chạy (ms)

    ; 8. [ZERO-DEPENDENCY]: Tự copy và format chuỗi không cần C-Runtime
    lea rdi, str_buf
    
    lea rsi, msg_header
    call copy_string            ; In Header
    
    mov rax, r11
    call itoa                   ; In Số lượng nguyên tố
    
    lea rsi, msg_time
    call copy_string            ; In chữ "Thoi gian chay: "
    
    mov rax, r10
    call itoa                   ; In số Mili-giây
    
    lea rsi, msg_ms
    call copy_string            ; In chữ " ms"

    ; Tính toán chiều dài chuỗi cuối cùng
    lea rax, str_buf
    sub rdi, rax
    mov r12, rdi                ; r12 = Chiều dài chuỗi cần in

    ; 9. In ra Terminal (Win32 API: WriteConsole)
    mov rcx, -11                ; STD_OUTPUT_HANDLE
    call GetStdHandle
    
    mov rcx, rax                ; hConsoleOutput
    lea rdx, str_buf            ; lpBuffer
    mov r8, r12                 ; nNumberOfCharsToWrite
    lea r9, written             ; lpNumberOfCharsWritten
    mov qword ptr [rsp + 20h], 0
    call WriteConsoleA

    ; 10. Chờ người dùng bấm phím (ReadConsole)
    mov rcx, -10                ; STD_INPUT_HANDLE
    call GetStdHandle
    
    mov rcx, rax
    lea rdx, str_buf
    mov r8, 1
    lea r9, written
    mov qword ptr [rsp + 20h], 0
    call ReadConsoleA

    ; 11. Thoát sạch sẽ
    xor ecx, ecx
    call ExitProcess
main endp

; ---------------------------------------------------------
; Hàm phụ trợ: Copy chuỗi (Tương đương strcpy)
; Input: rsi = Chuỗi nguồn (kết thúc bằng 0), rdi = Chuỗi đích
; Output: rdi = Điểm cuối của chuỗi đích
; ---------------------------------------------------------
copy_string proc
.L_copy:
    mov al, [rsi]
    test al, al
    jz .L_done
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .L_copy
.L_done:
    ret
copy_string endp

; ---------------------------------------------------------
; Hàm phụ trợ: Số nguyên sang Chuỗi (Tương đương itoa)
; Input: rax = Số cần in, rdi = Chuỗi đích
; Output: rdi = Điểm cuối của chuỗi đích sau khi in số
; ---------------------------------------------------------
itoa proc
    mov rbx, 10
    mov r8, rsp                 ; Lưu đỉnh Stack
    sub rsp, 32                 ; Mượn Stack làm bộ đệm lật ngược số
    mov r9, rsp
.L_div:
    xor rdx, rdx
    div rbx
    add dl, '0'                 ; Chuyển phần dư thành ký tự ASCII
    dec r9
    mov [r9], dl
    test rax, rax
    jnz .L_div
.L_write:                       ; Ghi từ Stack vào Buffer
    mov al, [r9]
    mov [rdi], al
    inc rdi
    inc r9
    cmp r9, rsp
    jne .L_write

    mov rsp, r8                 ; Phục hồi Stack
    ret
itoa endp

end
