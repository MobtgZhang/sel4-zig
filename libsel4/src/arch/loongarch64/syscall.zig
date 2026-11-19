//! loongarch64 non-MCS syscall register convention.
//! LoongArch is a project extension; upstream seL4 has no LoongArch ABI.
pub const Result = struct { badge: u64, info: u64, words: [4]u64 };
pub inline fn invoke(number: i64, destination: u64, info: u64, words: [4]u64) Result {
    var d = destination;
    var tag = info;
    var w0 = words[0];
    var w1 = words[1];
    var w2 = words[2];
    var w3 = words[3];
    asm volatile ("syscall 0"
        : [d] "+{r4}" (d),
          [i] "+{r5}" (tag),
          [m0] "+{r6}" (w0),
          [m1] "+{r7}" (w1),
          [m2] "+{r8}" (w2),
          [m3] "+{r9}" (w3),
        : [sc] "{r11}" (@as(u64, @bitCast(number))),
        : .{ .memory = true });
    return .{ .badge = d, .info = tag, .words = .{ w0, w1, w2, w3 } };
}
