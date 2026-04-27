; prime_sieve_extreme_fix.asm
OPTION CASEMAP:NONE

extrn GetStdHandle:proc
extrn WriteConsoleA:proc
extrn ReadConsoleA:proc
extrn ExitProcess:proc
extrn wsprintfA:proc
extrn GetTickCount:proc
extrn lstrlenA:proc

.DATA
limit       QWORD 10000000

; Chỉ lưu số lẻ >2
bits_len    QWORD ((10000000/2 +7)/8)
is_prime    DB ((10000000/2 +7)/8) DUP(0FFh)

fmt_out     DB "--- ASSEMBLY (PURE WIN32 API) ---",10
            DB "So nguyen to tim duoc (<%d): %d",10
            DB "Thoi gian chay: %d ms",10
            DB "Nhan Enter de thoat...",10,0

str_buf     DB 256 DUP(?)
written     DD ?

.DATA?
count       QWORD ?
start_tick  DWORD ?
duration    DWORD ?
hStdOut     QWORD ?
hStdIn      QWORD ?

.CODE
; --- thao tác bit ---
set_bit MACRO arr, idx
    mov rax, idx
    shr rax, 3
    mov rbx, idx
    and bl, 7          ; chỉ 8-bit cho bts
    bts BYTE PTR arr[rax], bl
ENDM

clear_bit MACRO arr, idx
    mov rax, idx
    shr rax, 3
    mov rbx, idx
    and bl, 7
    btr BYTE PTR arr[rax], bl
ENDM

test_bit MACRO arr, idx, out
    mov rax, idx
    shr rax, 3
    mov rbx, idx
    and bl, 7
    bt BYTE PTR arr[rax], bl
    setc out
ENDM

main PROC
    ; --- Bấm giờ bắt đầu ---
    call GetTickCount
    mov start_tick, eax

    ; --- Init console handles ---
    mov rcx, -11
    call GetStdHandle
    mov hStdOut, rax
    mov rcx, -10
    call GetStdHandle
    mov hStdIn, rax

    ; --- 2 là prime ---
    mov count, 1

    ; --- Sieve chỉ số lẻ ---
    mov rbx, 3                  ; p = 3
next_p:
    mov rax, rbx
    imul rax, rbx
    cmp rax, limit
    ja done_sieve

    ; p có phải prime?
    mov al, 0
    mov rcx, rbx
    shr rcx, 1
    test_bit is_prime, rcx, al
    cmp al, 0
    je skip_inner

    ; đánh dấu bội số từ p*p, bước 2p
    mov rsi, rax
inner_loop:
    cmp rsi, limit
    ja inner_done
    mov rcx, rsi
    shr rcx,1
    clear_bit is_prime, rcx
    add rsi, rbx*2
    jmp inner_loop
inner_done:
skip_inner:
    add rbx, 2
    jmp next_p
done_sieve:

    ; --- Count primes ---
    xor rdx, rdx
    mov rcx, 1
count_loop:
    mov rax, rcx
    shl rax, 1
    cmp rax, limit
    ja count_done
    test_bit is_prime, rcx, al
    cmp al, 0
    je skip_inc
    inc rdx
skip_inc:
    inc rcx
    jmp count_loop
count_done:
    add rdx, 1          ; cộng prime =2
    mov count, rdx

    ; --- Bấm giờ kết thúc ---
    call GetTickCount
    sub eax, start_tick
    mov duration, eax

    ; --- Format output ---
    lea rcx, str_buf
    lea rdx, fmt_out
    mov r8, limit
    mov r9, count
    mov [rsp+20h], duration
    sub rsp, 28h
    call wsprintfA
    add rsp, 28h

    ; --- WriteConsoleA ---
    mov rcx, hStdOut
    lea rdx, str_buf
    call lstrlenA
    mov r8d, eax
    lea r9, written
    mov qword ptr [rsp+20h], 0
    call WriteConsoleA

    ; --- Chờ Enter ---
    mov rcx, hStdIn
    lea rdx, str_buf
    mov r8d, 32
    lea r9, written
    mov qword ptr [rsp+20h], 0
    call ReadConsoleA

    ; --- Exit ---
    xor ecx, ecx
    call ExitProcess

main ENDP
END main
