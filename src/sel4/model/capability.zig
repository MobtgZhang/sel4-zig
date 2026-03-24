//! 阶段四 4.1：与上游生成 `structures_gen.h` 中 `cap_t`（`uint64_t words[2]`，类型域在 word0 位 59–63）对齐。
//! 高层 `Capability` 仍为 Zig 表达；低层布局用 `CapRaw` + `capType`。
const std = @import("std");

pub const UntypedCap = struct { bits: u128 };
pub const EndpointCap = struct { bits: u128 };
pub const TcbCap = struct { bits: u128 };
pub const CNodeCap = struct { bits: u128 };
pub const FrameCap = struct { bits: u128 };
pub const PageTableCap = struct { bits: u128 };
pub const NotificationCap = struct { bits: u128 };
pub const ReplyCap = struct { bits: u128 };
pub const IrqHandlerCap = struct { bits: u128 };

pub const Capability = union(enum) {
    null_cap: void,
    untyped: UntypedCap,
    endpoint: EndpointCap,
    tcb: TcbCap,
    cnode: CNodeCap,
    frame: FrameCap,
    page_table: PageTableCap,
    notification: NotificationCap,
    reply: ReplyCap,
    irq_handler: IrqHandlerCap,

    pub fn isValid(self: Capability) bool {
        return self != .null_cap;
    }
};

/// 与 `struct cap { uint64_t words[2]; }` 一致。
pub const CapRaw = extern struct {
    words: [2]u64,

    pub fn capType(self: CapRaw) u5 {
        return @truncate(self.words[0] >> 59);
    }

    pub fn nullCap() CapRaw {
        return .{ .words = .{ 0, 0 } };
    }
};

/// 与 `build-sel4-zig/generated/arch/object/structures_gen.h` 中 `enum cap_tag` 数值一致（节选）。
pub const cap_null_cap: u5 = 0;
pub const cap_frame_cap: u5 = 1;
pub const cap_untyped_cap: u5 = 2;
pub const cap_page_table_cap: u5 = 3;
pub const cap_endpoint_cap: u5 = 4;
pub const cap_page_directory_cap: u5 = 5;
pub const cap_notification_cap: u5 = 6;
pub const cap_pdpt_cap: u5 = 7;
pub const cap_reply_cap: u5 = 8;
pub const cap_pml4_cap: u5 = 9;
pub const cap_cnode_cap: u5 = 10;
pub const cap_asid_control_cap: u5 = 11;
pub const cap_thread_cap: u5 = 12;
pub const cap_asid_pool_cap: u5 = 13;
pub const cap_irq_control_cap: u5 = 14;
pub const cap_io_space_cap: u5 = 15;
pub const cap_irq_handler_cap: u5 = 16;
pub const cap_io_page_table_cap: u5 = 17;
pub const cap_zombie_cap: u5 = 18;
pub const cap_io_port_cap: u5 = 19;
pub const cap_domain_cap: u5 = 20;
pub const cap_io_port_control_cap: u5 = 31;

test "capability tagged union" {
    const c = Capability{ .null_cap = {} };
    try std.testing.expect(!c.isValid());
    const u: Capability = .{ .untyped = .{ .bits = 1 } };
    try std.testing.expect(u.isValid());
    const n: Capability = .{ .notification = .{ .bits = 0 } };
    try std.testing.expect(n.isValid());
}

test "cap raw matches seL4 cap_t layout" {
    try std.testing.expect(@sizeOf(CapRaw) == 16);
    try std.testing.expect(@alignOf(CapRaw) == 8);
    const z = CapRaw.nullCap();
    try std.testing.expectEqual(@as(u5, 0), z.capType());
}

test "cap tag constants sample" {
    try std.testing.expectEqual(@as(u5, 0), cap_null_cap);
    try std.testing.expectEqual(@as(u5, 12), cap_thread_cap);
}
