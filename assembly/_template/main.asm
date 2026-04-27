; prime_sieve_final.asm
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
main PROC
    ; --- Bấm giờ ---
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

    ; test prime
    mov rdx, rbx
    shr rdx, 1
    mov rcx, BYTE PTR is_prime[rdx/8]
    mov r8, rdx
    and r8, 7
    mov r9, 1
    shl r9, cl
    test rcx, r9
    jz skip_inner

    ; đánh dấu bội số
    mov rsi, rax
inner_loop:
    cmp rsi, limit
    ja inner_done
    mov rdx, rsi
    shr rdx, 1
    mov rcx, BYTE PTR is_prime[rdx/8]
    mov r8, rdx
    and r8, 7
    mov r9, 1
    shl r9, cl
    not r9
    and BYTE PTR is_prime[rdx/8], r9
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
    mov rbx, rcx
    shr rbx, 1
    mov al, BYTE PTR is_prime[rbx/8]
    mov bl, 1
    shl bl, cl
    test al, bl
    jz skip_inc
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
