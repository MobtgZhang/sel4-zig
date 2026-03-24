//! 阶段三优先级 4：上游 `seL4/src/kernel/thread.c`；x86：`arch/x86/kernel/thread.c`、`arch/x86/64/kernel/thread.c`。
pub const upstream_rel = "kernel/thread.c";
pub const upstream_arch_rel = "arch/x86/kernel/thread.c";
pub const upstream_arch_64_rel = "arch/x86/64/kernel/thread.c";

const hybrid = @import("../hybrid/boot_bridge.zig");
const statedata = @import("../model/statedata.zig");
const cspace = @import("cspace.zig");
const faulthandler = @import("faulthandler.zig");
const preemption = @import("../model/preemption.zig");
const sporadic = @import("sporadic.zig");
const stack = @import("stack.zig");
const benchmark = @import("../benchmark/benchmark.zig");

pub fn zigSmokeThreadStub() void {
    hybrid.callThreadStub();
    statedata.ks_cur_thread_tag = 0;
    _ = cspace.migration_phase;
    _ = cspace.lookupCapSlotStub(0, 0);
    faulthandler.faultHandlerStub();
    preemption.preemptionPointStub();
    sporadic.sporadicTickStub();
    stack.stackSwitchStub();
    benchmark.benchmarkNullStub();
}
