//! 镜像：`seL4/src/smp/lock.c`
pub const upstream_rel = "smp/lock.c";

/// 最简 ticket-free spin：与上游 `clh`/`bit` 锁不等价，仅作 SMP 迁移占位。
pub const SpinLockU32 = struct {
    state: u32 = 0,

    pub fn tryAcquire(lock: *SpinLockU32) bool {
        return @cmpxchgWeak(u32, &lock.state, 0, 1, .acquire, .monotonic) == null;
    }

    pub fn release(lock: *SpinLockU32) void {
        @atomicStore(u32, &lock.state, 0, .release);
    }
};
