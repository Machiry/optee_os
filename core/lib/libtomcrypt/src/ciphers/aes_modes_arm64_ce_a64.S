/*
 * Copyright (c) 2015, Linaro Limited
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 * this list of conditions and the following disclaimer in the documentation
 * and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

/*
 * - AES cipher for ARMv8 with Crypto Extensions
 * - Chaining mode wrappers for AES
 *
 * Copyright (C) 2013 Linaro Ltd <ard.biesheuvel@linaro.org>
 */


#define ENTRY(func) \
	.global func ; \
	.type func , %function ; \
	func :

#define ENDPROC(func) \
	.size func , .-func

	.arch		armv8-a+crypto

	/* preload all round keys */
	.macro		load_round_keys, rounds, rk
	cmp		\rounds, #12
	blo		2222f		/* 128 bits */
	beq		1111f		/* 192 bits */
	ld1		{v17.16b-v18.16b}, [\rk], #32
1111:	ld1		{v19.16b-v20.16b}, [\rk], #32
2222:	ld1		{v21.16b-v24.16b}, [\rk], #64
	ld1		{v25.16b-v28.16b}, [\rk], #64
	ld1		{v29.16b-v31.16b}, [\rk]
	.endm

	/* prepare for encryption with key in rk[] */
	.macro		enc_prepare, rounds, rk, ignore
	load_round_keys	\rounds, \rk
	.endm

	/* prepare for encryption (again) but with new key in rk[] */
	.macro		enc_switch_key, rounds, rk, ignore
	load_round_keys	\rounds, \rk
	.endm

	/* prepare for decryption with key in rk[] */
	.macro		dec_prepare, rounds, rk, ignore
	load_round_keys	\rounds, \rk
	.endm

	.macro		do_enc_Nx, de, mc, k, i0, i1, i2, i3
	aes\de		\i0\().16b, \k\().16b
	aes\mc		\i0\().16b, \i0\().16b
	.ifnb		\i1
	aes\de		\i1\().16b, \k\().16b
	aes\mc		\i1\().16b, \i1\().16b
	.ifnb		\i3
	aes\de		\i2\().16b, \k\().16b
	aes\mc		\i2\().16b, \i2\().16b
	aes\de		\i3\().16b, \k\().16b
	aes\mc		\i3\().16b, \i3\().16b
	.endif
	.endif
	.endm

	/* up to 4 interleaved encryption rounds with the same round key */
	.macro		round_Nx, enc, k, i0, i1, i2, i3
	.ifc		\enc, e
	do_enc_Nx	e, mc, \k, \i0, \i1, \i2, \i3
	.else
	do_enc_Nx	d, imc, \k, \i0, \i1, \i2, \i3
	.endif
	.endm

	/* up to 4 interleaved final rounds */
	.macro		fin_round_Nx, de, k, k2, i0, i1, i2, i3
	aes\de		\i0\().16b, \k\().16b
	.ifnb		\i1
	aes\de		\i1\().16b, \k\().16b
	.ifnb		\i3
	aes\de		\i2\().16b, \k\().16b
	aes\de		\i3\().16b, \k\().16b
	.endif
	.endif
	eor		\i0\().16b, \i0\().16b, \k2\().16b
	.ifnb		\i1
	eor		\i1\().16b, \i1\().16b, \k2\().16b
	.ifnb		\i3
	eor		\i2\().16b, \i2\().16b, \k2\().16b
	eor		\i3\().16b, \i3\().16b, \k2\().16b
	.endif
	.endif
	.endm

	/* up to 4 interleaved blocks */
	.macro		do_block_Nx, enc, rounds, i0, i1, i2, i3
	cmp		\rounds, #12
	blo		2222f		/* 128 bits */
	beq		1111f		/* 192 bits */
	round_Nx	\enc, v17, \i0, \i1, \i2, \i3
	round_Nx	\enc, v18, \i0, \i1, \i2, \i3
1111:	round_Nx	\enc, v19, \i0, \i1, \i2, \i3
	round_Nx	\enc, v20, \i0, \i1, \i2, \i3
