//! Native Zig objects for the serialized non-MCS kernel core.
//! These types model seL4 semantics; they are not the generated C object ABI.
const std = @import("std");

pub const Word = u64;
pub const max_message_words = 120;
pub const max_extra_caps = 3;

/// Exactly the upstream 64-bit wire layout; native objects remain private.
pub const IPCBuffer = extern struct {
    tag: MessageInfo = .{},
    msg: [120]u64 = @splat(0),
    userData: u64 = 0,
    caps_or_badges: [3]u64 = @splat(0),
    receiveCNode: u64 = 0,
    receiveIndex: u64 = 0,
    receiveDepth: u64 = 0,
};
comptime {
    std.debug.assert(@sizeOf(IPCBuffer) == 1024);
}

pub const Rights = struct {
    read: bool = true,
    write: bool = true,
    grant: bool = true,
    grant_reply: bool = true,

    pub fn intersect(a: Rights, b: Rights) Rights {
        return .{ .read = a.read and b.read, .write = a.write and b.write, .grant = a.grant and b.grant, .grant_reply = a.grant_reply and b.grant_reply };
    }
};

pub const MessageInfo = extern struct {
    words: [1]Word = .{0},

    pub fn init(msg_label: u52, caps_unwrapped: u3, extra_caps: u2, msg_length: u7) MessageInfo {
        return .{ .words = .{(@as(Word, msg_label) << 12) | (@as(Word, caps_unwrapped) << 9) | (@as(Word, extra_caps) << 7) | msg_length} };
    }
    pub fn label(self: MessageInfo) u52 {
        return @truncate(self.words[0] >> 12);
    }
    pub fn length(self: MessageInfo) usize {
        return @min(self.words[0] & 0x7f, max_message_words);
    }
    pub fn extraCaps(self: MessageInfo) u2 {
        return @truncate(self.words[0] >> 7);
    }
    pub fn capsUnwrapped(self: MessageInfo) u3 {
        return @truncate(self.words[0] >> 9);
    }
};

pub const CNodeCap = struct {
    slots: []Slot,
    radix: u6,
    guard: Word = 0,
    guard_size: u7 = 0,

    pub fn init(slots: []Slot, guard: Word, guard_size: u7) error{InvalidCNode}!CNodeCap {
        if (slots.len < 2 or !std.math.isPowerOfTwo(slots.len)) return error.InvalidCNode;
        const radix: u6 = @intCast(std.math.log2_int(usize, slots.len));
        if (@as(u8, radix) + guard_size > 64 or guard & ~mask(guard_size) != 0) return error.InvalidCNode;
        return .{ .slots = slots, .radix = radix, .guard = guard, .guard_size = guard_size };
    }
};
pub const EndpointCap = struct { object: *Endpoint, badge: Word = 0, rights: Rights = .{} };
pub const NotificationCap = struct { object: *Notification, badge: Word = 0, rights: Rights = .{} };
pub const UntypedCap = struct { memory: []align(16) u8, free_offset: usize = 0, device: bool = false };
pub const FrameCap = struct { memory: []align(16) u8, rights: Rights = .{}, device: bool = false };
pub const ReplyCap = struct { thread: *Thread, can_grant: bool = false };

pub const Capability = union(enum) {
    null_cap: void,
    untyped: UntypedCap,
    endpoint: EndpointCap,
    notification: NotificationCap,
    tcb: *Thread,
    cnode: CNodeCap,
    reply: ReplyCap,
    frame: FrameCap,
    irq_control: void,
    irq_handler: u16,
    domain: void,

    pub fn isValid(self: Capability) bool {
        return self != .null_cap;
    }
};

/// Intrusive mapping database, ordered exactly as capability insertion requires.
pub const Slot = struct {
    cap: Capability = .{ .null_cap = {} },
    prev: ?*Slot = null,
    next: ?*Slot = null,
    revocable: bool = false,
    first_badged: bool = false,

    /// Install bootstrap authority into an unlinked native slot.
    pub fn initRoot(cap: Capability) Slot {
        return .{ .cap = cap, .revocable = true, .first_badged = true };
    }

    pub fn isEmpty(self: *const Slot) bool {
        return self.cap == .null_cap and self.prev == null and self.next == null;
    }
};

