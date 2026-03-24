//! 阶段四 4.3：x86_64 IDT 表项布局（与 Intel SDM / 上游陷阱入口配合使用）。
const std = @import("std");

pub const IdtEntry = packed struct {
    offset_low: u16,
    selector: u16,
    ist: u3,
    _reserved0: u5 = 0,
    gate_type: u4,
    _reserved1: u1 = 0,
    dpl: u2,
    present: u1,
    offset_high: u48,
    _reserved2: u32 = 0,

    pub const gate_interrupt: u4 = 0xE;
    pub const gate_trap: u4 = 0xF;

    /// 填充 64 位中断/陷阱门描述符（offset 为内核代码段内线性地址）。
    pub fn initInterruptGate(code_selector: u16, offset: u64, dpl_bits: u2) IdtEntry {
        return .{
            .offset_low = @truncate(offset),
            .selector = code_selector,
            .ist = 0,
            .gate_type = gate_interrupt,
            .dpl = dpl_bits,
            .present = 1,
            .offset_high = @truncate(offset >> 16),
            ._reserved2 = 0,
        };
    }

    pub fn handlerAddress(self: IdtEntry) u64 {
        const low: u64 = self.offset_low;
        const high: u64 = self.offset_high;
        return low | (high << 16);
    }
};

test "idt entry size" {
    try std.testing.expect(@sizeOf(IdtEntry) == 16);
}

test "idt interrupt gate roundtrip" {
    const e = IdtEntry.initInterruptGate(0x08, 0xffff_8070_0000_1234, 0);
    try std.testing.expectEqual(@as(u64, 0xffff_8070_0000_1234), e.handlerAddress());
}