2222:	.irp		key, v21, v22, v23, v24, v25, v26, v27, v28, v29
	round_Nx	\enc, \key, \i0, \i1, \i2, \i3
	.endr
	fin_round_Nx	\enc, v30, v31, \i0, \i1, \i2, \i3
	.endm

	.macro		encrypt_block, in, rounds, t0, t1, t2
	do_block_Nx	e, \rounds, \in
	.endm

	.macro		encrypt_block2x, i0, i1, rounds, t0, t1, t2
	do_block_Nx	e, \rounds, \i0, \i1
	.endm

	.macro		encrypt_block4x, i0, i1, i2, i3, rounds, t0, t1, t2
	do_block_Nx	e, \rounds, \i0, \i1, \i2, \i3
	.endm

	.macro		decrypt_block, in, rounds, t0, t1, t2
	do_block_Nx	d, \rounds, \in
	.endm

	.macro		decrypt_block2x, i0, i1, rounds, t0, t1, t2
	do_block_Nx	d, \rounds, \i0, \i1
	.endm

	.macro		decrypt_block4x, i0, i1, i2, i3, rounds, t0, t1, t2
	do_block_Nx	d, \rounds, \i0, \i1, \i2, \i3
	.endm


	.text
	.align		4

/*
 * There are several ways to instantiate this code:
 * - no interleave, all inline
 * - 2-way interleave, 2x calls out of line (-DINTERLEAVE=2)
 * - 2-way interleave, all inline (-DINTERLEAVE=2 -DINTERLEAVE_INLINE)
 * - 4-way interleave, 4x calls out of line (-DINTERLEAVE=4)
 * - 4-way interleave, all inline (-DINTERLEAVE=4 -DINTERLEAVE_INLINE)
 *
 * Macros imported by this code:
 * - enc_prepare	- setup NEON registers for encryption
 * - dec_prepare	- setup NEON registers for decryption
 * - enc_switch_key	- change to new key after having prepared for encryption
 * - encrypt_block	- encrypt a single block
 * - decrypt block	- decrypt a single block
 * - encrypt_block2x	- encrypt 2 blocks in parallel (if INTERLEAVE == 2)
 * - decrypt_block2x	- decrypt 2 blocks in parallel (if INTERLEAVE == 2)
 * - encrypt_block4x	- encrypt 4 blocks in parallel (if INTERLEAVE == 4)
 * - decrypt_block4x	- decrypt 4 blocks in parallel (if INTERLEAVE == 4)
 */

#if defined(INTERLEAVE) && !defined(INTERLEAVE_INLINE)
#define FRAME_PUSH	stp x29, x30, [sp,#-16]! ; mov x29, sp
#define FRAME_POP	ldp x29, x30, [sp],#16

#if INTERLEAVE == 2

aes_encrypt_block2x:
	encrypt_block2x	v0, v1, w3, x2, x6, w7
	ret
ENDPROC(aes_encrypt_block2x)

aes_decrypt_block2x:
	decrypt_block2x	v0, v1, w3, x2, x6, w7
	ret
ENDPROC(aes_decrypt_block2x)

#elif INTERLEAVE == 4

aes_encrypt_block4x:
	encrypt_block4x	v0, v1, v2, v3, w3, x2, x6, w7
	ret
ENDPROC(aes_encrypt_block4x)

aes_decrypt_block4x:
	decrypt_block4x	v0, v1, v2, v3, w3, x2, x6, w7
	ret
ENDPROC(aes_decrypt_block4x)

#else
#error INTERLEAVE should equal 2 or 4
#endif

	.macro		do_encrypt_block2x
	bl		aes_encrypt_block2x
	.endm

	.macro		do_decrypt_block2x
	bl		aes_decrypt_block2x
	.endm

	.macro		do_encrypt_block4x
	bl		aes_encrypt_block4x
	.endm

	.macro		do_decrypt_block4x
	bl		aes_decrypt_block4x
	.endm

#else
#define FRAME_PUSH
#define FRAME_POP

	.macro		do_encrypt_block2x
	encrypt_block2x	v0, v1, w3, x2, x6, w7
	.endm

	.macro		do_decrypt_block2x
	decrypt_block2x	v0, v1, w3, x2, x6, w7
	.endm

	.macro		do_encrypt_block4x
	encrypt_block4x	v0, v1, v2, v3, w3, x2, x6, w7
	.endm

	.macro		do_decrypt_block4x
	decrypt_block4x	v0, v1, v2, v3, w3, x2, x6, w7
	.endm

#endif

	/*
	 * ce_aes_ecb_encrypt(u8 out[], u8 const in[], u8 const rk[],
	 *                    int rounds, int blocks, int first)
	 * ce_aes_ecb_decrypt(u8 out[], u8 const in[], u8 const rk[],
	 *                    int rounds, int blocks, int first)
	 */