pub const ThreadState = enum { inactive, running, restart, blocked_send, blocked_receive, blocked_notification, blocked_reply, blocked_mutex, idle };
pub const Fault = union(enum) {
    none: void,
    capability: struct { address: Word, in_receive: bool, lookup_type: Word = 2, bits_left: Word = 0, guard_found: Word = 0, bits_found: Word = 0 },
    unknown_syscall: i64,
    vm: struct { address: Word, status: Word, instruction: bool },
    user_exception: struct { number: Word, code: Word },
};

pub const Thread = struct {
    state: ThreadState = .inactive,
    /// Published only after the runtime has installed a user frame and VSpace.
    /// A retyped TCB has no hardware context and must never enter a run queue.
    user_context_ready: bool = false,
    priority: u8 = 0,
    /// Runnable placement and exclusive hardware execution ownership.
    affinity: u64 = ~@as(u64, 0),
    owner_cpu: ?u6 = null,
    max_controlled_priority: u8 = 0,
    time_slice: u32 = 5,
    cspace: Capability = .{ .null_cap = {} },
    message_info: MessageInfo = .{},
    message: [max_message_words]Word = @splat(0),
    /// Only four words are available without an IPC buffer.
    has_ipc_buffer: bool = false,
    extra_caps: [max_extra_caps]?*Slot = @splat(null),
    /// First unresolved extra CPtr, retained until Send/Call validates its target.
    extra_cap_fault: ?Word = null,
    receive_slot: ?*Slot = null,
    caps_or_badges: [max_extra_caps]Word = @splat(0),
    badge: Word = 0,
    fault: Fault = .{ .none = {} },
    fault_handler: Word = 0,
    fault_pc: Word = 0,
    /// Architecture-selected upstream fault register order, separate from IPC data.
    fault_registers: [18]Word = @splat(0),
    fault_register_count: u8 = 0,
    fault_reply_pending: bool = false,
    endpoint: ?*Endpoint = null,
    notification: ?*Notification = null,
    bound_notification: ?*Notification = null,
    pending_badge: Word = 0,
    pending_rights: Rights = .{},
    pending_call: bool = false,
    /// A non-MCS reply authority is single-use and owned by one server.
    caller: ?*Thread = null,
    reply_owner: ?*Thread = null,
    /// A saved reply moves authority from the server link to exactly one CSpace slot.
    saved_reply_slot: ?*Slot = null,
    reply_can_grant: bool = false,
    ready_prev: ?*Thread = null,
    ready_next: ?*Thread = null,
    queued: bool = false,
    wait_prev: ?*Thread = null,
    wait_next: ?*Thread = null,
    wait_mutex: ?*Mutex = null,
    owned_mutexes: ?*Mutex = null,

    pub fn isRunnable(self: *const Thread) bool {
        return self.state == .running or self.state == .restart;
    }
};

/// Endpoint and notification queues are FIFO in the non-MCS configuration.
pub const WaitQueue = struct {
    head: ?*Thread = null,
    tail: ?*Thread = null,

    pub fn append(self: *WaitQueue, thread: *Thread) void {
        std.debug.assert(thread.wait_prev == null and thread.wait_next == null and self.tail != thread);
        thread.wait_prev = self.tail;
        if (self.tail) |tail| tail.wait_next = thread else self.head = thread;
        self.tail = thread;
    }
    pub fn remove(self: *WaitQueue, thread: *Thread) void {
        if (thread.wait_prev) |prev| prev.wait_next = thread.wait_next else {
            std.debug.assert(self.head == thread);
            self.head = thread.wait_next;
        }
        if (thread.wait_next) |next| next.wait_prev = thread.wait_prev else {
            std.debug.assert(self.tail == thread);
            self.tail = thread.wait_prev;
        }
        thread.wait_prev = null;
        thread.wait_next = null;
    }
    pub fn pop(self: *WaitQueue) ?*Thread {
        const thread = self.head orelse return null;
        self.remove(thread);
        return thread;
    }
};
pub const Endpoint = struct { state: enum { idle, send, receive } = .idle, queue: WaitQueue = .{} };
/// Internal sleeping mutex, not an additional seL4 capability/object type.
pub const Mutex = struct {
    owner: ?*Thread = null,
    waiters: WaitQueue = .{},
    owned_prev: ?*Mutex = null,
    owned_next: ?*Mutex = null,
};
pub const Notification = struct {
    state: enum { idle, waiting, active } = .idle,
    badge: Word = 0,
    queue: WaitQueue = .{},
    bound: ?*Thread = null,
};

pub fn mask(bits: u7) Word {
    return if (bits >= 64) std.math.maxInt(Word) else (@as(Word, 1) << @as(u6, @intCast(bits))) - 1;
}
