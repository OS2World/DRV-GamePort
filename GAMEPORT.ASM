;**********************************************************************
;*                                                                    *
;*                           ICA System Inc                           *
;*                         -----------------                          *
;*                 Game Port Driver Version 1.00                      *
;*                                                                    *
;*                                                                    *
;*                                                                    *
;**********************************************************************

.286p
.SEQ

	extrn	DosWrite:far

;-------------------------------------------

ADATA	SEGMENT	PARA PUBLIC 'AUTO'

nexthdr		dd	0FFFFFFFFh	; pointer to next device driver
devattr		dw	9880h		; attribute flags
stratof		dw	offset strategy ;offset of strategy routine entry
reserv1		dw	0
devname		db	'GAME$   '	; device name for "DosOpen"
reserv2		db	8 dup (0)

devhelp		dd	0	; this is where we save the DevHelp pointer

tickcnt		dw	0	; tick count

JOYPORT		equ	201h	; joy stick port
JSNOTTHERE	equ	2000	; only allow 2000 ticks

jy_ax		equ	01h	; joystick ax bit
jy_ay		equ	02h	; joystick ay bit
jy_bx		equ	04h	; joystick bx bit
jy_by		equ	08h	; joystick by bit
jy_a1		equ	10h	; button a1
jy_a2		equ	20h	; button a2
jy_b1		equ	40h	; button b1
jy_b2		equ	80h	; button b2

joymask		db	0	; joystick mask
buttonmask	db	0	; button mask
b1_cnt		dw	0	; button 1 count
b2_cnt		dw	0	; button 2 count
a1_cnt		dw	0	; button 3 count
a2_cnt		dw	0	; button 4 count

buttonsta	db	0	; button status
jschkcnt	dd	0	; joystick check count

	PUBLIC	ax_cnt, ay_cnt, bx_cnt, by_cnt, joymask
ax_cnt		dw	0	; ax count
ay_cnt		dw	0	; ay count
bx_cnt		dw	0	; bx count
by_cnt		dw	0	; by count
timtick		dw	0	; clock ticks
clkticks	dw	6	; check joysticks 10 times per second
tickflg		dw	0	; timer active flag

opncnt		dw	0		; count of opens

dbrk	MACRO
ifdef	DEBUG
	int	3
endif
	ENDM

rq_init		equ	00h			; define requests
rq_open		equ	0dh
rq_close	equ	0eh
rq_ioctl	equ	10h

dh_PhysToVirt	equ	15h		; define device help routines
dh_PhysToUVirt	equ	17h
dh_SetIRQ	equ	1bh
dh_UnSetIRQ	equ	1ch
dh_EOI		equ	31h
dh_UnPhysToVirt	equ	32h
dh_SetTimer	equ	1dh
dh_ResetTimer	equ	1eh

end_of_data	label	byte            ; the rest isn't needed after init

initmsg		db	0Dh,0Ah
		db	'Game Port Driver',0Dh,0Ah
		db	'Version 1.00 * Copyright (c) 1989, 1992 ICA Systems Inc',0Dh,0Ah
		db	0Dh,0Ah
initmsglen	equ	$-offset initmsg
byteswritten	dw	0

ADATA	ENDS

DGROUP	GROUP	ADATA

;-------------------------------------------

CODE	SEGMENT	PARA	'CODE'

	ASSUME	CS:CODE,DS:ADATA
	PUBLIC strategy
strategy PROC	FAR

;examine command code in req packet

;	dbrk			; break on debug
	mov	al,es:[bx+2]
	cmp	al,rq_init	; is it initialize ?
	jne	chkopn		; no - go on
	jmp	FAR PTR Initbrd	; yes - go do it
chkopn:	cmp	al,rq_open	; is it open ?
	jne	chkcls		; no - maybe close
	jmp	FAR PTR Openbrd	; yes - go open it
chkcls:	cmp	al,rq_close	; is it close ?
	jne	chkioc		; no - maybe IOCtl
	jmp	FAR PTR Closebrd; yes - go close it
chkioc:	cmp	al,rq_ioctl	; is it IOCtl ?
	jne	cdone		; no - will thats it then
	jmp	FAR PTR IOCtlbrd; yes go do it

