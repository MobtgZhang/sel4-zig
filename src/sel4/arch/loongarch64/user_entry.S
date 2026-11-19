.section .text, "ax"
.balign 64
.global arch_user_vector
arch_user_vector:
    csrwr $sp, 0x30
    csrrd $sp, 0x31
    addi.d $sp, $sp, -544
    st.d $r1, $sp, 8
    st.d $r2, $sp, 16
    st.d $r4, $sp, 32
    st.d $r5, $sp, 40
    st.d $r6, $sp, 48
    st.d $r7, $sp, 56
    st.d $r8, $sp, 64
    st.d $r9, $sp, 72
    st.d $r10, $sp, 80
    st.d $r11, $sp, 88
    st.d $r12, $sp, 96
    st.d $r13, $sp, 104
    st.d $r14, $sp, 112
    st.d $r15, $sp, 120
    st.d $r16, $sp, 128
    st.d $r17, $sp, 136
    st.d $r18, $sp, 144
    st.d $r19, $sp, 152
    st.d $r20, $sp, 160
    st.d $r21, $sp, 168
    st.d $r22, $sp, 176
    st.d $r23, $sp, 184
    st.d $r24, $sp, 192
    st.d $r25, $sp, 200
    st.d $r26, $sp, 208
    st.d $r27, $sp, 216
    st.d $r28, $sp, 224
    st.d $r29, $sp, 232
    st.d $r30, $sp, 240
    st.d $r31, $sp, 248
    csrrd $t0, 0x30
    st.d $t0, $sp, 24
    csrrd $t0, 0x6
    st.d $t0, $sp, 256
    csrrd $t0, 0x1
    st.d $t0, $sp, 264
    fst.d $f0, $sp, 272
    fst.d $f1, $sp, 280
    fst.d $f2, $sp, 288
    fst.d $f3, $sp, 296
    fst.d $f4, $sp, 304
    fst.d $f5, $sp, 312
    fst.d $f6, $sp, 320
    fst.d $f7, $sp, 328
    fst.d $f8, $sp, 336
    fst.d $f9, $sp, 344
    fst.d $f10, $sp, 352
    fst.d $f11, $sp, 360
    fst.d $f12, $sp, 368
    fst.d $f13, $sp, 376
    fst.d $f14, $sp, 384
    fst.d $f15, $sp, 392
    fst.d $f16, $sp, 400
    fst.d $f17, $sp, 408
    fst.d $f18, $sp, 416
    fst.d $f19, $sp, 424
    fst.d $f20, $sp, 432
    fst.d $f21, $sp, 440
    fst.d $f22, $sp, 448
    fst.d $f23, $sp, 456
    fst.d $f24, $sp, 464
    fst.d $f25, $sp, 472
    fst.d $f26, $sp, 480
    fst.d $f27, $sp, 488
    fst.d $f28, $sp, 496
    fst.d $f29, $sp, 504
    fst.d $f30, $sp, 512
    fst.d $f31, $sp, 520
    movfcsr2gr $t0, $fcsr0
    st.d $t0, $sp, 528
    move $t0, $zero
    movcf2gr $t1, $fcc0
    bstrins.d $t0, $t1, 0, 0
    movcf2gr $t1, $fcc1
    bstrins.d $t0, $t1, 1, 1
    movcf2gr $t1, $fcc2
    bstrins.d $t0, $t1, 2, 2
    movcf2gr $t1, $fcc3
    bstrins.d $t0, $t1, 3, 3
    movcf2gr $t1, $fcc4
    bstrins.d $t0, $t1, 4, 4
    movcf2gr $t1, $fcc5
    bstrins.d $t0, $t1, 5, 5
    movcf2gr $t1, $fcc6
    bstrins.d $t0, $t1, 6, 6
    movcf2gr $t1, $fcc7
    bstrins.d $t0, $t1, 7, 7
    st.d $t0, $sp, 536
    move $a0, $sp
    bl terminal_arch_dispatch
    b arch_user_restore
