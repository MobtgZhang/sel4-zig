//! x86-64 fault message order and sanitized replies.
const Frame = @import("user_runtime.zig").Frame;
const Thread = @import("../../model/structures.zig").Thread;
pub fn capture(f: *const Frame, thread: *Thread, syscall: bool) void {
    thread.fault_reply_pending = false;
    if (syscall) {
        thread.fault_register_count = 18;
        thread.fault_registers[0] = f.rax;
        thread.fault_registers[1] = f.rbx;
        thread.fault_registers[2] = f.rcx;
        thread.fault_registers[3] = f.rdx;
        thread.fault_registers[4] = f.rsi;
        thread.fault_registers[5] = f.rdi;
        thread.fault_registers[6] = f.rbp;
        thread.fault_registers[7] = f.r8;
        thread.fault_registers[8] = f.r9;
        thread.fault_registers[9] = f.r10;
        thread.fault_registers[10] = f.r11;
        thread.fault_registers[11] = f.r12;
        thread.fault_registers[12] = f.r13;
        thread.fault_registers[13] = f.r14;
        thread.fault_registers[14] = f.r15;
        thread.fault_registers[15] = thread.fault_pc;
        thread.fault_registers[16] = f.rsp;
        thread.fault_registers[17] = f.rflags;
    } else {
        thread.fault_register_count = 3;
        thread.fault_registers[0] = f.rip;
        thread.fault_registers[1] = f.rsp;
        thread.fault_registers[2] = f.rflags;
    }
}
/// Reject invalid user return addresses before the architecture restores the frame.
pub fn apply(f: *Frame, thread: *Thread) bool {
    if (!thread.fault_reply_pending) return true;
    thread.fault_reply_pending = false;
    if (thread.fault_register_count == 18) {
        f.rax = thread.fault_registers[0];
        f.rbx = thread.fault_registers[1];
        f.rcx = thread.fault_registers[2];
        f.rdx = thread.fault_registers[3];
        f.rsi = thread.fault_registers[4];
        f.rdi = thread.fault_registers[5];
        f.rbp = thread.fault_registers[6];
        f.r8 = thread.fault_registers[7];
        f.r9 = thread.fault_registers[8];
        f.r10 = thread.fault_registers[9];
        f.r11 = thread.fault_registers[10];
        f.r12 = thread.fault_registers[11];
        f.r13 = thread.fault_registers[12];
        f.r14 = thread.fault_registers[13];
        f.r15 = thread.fault_registers[14];
        f.rip = thread.fault_registers[15];
        f.rsp = thread.fault_registers[16];
        f.rflags = thread.fault_registers[17];
    } else {
        f.rip = thread.fault_registers[0];
        f.rsp = thread.fault_registers[1];
        f.rflags = thread.fault_registers[2];
    }
    // Retain arithmetic flags; force IF and reserved bit 1, clear IOPL/NT/VM.
    f.rflags = (f.rflags & 0x8d5) | 0x202;
    f.cs = 0x23;
    f.ss = 0x1b;
    return f.rip < 1 << 47 and f.rsp < 1 << 47;
}