;if none of the above, execute default stuff

cdone:	mov	word ptr es:[bx+3],0100h    ;set the "done" flag
	ret
strategy ENDP


;***********************************************************************
; Open routine -  grab interrupt amd set timer to read joysticks
;
;***********************************************************************
	PUBLIC	Openbrd
Openbrd	PROC	FAR
	dbrk			; debug breakpoint
	push	es		; save some registers
	push	bx
	cmp	opncnt,0	; is it already open ?
	jne	opndon		; yes - go on
	mov	a1_cnt,0	; clear the button counts
	mov	a2_cnt,0
	mov	b1_cnt,0
	mov	b2_cnt,0
	mov	timtick,0

	mov	al,0fh		; say we have all our joysticks
	mov	joymask,al	; and save it
	mov	ax,OFFSET CS:TimeRtn ; get the timer routine
	mov	dx,dh_SetTimer	; set the function
	call	devhelp		; and call device help
	mov	tickflg,-1	; say we have a timer

opndon:	pop	bx		; restore registers
	pop	es
	inc	opncnt		; count the open
	mov	word ptr es:[bx+3],0100h ; set the "done" flag
	ret			; and return
Openbrd	ENDP

;*********************************************************************
; Close routine - give up the interrupt
;
;*********************************************************************
	PUBLIC	Closebrd
Closebrd PROC	FAR
;	dbrk			; debug breakpoint
	push	es		; save some registers
	push	bx
	cmp	opncnt,1	; is this the last open ?
	jne	clsdon		; no - go on
	cmp	tickflg,0	; do we have a timer ?
	je	clsdon		; no go on
	mov	ax,OFFSET CS:TimeRtn ; clear the timer
	mov	dx,dh_ResetTimer ; get the ResetTimer function
	call	devhelp		; and do it
clsdon:	pop	bx		; restore registers
	pop	es
	dec	opncnt		; count the close
	mov	word ptr es:[bx+3],0100h ; set the "done" flag
	ret			; and return
Closebrd ENDP

;*********************************************************************
; IOCtl Routine - Gets addresses or sets tick counts
;
;*********************************************************************
	PUBLIC	IOCtlbrd
IOCtlbrd PROC	FAR
;	dbrk			; debug break point
	mov	al,es:[bx+14]
iocjs:	cmp	al,20h		; is it joystick read ?
	jne	iockrj
	jmp	iocjoy		; yes - it is joy stick read
iockrj:	cmp	al,60h		; is it reset joysticks ?
	jne	iocerr		; no - go on
	jmp	iocrsj		; yes - go reset joysticks

	;return error if not recognized

iocerr:	mov	WORD PTR es:[bx+3],0C10Ch
	ret

iocrsj:	push	es			; save es for now
	les	di,DWORD PTR es:[bx+15]	; Get the parameter block
	mov	ax,WORD PTR es:[di]	; get the joystick mask
	cli				; no interrupts just now
	mov	joymask,al		; and store it
	sti				; ok interrupts
	pop	es			; restore es
	jmp	iocrtn			; and return


iocrtn:	mov	WORD PTR es:[bx+3],0100h    ;set the "done" flag
	ret

;error exit

iocext:	pop	bx			; restore the register
	pop	es			; ...
	mov	WORD PTR es:[bx+3],0C10Ch ; return error code
	ret				; and return

iocjoy:	push	es			; save es for now
	les	di,DWORD PTR es:[bx+19]	; get the result block
	mov	ax,ax_cnt		; get the count
	mov	WORD PTR es:[di],ax	; store the counts
	mov	ax,ay_cnt		; ...
	mov	WORD PTR es:[di+2],ax
	mov	ax,bx_cnt
	mov	WORD PTR es:[di+4],ax
	mov	ax,by_cnt
	mov	WORD PTR es:[di+6],ax
	mov	ax,a1_cnt		; get the switch counts
	mov	WORD PTR es:[di+8],ax	; store them
	mov	ax,a2_cnt
	mov	WORD PTR es:[di+10],ax
	mov	ax,b1_cnt
	mov	WORD PTR es:[di+12],ax
	mov	ax,b2_cnt
	mov	WORD PTR es:[di+14],ax
	mov	al,joymask		; get the mask
	mov	ah,buttonsta		; get the button state
	mov	WORD PTR es:[di+16],ax	; store the active mask
	mov	ax,WORD Ptr jschkcnt	; get the joystick check count
	mov	WORD PTR es:[di+18],ax	; ....
	mov	ax,WORD Ptr jschkcnt+2	; get the joystick count hi word
	mov	WORD PTR es:[di+20],ax	; ...
	pop	es			; restore the register
	jmp	iocrtn			; and return

