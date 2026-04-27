extrn GetStdHandle:proc
extrn WriteConsoleA:proc
extrn ReadConsoleA:proc
extrn ExitProcess:proc
extrn QueryPerformanceCounter:proc
extrn QueryPerformanceFrequency:proc

.data
    limit EQU 10000000
    max_idx EQU 4999998         ; max_idx = (10000000 - 3) / 2
    
    ; 625000 bytes = 5,000,000 bits. Đủ để biểu diễn 5 triệu số lẻ.
    qword_count EQU 78125       ; 625000 / 8 = 78125 khối 64-bit

    msg_hdr  db "--- ASSEMBLY (BITSET + POPCNT ALGORITHM) ---", 10, "So nguyen to tim duoc (<10000000): ", 0
    msg_time db 10, "Thoi gian chay: ", 0
    msg_ms   db " ms", 10, "Nhan Enter de thoat...", 10, 0

.data?
    ALIGN 8                     ; Căn lề 8-byte để tăng tốc độ đọc QWORD
    is_comp db 625000 dup(?)    ; Chỉ tốn 625 KB RAM! (1 Bit = 1 số lẻ)
    str_buf db 512 dup(?)
    freq    dq ?
    start_t dq ?
    end_t   dq ?
    written dd ?

.code
main proc
    sub rsp, 48h

    ; 1. Lấy tần số CPU
    lea rcx, freq
    call QueryPerformanceFrequency

    ; 2. Bắt đầu bấm giờ
    lea rcx, start_t
    call QueryPerformanceCounter

    ; 3. Thuật toán Sàng nguyên tố bằng BIT (Bit-Level Odd-Only Sieve)
    lea r8, is_comp             ; R8 = Địa chỉ cơ sở của mảng Bit
    mov r9, 0                   ; R9 = i = 0 (Tương ứng với số 3)

outer_loop:
    ; Lệnh BT (Bit Test): Kiểm tra bit thứ r9 trong mảng r8.
    ; CPU tự động tính toán byte và bit offset. Đẩy kết quả vào cờ Carry (CF).
    bt [r8], r9
    jc next_p                   ; Nếu CF=1 (Bit đã set = Hợp số), bỏ qua

    ; Tính p = 2*i + 3
    lea r10, [r9*2 + 3]         ; r10 = p

    ; Tính p * p
    mov rax, r10
    imul rax, r10
    cmp rax, limit
    jg do_count                 ; Nếu p*p > limit -> Dừng sàng

    ; Tính index bắt đầu j = (p*p - 3) / 2
    sub rax, 3
    shr rax, 1
    mov r11, rax                ; r11 = j

    ; ---------------------------------------------------------
    ; [VÒNG LẶP LÕI (INNER LOOP)]: Siêu Cache-Friendly
    ; Lệnh BTS (Bit Test and Set) tự động bật bit thứ r11 lên 1
    ; ---------------------------------------------------------
inner_loop:
    bts [r8], r11               ; Bật bit hợp số
    add r11, r10                ; j += p
    cmp r11, max_idx
    jbe inner_loop              
    ; ---------------------------------------------------------

next_p:
    inc r9
    jmp outer_loop

do_count:
    ; 4. [TỐI ƯU CỰC ĐẠI]: Đếm số lượng nguyên tố bằng POPCNT
    ; Lệnh POPCNT đếm số lượng bit '1' (Hợp số) trong thanh ghi 64-bit chỉ tốn 1 cycle.
    xor r11, r11                ; R11 = Tổng số hợp số (Composite count) = 0
    lea rsi, is_comp
    mov rcx, qword_count        ; Lặp 78125 lần (Mỗi lần đếm 64 số)
    
count_loop:
    popcnt rax, qword ptr [rsi] ; Đếm số lượng bit 1 trong khối 8 byte
    add r11, rax                ; Cộng vào tổng
    add rsi, 8                  ; Nhảy sang khối 64-bit tiếp theo
    dec rcx
    jnz count_loop

    ; Số nguyên tố = 1 (số 2) + 4999999 (tổng số lẻ) - Số hợp số (r11)
    ; => Số nguyên tố = 5000000 - r11
    mov rax, 5000000
    sub rax, r11
    mov r11, rax                ; R11 = Tổng số nguyên tố cuối cùng!

    ; 5. Dừng bấm giờ
    lea rcx, end_t
    call QueryPerformanceCounter

    ; 6. Tính Mili-giây
    mov rax, end_t
    sub rax, start_t
    mov rcx, 1000
    mul rcx
    div qword ptr [freq]
    mov r10, rax                ; R10 = ms

    ; 7. Ghi chuỗi ra màn hình
    lea rdi, str_buf
    lea rsi, msg_hdr
    call copy_string
    mov rax, r11
    call itoa
    lea rsi, msg_time
    call copy_string
    mov rax, r10
    call itoa
    lea rsi, msg_ms
    call copy_string

    lea rax, str_buf
    sub rdi, rax
    mov rbx, rdi

    ; 8. In ra Console
    mov rcx, -11
    call GetStdHandle
    mov rcx, rax
    lea rdx, str_buf
    mov r8, rbx
    lea r9, written
    mov qword ptr [rsp + 20h], 0
    call WriteConsoleA

    ; 9. Chờ người dùng
    mov rcx, -10
    call GetStdHandle
    mov rcx, rax
    lea rdx, str_buf
    mov r8, 1
    lea r9, written
    mov qword ptr [rsp + 20h], 0
    call ReadConsoleA

    ; 10. Thoát
    xor ecx, ecx
    call ExitProcess
main endp

; --- Helpers ---
copy_string proc
L_copy:
    mov al, [rsi]
    test al, al
    jz L_done
    mov [rdi], al
    inc rsi
    inc rdi
    jmp L_copy
L_done:
    ret
copy_string endp

itoa proc
    mov rbx, 10
    sub rsp, 40h
    lea r9, [rsp + 30h]
L_div_loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec r9
    mov [r9], dl
    test rax, rax
    jnz L_div_loop
L_write_loop:
    mov al, [r9]
    mov [rdi], al
    inc rdi
    inc r9
    lea rcx, [rsp + 30h]
    cmp r9, rcx
    jne L_write_loop
    add rsp, 40h
    ret
itoa endp

end
