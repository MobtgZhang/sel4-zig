//! aarch64 user exception request and floating-point preservation probe.
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
    asm volatile ("fmov d31, %[sentinel]; svc #1; fmov %[simd], d31"
        : [value] "+{x8}" (value),
          [a] "+{x0}" (arg0),
          [b] "+{x1}" (arg1),
          [c] "+{x2}" (arg2),
          [m0] "+{x3}" (mr0),
          [m1] "+{x4}" (mr1),
          [m2] "+{x5}" (mr2),
          [m3] "+{x6}" (mr3),
          [simd] "=&r" (simd),
        : [sentinel] "r" (sentinel),
        : .{ .v31 = true, .memory = true });
    return .{ .value = value, .badge = arg0, .info = arg2, .words = .{ mr0, mr1, mr2, mr3 }, .simd_preserved = simd == sentinel };
}
pub const mode = "user terminal: EL0";
pub fn relax() void {
    asm volatile ("yield");
}

// Fault message indices follow this architecture's register-set definition.
pub const fault_syscall_registers = 12;
pub const fault_exception_registers = 3;
pub const fault_syscall_pc = 8;
pub const fault_return_register = 0;
pub const fault_instruction_size = 4;
pub fn raiseException() void {
    asm volatile (".inst 0" ::: .{ .memory = true });
}

pub const uart_irq = 33;