IOCtlbrd ENDP

;**************************************************************************
;  Joystick Count Routine
;
;**************************************************************************
	PUBLIC	JsCnt
JsCnt	PROC	NEAR
	mov	dx,0201h		; get the address
	xor	al,al			; clear al
;	xor	cx,cx			; and cx
	mov	cx,JSNOTTHERE		; Get A Limit
	cli				; no interrupts just now
	out	dx,al			; start it going
	jmp	jsloop			; a timing break
jsloop:	in	al,dx			; read the port
	and	al,ah			; clear the junk
	je	jsdone			; if clear return the value
	loop	jsloop			; keep on going

jsdone:	sti				; ok interrupts
	sub	cx,JSNOTTHERE		; get negitive count
	neg	cx			; get the count
	ret				; and return it
JsCnt	ENDP


;*************************************************************************
; Timer Routine - Routine reads joystick values
;
;*************************************************************************
	PUBLIC	TimeRtn
TimeRtn	PROC	FAR
	pushf				; save the flags
	push	ax			; save some registers
	push	bx			; save lots of registers
	push	cx
	push	dx
	push	si
	push	di

	mov	ax,0
	mov	dx,JOYPORT		; read the joystick port
	in	al,dx			; ...
	and	al,0f0h			; just check the buttons for now
	or	al,ah
	xor	al,0f0h			; buttons down are now high
	mov	ah,al			; save a copy
	and	al,buttonmask		; is it the same 
	mov	buttonmask,ah		; set the new mask
	mov	ah,al			; copy the status
	xor	al,buttonsta		; get the state
	mov	buttonsta,ah		; save the new state
	je	chkcnt			; if done go on
	test	al,jy_a1		; is a1 set ?
	je	cka2			; no go on
	test	ah,jy_a1		; just count the down presses
	je	cka2			; ..
	inc	a1_cnt			; count the press
cka2:	test	al,jy_a2		; check a2
	je	ckb1			; no go on
	test	ah,jy_a2		; just the press
	je	ckb1
	inc	a2_cnt
ckb1:	test	al,jy_b1		; is b1 set ?
	je	ckb2			; no go on
	test	ah,jy_b1
	je	ckb2
	inc	b1_cnt			; count the press
ckb2:	test	al,jy_b2		; check b2
	je	chkcnt			; no go on
	test	ah,jy_b2
	je	chkcnt
	inc	b2_cnt			; count it
chkcnt:	mov	ax,timtick		; get the time tick count
	inc	ax			; bump it
	mov	timtick,ax		; store it back
	cmp	ax,clkticks		; is it time to check pots?
	jae	chkpot			; yes go do it
	jmp	timdon			; and go finish up

chkpot:	cmp	ax,clkticks		; is it time for js one?
	ja	tchkay			; no maybe the next one
	xor	bx,bx			; clear bx
	inc	WORD Ptr jschkcnt	; bump the check count
	adc	WORD Ptr jschkcnt+2,bx	; ...
	mov	ah,jy_ax		; get the channel to test
	and	ah,joymask		; is this channel used ?
	jne	tjsck			; yes - check it
	jmp	timdon			; no that it for now
tjsck:	call	JsCnt			; call the count routine
	cmp	cx,JSNOTTHERE		; is the joystick there ?
	jb	tchnax			; ok go on
	not	ah			; clear the bit in the mask
	and	joymask,ah		; ...
	mov	cx,0			; clear the count
tchnax:	mov	ax_cnt,cx		; save the count
	jmp	timdon			; thats it for now

