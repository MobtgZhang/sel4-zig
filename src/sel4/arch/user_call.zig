//! Register-independent bootstrap request decoded by each exception adapter.
pub const Call = struct {
    value: u64,
    a: u64,
    b: u64,
    c: u64,
    words: [4]u64,
};
