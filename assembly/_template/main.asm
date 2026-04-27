; prime_sieve_extreme_final.asm
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

; --- inline set bit ---
set_bit PROC idx:QWORD
    mov rax, idx
    shr rax, 3
    mov rcx, idx
    and cl, 7
    mov rdx, 1
    shl dl, cl
    or BYTE PTR is_prime[rax], dl
    ret
set_bit ENDP

; --- inline clear bit ---
clear_bit PROC idx:QWORD
    mov rax, idx
    shr rax, 3
    mov rcx, idx
    and cl, 7
    mov rdx, 1
    shl dl, cl
    not dl
    and BYTE PTR is_prime[rax], dl
    ret
clear_bit ENDP

; --- inline test bit ---
test_bit PROC idx:QWORD
    mov rax, idx
    shr rax, 3
    mov rcx, idx
    and cl, 7
    mov dl, BYTE PTR is_prime[rax]
    shr dl, cl
    and dl, 1
    movzx rax, dl
    ret
test_bit ENDP

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

    mov count, 1          ; 2 là prime

    ; --- Sieve chỉ số lẻ ---
    mov rbx, 3
next_p:
    mov rax, rbx
    imul rax, rbx
    cmp rax, limit
    ja done_sieve

    ; p có phải prime?
    mov rcx, rbx
    call test_bit
    cmp rax, 0
    je skip_inner

    ; đánh dấu bội số
    mov rsi, rax
inner_loop:
    cmp rsi, limit
    ja inner_done
    mov rcx, rsi
    call clear_bit
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
    mov rcx, rax
    call test_bit
    cmp rax, 0
    je skip_inc
    inc rdx
skip_inc:
    inc rcx
    jmp count_loop
count_done:
    add rdx, 1
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
    sub rsp, 28h
    mov r10d, duration
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
