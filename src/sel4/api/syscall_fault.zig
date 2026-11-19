//! Convert syscall lookup failures into standard capability fault messages.
const s = @import("../model/structures.zig");
const cspace = @import("../kernel/cspace.zig");
const nums = @import("syscall_numbers.zig");
pub fn lookup(thread: *s.Thread, number: i64, cptr: u64) void {
    var fault: @FieldType(s.Fault, "capability") = .{
        .address = cptr,
        .in_receive = number == nums.seL4_SysRecv or number == nums.seL4_SysNBRecv or number == nums.seL4_SysReplyRecv,
    };
    switch (cspace.resolveAddressBits(thread.cspace, cptr, 64)) {
        .found => |found| {
            fault.lookup_type = 2;
            fault.bits_left = found.bits_remaining;
        },
        .fault => |failure| switch (failure) {
            .invalid_root, .invalid_depth => fault.lookup_type = 1,
            .depth_mismatch => |depth| {
                fault.lookup_type = 3;
                fault.bits_left = depth.bits_left;
                fault.bits_found = depth.bits_found;
            },
            .guard_mismatch => |guard| {
                fault.lookup_type = 4;
                fault.bits_left = guard.bits_left;
                fault.guard_found = guard.expected;
                fault.bits_found = guard.guard_size;
            },
        },
    }
    thread.fault = .{ .capability = fault };
}
