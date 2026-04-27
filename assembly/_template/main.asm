extrn GetStdHandle:proc
extrn WriteConsoleA:proc
extrn ReadConsoleA:proc
extrn ExitProcess:proc
extrn QueryPerformanceCounter:proc
extrn QueryPerformanceFrequency:proc
extrn CreateThread:proc
extrn WaitForMultipleObjects:proc
extrn CloseHandle:proc

.data
    limit EQU 10000000
    max_idx EQU 4999998
    qword_count EQU 78125
    num_threads EQU 4           ; Tối ưu cho CPU 4 luồng

    msg_hdr  db "--- ASM (4 THREADS PARALLEL) ---", 10, "So nguyen to tim duoc (<10000000): ", 0
    msg_time db 10, "Thoi gian chay: ", 0
    msg_ms   db " ms", 10, "Nhan Enter de thoat...", 10, 0

.data?
    ALIGN 8
    is_comp db 625000 dup(?)
    
    ; Bộ đệm quản lý Đa luồng
    thread_handles dq 4 dup(?)
    thread_ids     dd 4 dup(?)
    
    str_buf db 512 dup(?)
    freq    dq ?
    start_t dq ?
    end_t   dq ?
    written dd ?

.code
; =====================================================================
; THREAD WORKER: Hàm thực thi song song trên các lõi CPU
; Input: RCX = Thread ID (0, 1, 2, 3)
; =====================================================================
SieveWorker proc
    lea r8, is_comp
    mov r9, rcx                 ; r9 = i = ID của luồng (0, 1, 2 hoặc 3)

outer_loop:
    bt [r8], r9
    jc next_p                   ; Nếu là hợp số, bỏ qua

    lea r10, [r9*2 + 3]         ; r10 = p = 2*i + 3
    mov rax, r10
    imul rax, r10               ; p * p
    cmp rax, limit
    jg thread_exit              ; Nếu p*p > limit -> Luồng này đã xong việc!

    sub rax, 3
    shr rax, 1
    mov r11, rax                ; r11 = j = Bắt đầu vòng lặp trong

inner_loop:
    ; BẮT BUỘC phải có tiền tố "LOCK" để chống Data Race giữa 4 lõi CPU
    lock bts [r8], r11          
    add r11, r10                
    cmp r11, max_idx
    jbe inner_loop

next_p:
    add r9, num_threads         ; Luồng 0 làm: 0, 4, 8... Luồng 1 làm: 1, 5, 9... (Chia việc đều nhau)
    jmp outer_loop

thread_exit:
    xor eax, eax
    ret
SieveWorker endp

; =====================================================================
; HÀM MAIN: Quản lý và Đồng bộ hóa luồng
; =====================================================================
main proc
    sub rsp, 48h

    lea rcx, freq
    call QueryPerformanceFrequency

    lea rcx, start_t
    call QueryPerformanceCounter

    ; 1. Khởi tạo 4 luồng phần cứng (Spawn Threads)
    xor r12, r12                ; r12 = thread_index = 0
spawn_loop:
    ; Cấp phát tham số cho CreateThread
    sub rsp, 30h
    mov rcx, 0                  ; lpThreadAttributes = NULL
    mov rdx, 0                  ; dwStackSize = 0 (Default)
    lea r8, SieveWorker         ; lpStartAddress = Địa chỉ hàm Worker
    mov r9, r12                 ; lpParameter = ID luồng (Truyền vào RCX của Worker)
    mov qword ptr [rsp+20h], 0  ; dwCreationFlags = 0 (Chạy ngay lập tức)
    lea rax, thread_ids
    mov [rsp+28h], rax          ; lpThreadId
    call CreateThread
    add rsp, 30h
    
    ; Lưu Handle của luồng
    lea rbx, thread_handles
    mov [rbx + r12*8], rax
    
    inc r12
    cmp r12, num_threads
    jl spawn_loop

    ; 2. Đợi cả 4 luồng làm xong việc (Wait Barrier)
    sub rsp, 28h
    mov rcx, num_threads        ; nCount = 4
    lea rdx, thread_handles     ; lpHandles
    mov r8, 1                   ; bWaitAll = TRUE (Đợi TẤT CẢ cùng xong)
    mov r9, -1                  ; dwMilliseconds = INFINITE
    call WaitForMultipleObjects
    add rsp, 28h

    ; Đóng Handle dọn rác hệ thống
    xor r12, r12
close_loop:
    sub rsp, 28h
    lea rbx, thread_handles
    mov rcx, [rbx + r12*8]
    call CloseHandle
    add rsp, 28h
    inc r12
    cmp r12, num_threads
    jl close_loop

    ; 3. Đếm tổng hợp số (Đơn luồng siêu tốc POPCNT)
    xor r11, r11
    lea rsi, is_comp
    mov rcx, qword_count
count_loop:
    popcnt rax, qword ptr [rsi]
    add r11, rax
    add rsi, 8
    dec rcx
    jnz count_loop

    ; Tính nguyên tố: 5000000 - Hợp số
    mov rax, 5000000
    sub rax, r11
    mov r11, rax

    ; 4. Tính giờ
    lea rcx, end_t
    call QueryPerformanceCounter

    mov rax, end_t
    sub rax, start_t
    mov rcx, 1000
    mul rcx
    div qword ptr [freq]
    mov r10, rax                ; ms

    ; In ấn
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

    mov rcx, -11
    call GetStdHandle
    mov rcx, rax
    lea rdx, str_buf
    mov r8, rbx
    lea r9, written
    mov qword ptr [rsp + 20h], 0
    call WriteConsoleA

    mov rcx, -10
    call GetStdHandle
    mov rcx, rax
    lea rdx, str_buf
    mov r8, 1
    lea r9, written
    mov qword ptr [rsp + 20h], 0
    call ReadConsoleA

    xor ecx, ecx
    call ExitProcess
main endp

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
