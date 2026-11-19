//! x86_64 non-MCS syscall register convention.
pub const Result = struct { badge: u64, info: u64, words: [4]u64 };
pub inline fn invoke(number: i64, destination: u64, info: u64, words: [4]u64) Result {
    var d = destination;
    var tag = info;
    var w0 = words[0];
    var w1 = words[1];
    var w2 = words[2];
    var w3 = words[3];
    asm volatile ("movq %%rsp, %%rbx; syscall; movq %%rbx, %%rsp"
        : [d] "+{rdi}" (d),
          [i] "+{rsi}" (tag),
          [m0] "+{r10}" (w0),
          [m1] "+{r8}" (w1),
          [m2] "+{r9}" (w2),
          [m3] "+{r15}" (w3),
        : [sc] "{rdx}" (@as(u64, @bitCast(number))),
        : .{ .rbx = true, .rcx = true, .r11 = true, .memory = true });
    return .{ .badge = d, .info = tag, .words = .{ w0, w1, w2, w3 } };
}