ENTRY(ce_aes_ecb_encrypt)
	FRAME_PUSH
	cbz		w5, .LecbencloopNx

	enc_prepare	w3, x2, x5

.LecbencloopNx:
#if INTERLEAVE >= 2
	subs		w4, w4, #INTERLEAVE
	bmi		.Lecbenc1x
#if INTERLEAVE == 2
	ld1		{v0.16b-v1.16b}, [x1], #32	/* get 2 pt blocks */
	do_encrypt_block2x
	st1		{v0.16b-v1.16b}, [x0], #32
#else
	ld1		{v0.16b-v3.16b}, [x1], #64	/* get 4 pt blocks */
	do_encrypt_block4x
	st1		{v0.16b-v3.16b}, [x0], #64
#endif
	b		.LecbencloopNx
.Lecbenc1x:
	adds		w4, w4, #INTERLEAVE
	beq		.Lecbencout
#endif
.Lecbencloop:
	ld1		{v0.16b}, [x1], #16		/* get next pt block */
	encrypt_block	v0, w3, x2, x5, w6
	st1		{v0.16b}, [x0], #16
	subs		w4, w4, #1
	bne		.Lecbencloop
.Lecbencout:
	FRAME_POP
	ret
ENDPROC(ce_aes_ecb_encrypt)


ENTRY(ce_aes_ecb_decrypt)
	FRAME_PUSH
	cbz		w5, .LecbdecloopNx

	dec_prepare	w3, x2, x5

.LecbdecloopNx:
#if INTERLEAVE >= 2
	subs		w4, w4, #INTERLEAVE
	bmi		.Lecbdec1x
#if INTERLEAVE == 2
	ld1		{v0.16b-v1.16b}, [x1], #32	/* get 2 ct blocks */
	do_decrypt_block2x
	st1		{v0.16b-v1.16b}, [x0], #32
#else
	ld1		{v0.16b-v3.16b}, [x1], #64	/* get 4 ct blocks */
	do_decrypt_block4x
	st1		{v0.16b-v3.16b}, [x0], #64
#endif
	b		.LecbdecloopNx
.Lecbdec1x:
	adds		w4, w4, #INTERLEAVE
	beq		.Lecbdecout
#endif
.Lecbdecloop:
	ld1		{v0.16b}, [x1], #16		/* get next ct block */
	decrypt_block	v0, w3, x2, x5, w6
	st1		{v0.16b}, [x0], #16
	subs		w4, w4, #1
	bne		.Lecbdecloop
.Lecbdecout:
	FRAME_POP
	ret
ENDPROC(ce_aes_ecb_decrypt)


	/*
	 * aes_cbc_encrypt(u8 out[], u8 const in[], u8 const rk[], int rounds,
	 *		   int blocks, u8 iv[], int first)
	 * aes_cbc_decrypt(u8 out[], u8 const in[], u8 const rk[], int rounds,
	 *		   int blocks, u8 iv[], int first)
	 */

ENTRY(ce_aes_cbc_encrypt)
	cbz		w6, .Lcbcencloop

	ld1		{v0.16b}, [x5]			/* get iv */
	enc_prepare	w3, x2, x5

.Lcbcencloop:
	ld1		{v1.16b}, [x1], #16		/* get next pt block */
	eor		v0.16b, v0.16b, v1.16b		/* ..and xor with iv */
	encrypt_block	v0, w3, x2, x5, w6
	st1		{v0.16b}, [x0], #16
	subs		w4, w4, #1
	bne		.Lcbcencloop
	st1		{v0.16b}, [x5]			/* save iv for later */
	ret
ENDPROC(ce_aes_cbc_encrypt)


ENTRY(ce_aes_cbc_decrypt)
	FRAME_PUSH
	cbz		w6, .LcbcdecloopNx

	ld1		{v7.16b}, [x5]			/* get iv */
	dec_prepare	w3, x2, x5

.LcbcdecloopNx:
#if INTERLEAVE >= 2
	subs		w4, w4, #INTERLEAVE
	bmi		.Lcbcdec1x
#if INTERLEAVE == 2
	ld1		{v0.16b-v1.16b}, [x1], #32	/* get 2 ct blocks */
	mov		v2.16b, v0.16b
	mov		v3.16b, v1.16b
	do_decrypt_block2x
	eor		v0.16b, v0.16b, v7.16b
	eor		v1.16b, v1.16b, v2.16b
	mov		v7.16b, v3.16b
	st1		{v0.16b-v1.16b}, [x0], #32
