//! The controller claims an IRQ before kernel object notification delivery.
const arch = @import("../arch/mod.zig");
const Kernel = @import("runtime.zig").Kernel;
pub fn handle(kernel: *Kernel, event: @import("../arch/irq_event.zig").Event) void {
    switch (event) {
        .timer => kernel.scheduler.timerTick(),
        .ipi => @import("../platform/smp.zig").pollWork(@import("smp_dispatch.zig").index()),
        .device => |irq| kernel.irqs.handle(&kernel.scheduler, irq) catch {
            // Unknown sources must not remain asserted and starve the timer.
            const controller = arch.backend.irq.controller;
            controller.mask(controller.context, irq, true);
            controller.acknowledge(controller.context, irq);
        },
        .spurious => {},
    }
}