tchkay: mov	bx,clkticks		; get clock ticks
	inc	bx
	cmp	ax,bx			; maybe time to check here
	ja	tchkbx			; no go on
	mov	ah,jy_ay		; get the channel to test
	and	ah,joymask		; is this channel used ?
	je	timdon			; no finish up
	call	JsCnt			; call the count routine
	cmp	cx,JSNOTTHERE		; is the joystick there ?
	jb	tchnay			; ok go on
	not	ah			; clear the bit in the mask
	and	joymask,ah		; ...
	mov	cx,0			; clear the count
tchnay:	mov	ay_cnt,cx		; save the count
	jmp	timdon			; thats it for now

tchkbx: inc	bx
	cmp	ax,bx			; maybe here
	ja	tchkby			; no go on
	mov	ah,jy_bx		; get the channel to test
	and	ah,joymask		; is this channel used ?
	je	timdon			; no go on
	call	JsCnt			; call the count routine
	cmp	cx,JSNOTTHERE		; is the joystick there ?
	jb	tchnbx			; ok go on
	not	ah			; clear the bit in the mask
	and	joymask,ah		; ...
	mov	cx,0			; clear the count
tchnbx:	mov	bx_cnt,cx		; save the count
	jmp	timdon

tchkby: xor	ax,ax			; reset the count
	mov	timtick,ax		; and store it
	mov	ah,jy_by		; get the channel to test
	and	ah,joymask		; is this channel used ?
	je	timdon			; no thats it
	call	JsCnt			; call the count routine
	cmp	cx,JSNOTTHERE		; is the joystick there ?
	jb	tchnby			; ok go on
	not	ah			; clear the bit in the mask
	and	joymask,ah		; ...
	mov	cx,0			; clear the count
tchnby:	mov	by_cnt,cx		; save the count
	
timdon: pop	di			; restore the register and flags
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	popf
	ret
TimeRtn	ENDP

end_of_code	label	byte		; code after this point is needed
					; only at initialization time

;*********************************************************************
; initialization routine - Just set things up
;
;*********************************************************************
	PUBLIC	Initbrd
Initbrd	PROC	FAR

;save "DevHlp" call address

;	dbrk				; debug breakpoint
	mov	ax,es:[bx+14]		; get the device help address
	mov	word ptr devhelp,ax	; and store it away
	mov	ax,es:[bx+16]		; ...
	mov	word ptr devhelp+2,ax	; ...

;display message

	push	1
	push	ds
	push	offset initmsg
	push	initmsglen
	push	ds
	push	offset byteswritten
	call	DosWrite

;now checkout the joysicks

	mov	ah,jy_ax		; bit to check
	call	JsCnt			; check the joystick ax channel
	cmp	cx,JSNOTTHERE		; is it there ?
	ja	c2chk			; no go on
	or	joymask,ah		; ax is there
	mov	ax_cnt,cx		; and save the count

c2chk:	mov	ah,jy_ay		; check the ay channel
	push	ax
	call	JsCnt			; check the joystick channel
	pop	ax
	cmp	cx,JSNOTTHERE		; is it there ?
	ja	c3chk			; no go on
	or	joymask,ah		; ax is there
	mov	ay_cnt,cx		; and save the count

c3chk:	mov	ah,jy_bx		; check the bx channel
	push	ax
	call	JsCnt			; check the joystick channel
	pop	ax
	cmp	cx,JSNOTTHERE		; is it there ?
	ja	c4chk			; no go on
	or	joymask,ah		; ax is there
	mov	bx_cnt,cx		; and save the count

c4chk:	mov	ah,jy_by		; check the by channel
	push	ax
	call	JsCnt			; check the joystick channel
	pop	ax
	cmp	cx,JSNOTTHERE		; is it there ?
	ja	cjsdon			; no go on
	or	joymask,ah		; ax is there
	mov	by_cnt,cx		; and save the count

;set ending offsets

cjsdon:	mov	word ptr es:[bx+14],offset end_of_code ; say how much code
	mov	word ptr es:[bx+16],offset end_of_data ; and data to keep

;set other req packet fields

	mov	word ptr es:[bx+18],0
	mov	word ptr es:[bx+20],0

;set status and exit

	mov	word ptr es:[bx+3],0100h    ;"done"
	ret

Initbrd	ENDP

CODE	ENDS

	end