#else
	ld1		{v0.16b-v3.16b}, [x1], #64	/* get 4 ct blocks */
	mov		v4.16b, v0.16b
	mov		v5.16b, v1.16b
	mov		v6.16b, v2.16b
	do_decrypt_block4x
	sub		x1, x1, #16
	eor		v0.16b, v0.16b, v7.16b
	eor		v1.16b, v1.16b, v4.16b
	ld1		{v7.16b}, [x1], #16		/* reload 1 ct block */
	eor		v2.16b, v2.16b, v5.16b
	eor		v3.16b, v3.16b, v6.16b
	st1		{v0.16b-v3.16b}, [x0], #64
#endif
	b		.LcbcdecloopNx
.Lcbcdec1x:
	adds		w4, w4, #INTERLEAVE
	beq		.Lcbcdecout
#endif
.Lcbcdecloop:
	ld1		{v1.16b}, [x1], #16		/* get next ct block */
	mov		v0.16b, v1.16b			/* ...and copy to v0 */
	decrypt_block	v0, w3, x2, x5, w6
	eor		v0.16b, v0.16b, v7.16b		/* xor with iv => pt */
	mov		v7.16b, v1.16b			/* ct is next iv */
	st1		{v0.16b}, [x0], #16
	subs		w4, w4, #1
	bne		.Lcbcdecloop
.Lcbcdecout:
	st1		{v1.16b}, [x5]			/* save iv for later */
	FRAME_POP
	ret
ENDPROC(ce_aes_cbc_decrypt)


	/*
	 * aes_ctr_encrypt(u8 out[], u8 const in[], u8 const rk[], int rounds,
	 *		   int blocks, u8 ctr[], int first)
	 */

ENTRY(ce_aes_ctr_encrypt)
	FRAME_PUSH
	mov		x9, x5			/* save ctr pointer */
	cbnz		w6, .Lctrfirst		/* 1st time around? */
	umov		x5, v4.d[1]		/* keep swabbed ctr in reg */
	rev		x5, x5
#if INTERLEAVE >= 2
	cmn		w5, w4			/* 32 bit overflow? */
	bcs		.Lctrinc
	add		x5, x5, #1		/* increment BE ctr */
	b		.LctrincNx
#else
	b		.Lctrinc
#endif
.Lctrfirst:
	enc_prepare	w3, x2, x6
	ld1		{v4.16b}, [x5]
	umov		x5, v4.d[1]		/* keep swabbed ctr in reg */
	rev		x5, x5
#if INTERLEAVE >= 2
	cmn		w5, w4			/* 32 bit overflow? */
	bcs		.Lctrloop
.LctrloopNx:
	subs		w4, w4, #INTERLEAVE
	bmi		.Lctr1x
#if INTERLEAVE == 2
	mov		v0.8b, v4.8b
	mov		v1.8b, v4.8b
	rev		x7, x5
	add		x5, x5, #1
	ins		v0.d[1], x7
	rev		x7, x5
	add		x5, x5, #1
	ins		v1.d[1], x7
	ld1		{v2.16b-v3.16b}, [x1], #32	/* get 2 input blocks */
	do_encrypt_block2x
	eor		v0.16b, v0.16b, v2.16b
	eor		v1.16b, v1.16b, v3.16b
	st1		{v0.16b-v1.16b}, [x0], #32
#else
	ldr		q8, =0x30000000200000001	/* addends 1,2,3[,0] */
	dup		v7.4s, w5
	mov		v0.16b, v4.16b
	add		v7.4s, v7.4s, v8.4s
	mov		v1.16b, v4.16b
	rev32		v8.16b, v7.16b
	mov		v2.16b, v4.16b
	mov		v3.16b, v4.16b
	mov		v1.s[3], v8.s[0]
	mov		v2.s[3], v8.s[1]
	mov		v3.s[3], v8.s[2]
	ld1		{v5.16b-v7.16b}, [x1], #48	/* get 3 input blocks */
	do_encrypt_block4x
	eor		v0.16b, v5.16b, v0.16b
	ld1		{v5.16b}, [x1], #16		/* get 1 input block  */
	eor		v1.16b, v6.16b, v1.16b
	eor		v2.16b, v7.16b, v2.16b
	eor		v3.16b, v5.16b, v3.16b
	st1		{v0.16b-v3.16b}, [x0], #64
	add		x5, x5, #INTERLEAVE
