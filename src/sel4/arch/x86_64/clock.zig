//! Calibrate TSC against PIT channel 2 without changing the scheduler's channel 0.
const io = @import("../../platform/io.zig");
const machine = @import("machine.zig");
var frequency_hz: u64 = 0;

pub fn ticks() u64 {
    var low: u32 = undefined;
    var high: u32 = undefined;
    asm volatile ("lfence; rdtsc"
        : [low] "={eax}" (low),
          [high] "={edx}" (high),
        :
        : .{ .memory = true });
    return (@as(u64, high) << 32) | low;
}
pub fn frequency() u64 {
    return frequency_hz;
}
pub fn initialize() !void {
    // CPUID.15 specifies the TSC/crystal ratio when all three fields are present.
    if (machine.cpuid(0, 0).eax >= 0x15) {
        const ratio = machine.cpuid(0x15, 0);
        if (ratio.eax != 0 and ratio.ebx != 0 and ratio.ecx != 0) {
            frequency_hz = @as(u64, ratio.ecx) * ratio.ebx / ratio.eax;
            if (frequency_hz != 0) return;
        }
    }
    const previous = io.in8(0x61);
    defer io.out8(0x61, previous);
    io.out8(0x61, previous & ~@as(u8, 3));
    io.out8(0x43, 0xb0); // Channel 2, low/high bytes, one-shot mode.
    const count: u16 = 11932; // Approximately 10 ms at 1.193182 MHz.
    io.out8(0x42, @truncate(count));
    io.out8(0x42, @truncate(count >> 8));
    const start = ticks();
    io.out8(0x61, (previous & ~@as(u8, 2)) | 1);
    // This guard detects an absent PIT; it is not a device-request timeout.
    var remaining: usize = 10_000_000;
    while (io.in8(0x61) & 0x20 == 0) {
        if (remaining == 0) return error.ClockCalibrationFailed;
        remaining -= 1;
        asm volatile ("pause");
    }
    frequency_hz = (ticks() -% start) * 1_193_182 / count;
    if (frequency_hz == 0) return error.InvalidCounterFrequency;
}
