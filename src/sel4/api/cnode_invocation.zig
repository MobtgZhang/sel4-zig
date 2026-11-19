//! Decode CNode methods separately from slot mutation and object finalization.
const s = @import("../model/structures.zig");
const Kernel = @import("../kernel/runtime.zig").Kernel;
const invocation = @import("invocation.zig");
const Request = invocation.Request;
const Error = invocation.Error;
const labels = @import("invocation_labels.zig");
const cnode = @import("../object/cnode.zig");
const caps = @import("../model/capability.zig");

pub fn decode(kernel: *Kernel, request: *Request, root: s.Capability, label: u52) Error!void {
    if (label < labels.CNodeRevoke or label > labels.CNodeSaveCaller) return error.IllegalOperation;
    try request.require(2, 0);
    const dest = try request.slot(root, request.arg(0), request.arg(1) & 0xff, false);
    switch (label) {
        labels.CNodeRevoke => kernel.revoke(dest),
        labels.CNodeDelete => kernel.delete(dest),
        labels.CNodeSaveCaller => try @import("../object/reply.zig").save(request.thread, dest),
        labels.CNodeCancelBadgedSends => {
            if (dest.cap != .endpoint) return error.IllegalOperation;
            const cap = dest.cap.endpoint;
            if (!cap.rights.read or !cap.rights.write or !cap.rights.grant or !cap.rights.grant_reply) return error.IllegalOperation;
            @import("../object/endpoint.zig").cancelBadgedSends(&kernel.scheduler, cap.object, cap.badge);
        },
        labels.CNodeRotate => try rotate(request, dest),
        else => {
            const length: usize = switch (label) {
                labels.CNodeMint => 6,
                labels.CNodeCopy, labels.CNodeMutate => 5,
                else => 4,
            };
            try request.require(length, 1);
            if (!dest.isEmpty()) return error.DeleteFirst;
            const source = try request.slot(request.extra(0), request.arg(2), request.arg(3) & 0xff, true);
            if (!source.cap.isValid()) return request.missingCap(true, request.arg(3) & 0xff);
            switch (label) {
                labels.CNodeCopy => try cnode.copy(source, dest, invocation.rights(request.arg(4))),
                labels.CNodeMint => try cnode.mint(source, dest, invocation.rights(request.arg(4)), request.arg(5)),
                labels.CNodeMove => try cnode.move(source, dest),
                labels.CNodeMutate => {
                    // Preserve existing authority: endpoint badges cannot be changed by Mutate.
                    const updated = try caps.updateData(source.cap, true, request.arg(4));
                    try cnode.move(source, dest);
                    dest.cap = updated;
                },
                else => unreachable,
            }
        },
    }
}

fn rotate(request: *Request, dest: *s.Slot) Error!void {
    try request.require(8, 2);
    const pivot = try request.slot(request.extra(0), request.arg(3), request.arg(4) & 0xff, true);
    const source = try request.slot(request.extra(1), request.arg(6), request.arg(7) & 0xff, true);
    if (pivot == source or pivot == dest) return error.IllegalOperation;
    if (source != dest and !dest.isEmpty()) return error.DeleteFirst;
    if (!source.cap.isValid()) return request.missingCap(true, request.arg(7) & 0xff);
    if (!pivot.cap.isValid()) return request.missingCap(false, request.arg(4) & 0xff);
    const source_cap = try caps.updateData(source.cap, true, request.arg(5));
    const pivot_cap = try caps.updateData(pivot.cap, true, request.arg(2));
    try cnode.rotate(source, pivot, dest, source_cap, pivot_cap);
}
