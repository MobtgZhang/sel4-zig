//! Private register-message trap shared by independently loaded user services.
const abi = @import("shell").abi;
pub fn invoke(op: abi.Operation, a: u64, b: u64, c: u64, word: u64) abi.Result {
    return invokeWords(op, a, b, c, .{ word, 0, 0, 0 });
}
pub fn invokeWords(op: abi.Operation, a: u64, b: u64, c: u64, words: [4]u64) abi.Result {
    var value: u64 = @backingInt(op);
    var arg0 = a;
    var arg1 = b;
    var arg2 = c;
    var mr0 = words[0];
    var mr1 = words[1];
    var mr2 = words[2];
    var mr3 = words[3];
    // A different sentinel per request detects SIMD corruption across task switches.
    const sentinel: u64 = 0x3ff0_1234_5678_9abc ^ (a & 0xffff) ^ words[0];
    var simd: u64 = undefined;
    asm volatile ("movq %[sentinel], %%xmm15; int $0x80; movq %%xmm15, %[simd]"
        : [value] "+{rax}" (value),
          [a] "+{rdi}" (arg0),
          [b] "+{rsi}" (arg1),
          [c] "+{rdx}" (arg2),
          [m0] "+{r10}" (mr0),
          [m1] "+{r8}" (mr1),
          [m2] "+{r9}" (mr2),
          [m3] "+{r15}" (mr3),
          [simd] "=&r" (simd),
        : [sentinel] "r" (sentinel),
        : .{ .xmm15 = true, .memory = true });
    return .{ .value = value, .badge = arg0, .info = arg2, .words = .{ mr0, mr1, mr2, mr3 }, .simd_preserved = simd == sentinel };
}

pub const mode = "user terminal: ring 3";
pub fn relax() void {
    asm volatile ("pause");
}

// Fault message indices follow this architecture's register-set definition.
pub const fault_syscall_registers = 18;
pub const fault_exception_registers = 3;
pub const fault_syscall_pc = 15;
pub const fault_return_register = 5;
pub const fault_instruction_size = 2;
pub fn raiseException() void {
    asm volatile ("ud2" ::: .{ .memory = true });
}

pub const uart_irq = 4;
