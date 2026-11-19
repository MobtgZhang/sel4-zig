//! riscv64 user exception request and floating-point preservation probe.
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
    const sentinel: u64 = 0x3ff0123456789abc ^ (a & 0xffff) ^ words[0];
    var simd: u64 = undefined;
    asm volatile ("fmv.d.x f31, %[sentinel]; ecall; fmv.x.d %[simd], f31"
        : [value] "+{a7}" (value),
          [a] "+{a0}" (arg0),
          [b] "+{a1}" (arg1),
          [c] "+{a2}" (arg2),
          [m0] "+{a3}" (mr0),
          [m1] "+{a4}" (mr1),
          [m2] "+{a5}" (mr2),
          [m3] "+{a6}" (mr3),
          [simd] "=&r" (simd),
        : [sentinel] "r" (sentinel),
        : .{ .f31 = true, .memory = true });
    return .{ .value = value, .badge = arg0, .info = arg2, .words = .{ mr0, mr1, mr2, mr3 }, .simd_preserved = simd == sentinel };
}
pub const mode = "user terminal: U-mode";
pub fn relax() void {
    asm volatile ("nop");
}

// Fault message indices follow this architecture's register-set definition.
pub const fault_syscall_registers = 10;
pub const fault_exception_registers = 2;
pub const fault_syscall_pc = 0;
pub const fault_return_register = 3;
pub const fault_instruction_size = 4;
pub fn raiseException() void {
    asm volatile (".4byte 0" ::: .{ .memory = true });
}

pub const uart_irq = 10;