#endif
	cbz		w4, .LctroutNx
.LctrincNx:
	rev		x7, x5
	ins		v4.d[1], x7
	b		.LctrloopNx
.LctroutNx:
	sub		x5, x5, #1
	rev		x7, x5
	ins		v4.d[1], x7
	b		.Lctrout
.Lctr1x:
	adds		w4, w4, #INTERLEAVE
	beq		.Lctrout
#endif
.Lctrloop:
	mov		v0.16b, v4.16b
	encrypt_block	v0, w3, x2, x6, w7
	subs		w4, w4, #1
	bmi		.Lctrhalfblock		/* blocks < 0 means 1/2 block */
	ld1		{v3.16b}, [x1], #16
	eor		v3.16b, v0.16b, v3.16b
	st1		{v3.16b}, [x0], #16
	beq		.Lctrout
.Lctrinc:
	adds		x5, x5, #1		/* increment BE ctr */
	rev		x7, x5
	ins		v4.d[1], x7
	bcc		.Lctrloop		/* no overflow? */
	umov		x7, v4.d[0]		/* load upper word of ctr  */
	rev		x7, x7			/* ... to handle the carry */
	add		x7, x7, #1
	rev		x7, x7
	ins		v4.d[0], x7
	b		.Lctrloop
.Lctrhalfblock:
	ld1		{v3.8b}, [x1]
	eor		v3.8b, v0.8b, v3.8b
	st1		{v3.8b}, [x0]
.Lctrout:
	st1		{v4.16b}, [x9]		/* save ctr for next call */
	FRAME_POP
	ret
ENDPROC(ce_aes_ctr_encrypt)
	.ltorg


	/*
	 * aes_xts_decrypt(u8 out[], u8 const in[], u8 const rk1[], int rounds,
	 *		   int blocks, u8 const rk2[], u8 iv[])
	 * aes_xts_decrypt(u8 out[], u8 const in[], u8 const rk1[], int rounds,
	 *		   int blocks, u8 const rk2[], u8 iv[])
	 */

	.macro		next_tweak, out, in, const, tmp
	sshr		\tmp\().2d,  \in\().2d,   #63
	and		\tmp\().16b, \tmp\().16b, \const\().16b
	add		\out\().2d,  \in\().2d,   \in\().2d
	ext		\tmp\().16b, \tmp\().16b, \tmp\().16b, #8
	eor		\out\().16b, \out\().16b, \tmp\().16b
	.endm

.Lxts_mul_x:
	.word		1, 0, 0x87, 0

ENTRY(ce_aes_xts_encrypt)
	FRAME_PUSH

	ld1		{v4.16b}, [x6]
	enc_prepare	w3, x5, x6
	encrypt_block	v4, w3, x5, x6, w7		/* first tweak */
	enc_switch_key	w3, x2, x6
	ldr		q7, .Lxts_mul_x
	b		.LxtsencNx

.LxtsencloopNx:
	ldr		q7, .Lxts_mul_x
	next_tweak	v4, v4, v7, v8
.LxtsencNx:
#if INTERLEAVE >= 2
	subs		w4, w4, #INTERLEAVE
	bmi		.Lxtsenc1x
#if INTERLEAVE == 2
	ld1		{v0.16b-v1.16b}, [x1], #32	/* get 2 pt blocks */
	next_tweak	v5, v4, v7, v8
	eor		v0.16b, v0.16b, v4.16b
	eor		v1.16b, v1.16b, v5.16b
	do_encrypt_block2x
	eor		v0.16b, v0.16b, v4.16b
	eor		v1.16b, v1.16b, v5.16b
	st1		{v0.16b-v1.16b}, [x0], #32
	cbz		w4, .LxtsencoutNx
	next_tweak	v4, v5, v7, v8
	b		.LxtsencNx
.LxtsencoutNx:
	mov		v4.16b, v5.16b
	b		.Lxtsencout