.global arch_user_restore
arch_user_restore:
    move $sp, $a0
    ld.d $t0, $sp, 256
    csrwr $t0, 0x6
    ld.d $t0, $sp, 264
    csrwr $t0, 0x1
    ld.d $t0, $sp, 528
    movgr2fcsr $fcsr0, $t0
    ld.d $t0, $sp, 536
    srli.d $t1, $t0, 0
    movgr2cf $fcc0, $t1
    srli.d $t1, $t0, 1
    movgr2cf $fcc1, $t1
    srli.d $t1, $t0, 2
    movgr2cf $fcc2, $t1
    srli.d $t1, $t0, 3
    movgr2cf $fcc3, $t1
    srli.d $t1, $t0, 4
    movgr2cf $fcc4, $t1
    srli.d $t1, $t0, 5
    movgr2cf $fcc5, $t1
    srli.d $t1, $t0, 6
    movgr2cf $fcc6, $t1
    srli.d $t1, $t0, 7
    movgr2cf $fcc7, $t1
    fld.d $f0, $sp, 272
    fld.d $f1, $sp, 280
    fld.d $f2, $sp, 288
    fld.d $f3, $sp, 296
    fld.d $f4, $sp, 304
    fld.d $f5, $sp, 312
    fld.d $f6, $sp, 320
    fld.d $f7, $sp, 328
    fld.d $f8, $sp, 336
    fld.d $f9, $sp, 344
    fld.d $f10, $sp, 352
    fld.d $f11, $sp, 360
    fld.d $f12, $sp, 368
    fld.d $f13, $sp, 376
    fld.d $f14, $sp, 384
    fld.d $f15, $sp, 392
    fld.d $f16, $sp, 400
    fld.d $f17, $sp, 408
    fld.d $f18, $sp, 416
    fld.d $f19, $sp, 424
    fld.d $f20, $sp, 432
    fld.d $f21, $sp, 440
    fld.d $f22, $sp, 448
    fld.d $f23, $sp, 456
    fld.d $f24, $sp, 464
    fld.d $f25, $sp, 472
    fld.d $f26, $sp, 480
    fld.d $f27, $sp, 488
    fld.d $f28, $sp, 496
    fld.d $f29, $sp, 504
    fld.d $f30, $sp, 512
    fld.d $f31, $sp, 520
    ld.d $r1, $sp, 8
    ld.d $r2, $sp, 16
    ld.d $r4, $sp, 32
    ld.d $r5, $sp, 40
    ld.d $r6, $sp, 48
    ld.d $r7, $sp, 56
    ld.d $r8, $sp, 64
    ld.d $r9, $sp, 72
    ld.d $r10, $sp, 80
    ld.d $r11, $sp, 88
    ld.d $r12, $sp, 96
    ld.d $r13, $sp, 104
    ld.d $r14, $sp, 112
    ld.d $r15, $sp, 120
    ld.d $r16, $sp, 128
    ld.d $r17, $sp, 136
    ld.d $r18, $sp, 144
    ld.d $r19, $sp, 152
    ld.d $r20, $sp, 160
    ld.d $r21, $sp, 168
    ld.d $r22, $sp, 176
    ld.d $r23, $sp, 184
    ld.d $r24, $sp, 192
    ld.d $r25, $sp, 200
    ld.d $r26, $sp, 208
    ld.d $r27, $sp, 216
    ld.d $r28, $sp, 224
    ld.d $r29, $sp, 232
    ld.d $r30, $sp, 240
    ld.d $r31, $sp, 248
    ld.d $sp, $sp, 24
    ertn
.balign 4096
.global arch_tlb_refill
arch_tlb_refill:
    csrwr $t0, 0x8b
    csrwr $t1, 0x32
    csrwr $t2, 0x33
    csrrd $t0, 0x19
    csrrd $t1, 0x89
    srli.d $t2, $t1, 30
    andi $t2, $t2, 511
    slli.d $t2, $t2, 3
    add.d $t0, $t0, $t2
    ld.d $t0, $t0, 0
    beqz $t0, arch_refill_invalid
    srli.d $t2, $t1, 21
    andi $t2, $t2, 511
    slli.d $t2, $t2, 3
    add.d $t0, $t0, $t2
    ld.d $t0, $t0, 0
    beqz $t0, arch_refill_invalid
    srli.d $t2, $t1, 12
    andi $t2, $t2, 510
    slli.d $t2, $t2, 3
    add.d $t0, $t0, $t2
    ld.d $t1, $t0, 0
    ld.d $t2, $t0, 8
    b arch_refill_pair
arch_refill_invalid:
    move $t1, $zero
    move $t2, $zero
arch_refill_pair:
    csrwr $t1, 0x8c
    csrwr $t2, 0x8d
    csrrd $t0, 0x89
    srli.d $t0, $t0, 13
    slli.d $t0, $t0, 13
    ori $t0, $t0, 12
    csrwr $t0, 0x8e
    tlbfill
    csrrd $t2, 0x33
    csrrd $t1, 0x32
    csrrd $t0, 0x8b
    ertn
.section .bss, "aw", @nobits
.balign 16
.space 262144
arch_kernel_stack_top:
