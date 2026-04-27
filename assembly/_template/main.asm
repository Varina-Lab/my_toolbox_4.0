; prime_sieve_masm64.asm
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

bits_len    QWORD ((10000000/2+7)/8)
is_prime    DB ((10000000/2+7)/8) DUP(0FFh)

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
    mov rdx, 3
next_p:
    mov rax, rdx
    imul rax, rdx
    cmp rax, limit
    ja done_sieve

    ; --- Test p ---
    mov rcx, rdx
    shr rcx, 1                  ; index trong bit array
    mov r8, rcx
    shr r8, 3                    ; byte index
    mov r9, cl
    and r9, 7                     ; bit index
    mov r10d, 1
    shl r10d, r9                  ; mask
    mov r11b, is_prime[r8]
    test r11b, r10b
    jz skip_inner

    ; --- Clear multiples ---
    mov rsi, rax
inner_loop:
    cmp rsi, limit
    ja inner_done
    mov rcx, rsi
    shr rcx, 1                    ; index bit array
    mov r8, rcx
    shr r8, 3                     ; byte index
    mov r9, cl
    and r9, 7                      ; bit index
    mov r10d, 1
    shl r10d, r9
    not r10d
    and BYTE PTR is_prime[r8], r10b
    add rsi, rdx*2
    jmp inner_loop
inner_done:
skip_inner:
    add rdx, 2
    jmp next_p
done_sieve:

    ; --- Count primes ---
    xor rax, rax
    mov rcx, 1
count_loop:
    mov rbx, rcx
    shr rbx, 1                    ; index bit array
    mov r8, bl
    mov r9, BYTE PTR is_prime[rbx]
    mov r10d, 1
    shl r10d, r8
    test r9, r10b
    jz skip_inc
    inc rax
skip_inc:
    inc rcx
    cmp rcx, limit
    jb count_loop
    add rax, 1
    mov count, rax

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
