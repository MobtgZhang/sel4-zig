//! Local invalidation includes global translations before acknowledging a shootdown.
pub fn invlpg(address: usize) void {
    asm volatile ("invlpg (%[v])"
        :
        : [v] "r" (address),
        : .{ .memory = true });
}
pub fn invalidateAll() void {
    const cr4 = asm volatile ("mov %%cr4, %[v]"
        : [v] "=r" (-> u64),
    );
    if (cr4 & (1 << 7) != 0) {
        asm volatile ("mov %[v], %%cr4"
            :
            : [v] "r" (cr4 & ~@as(u64, 1 << 7)),
            : .{ .memory = true });
        asm volatile ("mov %[v], %%cr4"
            :
            : [v] "r" (cr4),
            : .{ .memory = true });
    } else @import("machine.zig").writeCr3(@import("machine.zig").readCr3());
}
pub fn readUser(address: usize) u64 {
    return @as(*const volatile u64, @ptrFromInt(address)).*;
}
