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
    num_threads EQU 4           ; Số luồng chạy song song

    msg_hdr  db "--- ASM (4 THREADS PARALLEL - SAFE ALIGNED) ---", 10, "So nguyen to tim duoc (<10000000): ", 0
    msg_time db 10, "Thoi gian chay: ", 0
    msg_ms   db " ms", 10, "Nhan Enter de thoat...", 10, 0

.data?
    ALIGN 8
    is_comp db 625000 dup(?)    ; 625 KB (5 triệu bit)
    
    thread_handles dq 4 dup(?)
    thread_ids     dd 4 dup(?)
    
    str_buf db 512 dup(?)
    freq    dq ?
    start_t dq ?
    end_t   dq ?
    written dd ?

.code
; =====================================================================
; THREAD WORKER: Hàm thực thi song song
; Input: RCX = Thread ID (0, 1, 2, 3)
; =====================================================================
SieveWorker proc
    lea r8, is_comp
    mov r9, rcx                 

outer_loop:
    ; Đã thêm qword ptr để an toàn tuyệt đối cho bộ nhớ
    bt qword ptr [r8], r9
    jc next_p                   

    lea r10, [r9*2 + 3]         
    mov rax, r10
    imul rax, r10               
    cmp rax, limit
    jg thread_exit              

    sub rax, 3
    shr rax, 1
    mov r11, rax                

inner_loop:
    ; Tiền tố LOCK kết hợp chỉ định rõ qword ptr
    lock bts qword ptr [r8], r11          
    add r11, r10                
    cmp r11, max_idx
    jbe inner_loop

next_p:
    add r9, num_threads         
    jmp outer_loop

thread_exit:
    xor eax, eax
    ret
SieveWorker endp

; =====================================================================
; HÀM MAIN: Quản lý luồng và Đồng bộ
; =====================================================================
main proc
    ; [TỐI ƯU STACK]: Cấp phát 56 bytes (38h) MỘT LẦN DUY NHẤT
    ; (32 bytes Shadow Space + 24 bytes cho các tham số thứ 5,6)
    ; Stack sẽ luôn Aligned 16-byte hoàn hảo!
    sub rsp, 38h

    lea rcx, freq
    call QueryPerformanceFrequency

    lea rcx, start_t
    call QueryPerformanceCounter

    ; 1. Khởi tạo 4 luồng phần cứng
    xor r12, r12                
spawn_loop:
    mov rcx, 0                  ; Arg 1: lpThreadAttributes
    mov rdx, 0                  ; Arg 2: dwStackSize
    lea r8, SieveWorker         ; Arg 3: lpStartAddress
    mov r9, r12                 ; Arg 4: lpParameter = ID luồng
    mov qword ptr [rsp+20h], 0  ; Arg 5: dwCreationFlags
    
    ; Đẩy ID luồng vào đúng slot của mảng (r12 * 4 bytes)
    lea rax, thread_ids
    lea rax, [rax + r12*4]
    mov [rsp+28h], rax          ; Arg 6: lpThreadId
    
    call CreateThread
    
    lea rbx, thread_handles
    mov [rbx + r12*8], rax      ; Lưu Handle lại để chờ
    
    inc r12
    cmp r12, num_threads
    jl spawn_loop

    ; 2. Đợi TẤT CẢ các luồng làm xong
    mov rcx, num_threads        ; Arg 1: nCount = 4
    lea rdx, thread_handles     ; Arg 2: lpHandles
    mov r8, 1                   ; Arg 3: bWaitAll = TRUE
    mov r9, -1                  ; Arg 4: dwMilliseconds = INFINITE
    call WaitForMultipleObjects

    ; Đóng Handle
    xor r12, r12
close_loop:
    lea rbx, thread_handles
    mov rcx, [rbx + r12*8]
    call CloseHandle
    inc r12
    cmp r12, num_threads
    jl close_loop

    ; 3. Đếm tổng số lượng bằng POPCNT
    xor r11, r11
    lea rsi, is_comp
    mov rcx, qword_count
count_loop:
    popcnt rax, qword ptr [rsi]
    add r11, rax
    add rsi, 8
    dec rcx
    jnz count_loop

    ; 5,000,000 - số hợp số = số nguyên tố
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
    mov r10, rax                

    ; 5. In ấn
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
    sub rsp, 28h                ; Đã sửa lại Stack Alignment cho hàm con
    lea r9, [rsp + 18h]
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
    lea rcx, [rsp + 18h]
    cmp r9, rcx
    jne L_write_loop
    add rsp, 28h
    ret
itoa endp

end
