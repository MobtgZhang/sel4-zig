//! Architecture-independent classification after controller claim.
pub const Event = union(enum) { timer, ipi, device: u16, spurious };
