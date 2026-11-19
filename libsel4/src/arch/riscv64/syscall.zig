//! riscv64 non-MCS syscall register convention.
pub const Result = struct { badge: u64, info: u64, words: [4]u64 };
pub inline fn invoke(number: i64, destination: u64, info: u64, words: [4]u64) Result {
    var d = destination;
    var tag = info;
    var w0 = words[0];
    var w1 = words[1];
    var w2 = words[2];
    var w3 = words[3];
    asm volatile ("ecall"
        : [d] "+{a0}" (d),
          [i] "+{a1}" (tag),
          [m0] "+{a2}" (w0),
          [m1] "+{a3}" (w1),
          [m2] "+{a4}" (w2),
          [m3] "+{a5}" (w3),
        : [sc] "{a7}" (@as(u64, @bitCast(number))),
        : .{ .memory = true });
    return .{ .badge = d, .info = tag, .words = .{ w0, w1, w2, w3 } };
}
