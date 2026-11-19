//! Register order follows upstream fault message definitions.
//! Replies can update user registers but never grant privileged execution state.
const Frame = @import("user.zig").Frame;
const Thread = @import("../../model/structures.zig").Thread;
pub fn capture(f: *const Frame, thread: *Thread, syscall: bool) void {
    thread.fault_reply_pending = false;
    if (syscall) {
        thread.fault_register_count = 12;
        thread.fault_registers[0] = f.regs[0];
        thread.fault_registers[1] = f.regs[1];
        thread.fault_registers[2] = f.regs[2];
        thread.fault_registers[3] = f.regs[3];
        thread.fault_registers[4] = f.regs[4];
        thread.fault_registers[5] = f.regs[5];
        thread.fault_registers[6] = f.regs[6];
        thread.fault_registers[7] = f.regs[7];
        thread.fault_registers[8] = thread.fault_pc;
        thread.fault_registers[9] = f.sp;
        thread.fault_registers[10] = f.pc;
        thread.fault_registers[11] = f.status;
    } else {
        thread.fault_register_count = 3;
        thread.fault_registers[0] = thread.fault_pc;
        thread.fault_registers[1] = f.sp;
        thread.fault_registers[2] = f.status;
    }
}
/// Reject invalid user return addresses before the architecture restores the frame.
pub fn apply(f: *Frame, thread: *Thread) bool {
    if (!thread.fault_reply_pending) return true;
    thread.fault_reply_pending = false;
    if (thread.fault_register_count > 3) {
        f.regs[0] = thread.fault_registers[0];
        f.regs[1] = thread.fault_registers[1];
        f.regs[2] = thread.fault_registers[2];
        f.regs[3] = thread.fault_registers[3];
        f.regs[4] = thread.fault_registers[4];
        f.regs[5] = thread.fault_registers[5];
        f.regs[6] = thread.fault_registers[6];
        f.regs[7] = thread.fault_registers[7];
        f.pc = thread.fault_registers[8];
        f.sp = thread.fault_registers[9];
        // Restart uses FaultIP, as upstream does when leaving ThreadState_Restart.
        // The separate ELR_EL1 message word describes the saved next PC.
        f.status = thread.fault_registers[11];
    } else {
        f.pc = thread.fault_registers[0];
        f.sp = thread.fault_registers[1];
        f.status = thread.fault_registers[2];
    }
    f.status = (f.status & 0xf0000000) | 0x340;
    return f.pc < 1 << 38 and f.sp < 1 << 38 and f.pc & 3 == 0;
}
