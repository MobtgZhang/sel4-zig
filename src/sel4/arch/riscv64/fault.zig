//! Register order follows upstream fault message definitions.
//! Replies can update user registers but never grant privileged execution state.
const Frame = @import("user.zig").Frame;
const Thread = @import("../../model/structures.zig").Thread;
pub fn capture(f: *const Frame, thread: *Thread, syscall: bool) void {
    thread.fault_reply_pending = false;
    if (syscall) {
        thread.fault_register_count = 10;
        thread.fault_registers[0] = thread.fault_pc;
        thread.fault_registers[1] = f.regs[2];
        thread.fault_registers[2] = f.regs[1];
        thread.fault_registers[3] = f.regs[10];
        thread.fault_registers[4] = f.regs[11];
        thread.fault_registers[5] = f.regs[12];
        thread.fault_registers[6] = f.regs[13];
        thread.fault_registers[7] = f.regs[14];
        thread.fault_registers[8] = f.regs[15];
        thread.fault_registers[9] = f.regs[16];
    } else {
        thread.fault_register_count = 2;
        thread.fault_registers[0] = thread.fault_pc;
        thread.fault_registers[1] = f.regs[2];
    }
}
/// Reject invalid user return addresses before the architecture restores the frame.
pub fn apply(f: *Frame, thread: *Thread) bool {
    if (!thread.fault_reply_pending) return true;
    thread.fault_reply_pending = false;
    if (thread.fault_register_count > 3) {
        f.pc = thread.fault_registers[0];
        f.regs[2] = thread.fault_registers[1];
        f.regs[1] = thread.fault_registers[2];
        f.regs[10] = thread.fault_registers[3];
        f.regs[11] = thread.fault_registers[4];
        f.regs[12] = thread.fault_registers[5];
        f.regs[13] = thread.fault_registers[6];
        f.regs[14] = thread.fault_registers[7];
        f.regs[15] = thread.fault_registers[8];
        f.regs[16] = thread.fault_registers[9];
    } else {
        f.pc = thread.fault_registers[0];
        f.regs[2] = thread.fault_registers[1];
    }
    f.status = 0x46020;
    return f.pc < 1 << 38 and f.regs[2] < 1 << 38 and f.pc & 1 == 0;
}
