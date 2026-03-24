//! 与 [arch/x86_64/idt.zig](../arch/x86_64/idt.zig) 单一真源；裸机侧仅 re-export。
pub const IdtEntry = @import("../arch/x86_64/idt.zig").IdtEntry;
