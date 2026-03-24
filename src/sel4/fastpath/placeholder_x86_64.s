/* 阶段三 3.3：演示通过 build.zig `addAssemblyFile` 引入 .s（快路径最后迁移时的接线位）。 */
.text
.global sel4_zig_fastpath_asm_placeholder
.type sel4_zig_fastpath_asm_placeholder, @function
sel4_zig_fastpath_asm_placeholder:
    ret
.size sel4_zig_fastpath_asm_placeholder, .-sel4_zig_fastpath_asm_placeholder
.section .note.GNU-stack,"",@progbits