#else
	ld1		{v0.16b-v3.16b}, [x1], #64	/* get 4 pt blocks */
	next_tweak	v5, v4, v7, v8
	eor		v0.16b, v0.16b, v4.16b
	next_tweak	v6, v5, v7, v8
	eor		v1.16b, v1.16b, v5.16b
	eor		v2.16b, v2.16b, v6.16b
	next_tweak	v7, v6, v7, v8
	eor		v3.16b, v3.16b, v7.16b
	do_encrypt_block4x
	eor		v3.16b, v3.16b, v7.16b
	eor		v0.16b, v0.16b, v4.16b
	eor		v1.16b, v1.16b, v5.16b
	eor		v2.16b, v2.16b, v6.16b
	st1		{v0.16b-v3.16b}, [x0], #64
	mov		v4.16b, v7.16b
	cbz		w4, .Lxtsencout
	b		.LxtsencloopNx
#endif
.Lxtsenc1x:
	adds		w4, w4, #INTERLEAVE
	beq		.Lxtsencout
#endif
.Lxtsencloop:
	ld1		{v1.16b}, [x1], #16
	eor		v0.16b, v1.16b, v4.16b
	encrypt_block	v0, w3, x2, x6, w7
	eor		v0.16b, v0.16b, v4.16b
	st1		{v0.16b}, [x0], #16
	subs		w4, w4, #1
	beq		.Lxtsencout
	next_tweak	v4, v4, v7, v8
	b		.Lxtsencloop
.Lxtsencout:
	next_tweak	v4, v4, v7, v8
	st1		{v4.16b}, [x6], #16
	FRAME_POP
	ret
ENDPROC(ce_aes_xts_encrypt)


ENTRY(ce_aes_xts_decrypt)
	FRAME_PUSH

	ld1		{v4.16b}, [x6]
	enc_prepare	w3, x5, x6
	encrypt_block	v4, w3, x5, x6, w7		/* first tweak */
	dec_prepare	w3, x2, x6
	ldr		q7, .Lxts_mul_x
	b		.LxtsdecNx

.LxtsdecloopNx:
	ldr		q7, .Lxts_mul_x
	next_tweak	v4, v4, v7, v8
.LxtsdecNx:
#if INTERLEAVE >= 2
	subs		w4, w4, #INTERLEAVE
	bmi		.Lxtsdec1x
#if INTERLEAVE == 2
	ld1		{v0.16b-v1.16b}, [x1], #32	/* get 2 ct blocks */
	next_tweak	v5, v4, v7, v8
	eor		v0.16b, v0.16b, v4.16b
	eor		v1.16b, v1.16b, v5.16b
	do_decrypt_block2x
	eor		v0.16b, v0.16b, v4.16b
	eor		v1.16b, v1.16b, v5.16b
	st1		{v0.16b-v1.16b}, [x0], #32
	cbz		w4, .LxtsdecoutNx
	next_tweak	v4, v5, v7, v8
	b		.LxtsdecNx
.LxtsdecoutNx:
	mov		v4.16b, v5.16b
	b		.Lxtsdecout
#else
	ld1		{v0.16b-v3.16b}, [x1], #64	/* get 4 ct blocks */
	next_tweak	v5, v4, v7, v8
	eor		v0.16b, v0.16b, v4.16b
	next_tweak	v6, v5, v7, v8
	eor		v1.16b, v1.16b, v5.16b
	eor		v2.16b, v2.16b, v6.16b
	next_tweak	v7, v6, v7, v8
	eor		v3.16b, v3.16b, v7.16b
	do_decrypt_block4x
	eor		v3.16b, v3.16b, v7.16b
	eor		v0.16b, v0.16b, v4.16b
	eor		v1.16b, v1.16b, v5.16b
	eor		v2.16b, v2.16b, v6.16b
	st1		{v0.16b-v3.16b}, [x0], #64
	mov		v4.16b, v7.16b
	cbz		w4, .Lxtsdecout
	b		.LxtsdecloopNx
#endif
.Lxtsdec1x:
	adds		w4, w4, #INTERLEAVE
	beq		.Lxtsdecout
#endif
.Lxtsdecloop:
	ld1		{v1.16b}, [x1], #16
	eor		v0.16b, v1.16b, v4.16b
	decrypt_block	v0, w3, x2, x6, w7
	eor		v0.16b, v0.16b, v4.16b
	st1		{v0.16b}, [x0], #16
	subs		w4, w4, #1
	beq		.Lxtsdecout
	next_tweak	v4, v4, v7, v8
	b		.Lxtsdecloop
.Lxtsdecout:
	FRAME_POP
	next_tweak	v4, v4, v7, v8
	st1		{v4.16b}, [x6], #16
	ret
ENDPROC(ce_aes_xts_decrypt)
