ssg_stop:
	push de
		ld de,REG_SSG_CHA_VOL<<8 | $00
		rst RST_YM_WRITEA
		ld de,REG_SSG_CHB_VOL<<8 | $00
		rst RST_YM_WRITEA
		ld de,REG_SSG_CHC_VOL<<8 | $00
		rst RST_YM_WRITEA

		ld de,REG_SSG_MIX_ENABLE<<8 | $3F
		rst RST_YM_WRITEA
	pop de
	ret

SSGCNT_init:
	push bc
	push af
	push de
	push hl
		; clear SSGCNT WRAM
		ld hl,SSGCNT_wram_start
		ld de,SSGCNT_wram_start+1
		ld bc,SSGCNT_wram_end-SSGCNT_wram_start-1
		ld (hl),0
		ldir

		ld b,3
loop$:
		ld a,b
		dec a

		; Set default volume
		ld c,15
		call SSGCNT_set_vol

		djnz loop$
	pop hl
	pop de
	pop af
	pop bc
	ret

; DOESN'T BACKUP REGISTERS!!
SSGCNT_irq:
	ld b,3

channel_loop$:
	dec b
	call SSGCNT_update_volume
	call SSGCNT_update_note
	call SSGCNT_update_pitch_ofs
	call SSGCNT_update_channels_mix
	inc b
	djnz channel_loop$

	call SSGCNT_update_mixing
	call SSGCNT_update_noise_tune

	; Update all macros
	ld b,9                   ; total amount of macros
	ld de,ControlMacro.SIZE  ; de = sizeof(ControlMacro)
	ld ix,SSGCNT_macros

macro_loop$:
	call MACRO_update
	add ix,de
	djnz macro_loop$

	ret

; b: channel (0~2)
SSGCNT_update_volume:
	push hl
	push de
	push af
	push bc
		; Load SSGCNT_channel_enable[ch]
		; in a
		ld hl,SSGCNT_channel_enable
		ld e,b
		ld d,0
		add hl,de
		ld a,(hl)

		; If channel enable is 0 (off) set 
		; volume to 0, else calculate the 
		; volume based on the channel volume
		; and the channel's volume macro, if enabled.
		ld c,0
		or a,a ; cp a,0
		call nz,SSGCNT_get_ym2610_ch_volume

		; Calculate the register address
		ld a,REG_SSG_CHA_VOL
		add a,b
		ld d,a
		ld e,c
		rst RST_YM_WRITEA
	pop bc
	pop af
	pop de
	pop hl
	ret

; [INPUT]
; 	b: channel (0~2)
; [OUTPUT]
;	c: volume
; Calculates the volume, based on the set 
; channel volume and also the channel's
; volume macro, if it's enabled
SSGCNT_get_ym2610_ch_volume:
	push hl
	push de
	push ix
	push af
		; Load SSGCNT_volumes[channel]
		; in c
		ld hl,SSGCNT_volumes
		ld e,b
		ld d,0
		add hl,de
		ld c,(hl)

		; Calculate pointer to the
		; channel's volume macro (ix)
		ld ixl,b
		ld ixh,0
		ld de,SSGCNT_vol_macro_A
		add ix,ix ; \
		add ix,ix ; | ix *= 8
		add ix,ix ; /
		add ix,de

		; If the macro is disabled (enable = $00)
		; then return, else calculate the volume
		; using the macro's data
		ld a,(ix+ControlMacro.enable)
		or a,a ; cp a,0
		jr z,return$

		; Calculate pointer to current
		; volume array (a LUT is used to 
		; correctly set the volume of macros)
		ld l,c
		ld h,0
		add hl,hl ; -\
		add hl,hl ;   | hl *= 16
		add hl,hl ;  /
		add hl,hl ; /
		ld de,SSGCNT_vol_LUT
		add hl,de

		; Index said array to get the
		; desired volume
		call NMACRO_read ; Load macro value in a
		ld e,a
		ld d,0
		add hl,de
		ld c,(hl)

return$:
	pop af
	pop ix
	pop de
	pop hl
	ret

; b: channel (0~2)
SSGCNT_update_note:
	push hl
	push de
	push af
	push ix
		; Load SSGCNT_notes[channel]
		; into l
		ld hl,SSGCNT_notes
		ld e,b
		ld d,0
		add hl,de
		ld l,(hl)

		; Wrap l inbetween 0 and 127
		ld a,l
		and a,$7F
		ld l,a

		; Calculate pointer to
		; arpeggio macro
		ld ixl,b
		ld ixh,0
		ld de,SSGCNT_arp_macro_A
		add ix,ix ; \
		add ix,ix ; | ix *= 8
		add ix,ix ; /
		add ix,de

		; If the macro is disabled (enable = $00), 
		; just use the value in SSGCNT_notes[channel]
		xor a,a ; ld a,0
		cp a,(ix+ControlMacro.enable)
		jr z,macro_is_disabled$
		
		; Else (the macro is enabled) add to
		; the value in SSGCNT_notes[channel]
		; the macro's current value (signed addition)
		call BMACRO_read ; Load macro value in a
		add a,l
		ld l,a
		;ld ixl,a

macro_is_disabled$:
		; Load tune from LUT into hl
		ld h,0
		ld de,SSGCNT_note_LUT
		add hl,hl
		add hl,de
		ld e,(hl)
		inc hl
		ld d,(hl)
		ex hl,de

		; Load pitch ofs from WRAM into de
		ld ix,SSGCNT_pitch_ofs
		ld d,0
		ld e,b
		add ix,de
		add ix,de
		ld e,(ix+0)
		ld d,(ix+1)
		add hl,de ; Add offset to loaded pitch

		; Check if custom clamp is enabled, if that's the
		; case, use custom clamp routine
		ld ix,SSGCNT_pitch_slide_clamp
		ld d,0
		ld e,b
		add ix,de
		add ix,de
		bit 7,(ix+1)
		jp nz,custom_clamp$

		; Check for underflow (upward pitch slide)
		;   SSG tune values go inbetween $0000 and $0FFF,
		;   if the most significant nibble isn't 0, then
		;   an over/underflow has happened. Assume an 
		;   underflow happened for now.
		ld a,h
		rrca      ; \
		rrca      ;  \
		rrca      ;  | a >>= 4
		rrca      ;  /
		and a,$0F ; /
		or a,a    ; cp a,0
		jp nz,solve_over_and_underflow$

solve_under_and_over_flow_return$:
		; Load coarse tune and write
		; it to correct register
		ld a,REG_SSG_CHA_COARSE_TUNE
		add a,b ; - a += channel*2
		add a,b ; /
		ld d,a
		ld e,h
		rst RST_YM_WRITEA

		; Load fine tune and write
		; it to the correct register
		dec d
		ld e,l
		rst RST_YM_WRITEA
	pop ix
	pop af
	pop de
	pop hl
	ret

; [INPUT]
;   hl: pitch offset
;   de: channel
; [OUTPUT]
;   hl: clamped pitch offset
;   d: pitch slide offset MSB
solve_over_and_underflow$:
	; Load pitch slide offset MSB
	push hl
		ld hl,SSGCNT_pitch_slide_ofs+1
		add hl,de
		add hl,de
		ld d,(hl)
	pop hl

	; If pitch slide offset is 
	; positive, solve overflow
	bit 7,d
	jp z,solve_overflow$

	; Else, solve underflow
	ld hl,$0000
	jp solve_under_and_over_flow_return$

solve_overflow$:
	ld hl,$0FFF
	jp solve_under_and_over_flow_return$

; [INPUT]
;   hl: pitch 
;   de: channel
;   ix: pitch slide clamp address
; [OUTPUT]
;   hl: clamped pitch 
;   REGISTER DE ISNT BACKED UP
;   TO REFACTOR
;   TO FIX: REDIRECT TO DEFAULT CLAMP IF CLAMP LIMIT IS 0
custom_clamp$:
	; if custom clamp is a clamp on the minimum 
	; value, use default limit
	bit 6,(ix+1)
	jp nz,default_overflow$

	; if pitch < limit: skip to underflow check
	ld de,$0FFF ; DEFAULT
	or a,a ; clear carry flag
	sbc hl,de
	add hl,de
	jp c,custom_underflow$

	; clamp result and reset pslide offset
	ld hl,de
	ld ix,SSGCNT_pitch_slide_ofs
	ld e,b
	ld d,0
	add ix,de
	add ix,de
	ld (ix+0),d
	ld (ix+1),d
	jp solve_under_and_over_flow_return$

default_overflow$:
	; Load maximum clamp value in de
	ld e,(ix+0)
	ld a,(ix+1)
	and a,%00001111 ; clear flags
	ld d,a
	
	; if pitch < limit: skip to underflow check
	or a,a ; clear carry flag
	sbc hl,de
	add hl,de
	jp c,custom_underflow$
	
	; clamp result and reset pslide offset
	ld hl,de
	ld ix,SSGCNT_pitch_slide_ofs
	ld e,b
	ld d,0
	add ix,de
	add ix,de
	ld (ix+0),d
	ld (ix+1),d
	jp solve_under_and_over_flow_return$

custom_underflow$:
	; else, solve underflow
	;   if custom clamp is a clamp on the maximum
	;   value, use default overflow handler
	bit 6,(ix+1)
	jp z,default_underflow$

	ld de,$0000
	or a,a ; clear carry flag
	sbc hl,de
	add hl,de
	jp nc,solve_under_and_over_flow_return$

	; clamp result and reset pslide offset
	ld hl,de
	ld ix,SSGCNT_pitch_slide_ofs
	ld e,b
	ld d,0
	add ix,de
	add ix,de
	ld (ix+0),d
	ld (ix+1),d
	jp solve_under_and_over_flow_return$

default_underflow$:
	; Load minimum clamp value in de
	ld e,(ix+0)
	ld a,(ix+1)
	and a,%00001111 ; clear flags
	ld d,a
	
	; if pitch >= limit: return
	or a,a ; clear carry flag
	sbc hl,de
	add hl,de
	jp nc,solve_under_and_over_flow_return$
	
	; clamp result and reset pslide offset
	ld hl,de
	ld ix,SSGCNT_pitch_slide_ofs
	ld e,b
	ld d,0
	add ix,de
	add ix,de
	ld (ix+0),d
	ld (ix+1),d
	jp solve_under_and_over_flow_return$

; b: channel (0~2)
SSGCNT_update_pitch_ofs:
	push ix
	push de
	push hl
		; Load pitch slide offset in hl
		ld ix,SSGCNT_pitch_slide_ofs
		ld e,b
		ld d,0
		add ix,de
		add ix,de
		ld e,(ix+0)
		ld d,(ix+1)
		ex hl,de

		; Load pitch offset in de
		ld ix,SSGCNT_pitch_ofs
		ld e,b
		ld d,0
		add ix,de
		add ix,de
		ld e,(ix+0)
		ld d,(ix+1)

		; Add together pitch offset and pitch slide, 
		; then store everything back into WRAM
		add hl,de
		ex hl,de
		ld (ix+0),e
		ld (ix+1),d
	pop hl
	pop de
	pop ix
	ret

; b: channel (0~2)
;	Updates the channel's mixing according to the macros,
;   if the channel's mix macros are disabled this won't
;   do anything, and the mixing values set manually won't
;   be overwritten.
SSGCNT_update_channels_mix:
	push ix
	push de
	push af
	push bc
		; Load channel's mix macro enable in a
		ld ixl,b
		ld ixh,0
		ld de,SSGCNT_mix_macro_A
		add ix,ix ; \
		add ix,ix ; | hl *= 8
		add ix,ix ; /
		add ix,de
		ld a,(ix+ControlMacro.enable)

		; If the selected channel's mix macro is
		; disabled (enable == $00) then return
		or a,a ; cp a,0
		jr z,return$

		call NMACRO_read ; Stores macro value in a
		ld ixl,a ; backup macro value in ixl
		ld d,b   ; backup channel in d (channel parameter)

		; Enable tone if the mixing's byte
		; bit 0 is 1, else disable it
		and a,%00000001 ; Get tone enable bit
		ld c,a                    ; Enable/Disable parameter
		ld e,SSGCNT_MIX_EN_TUNE   ; Tune/Noise select parameter
		call SSGCNT_set_mixing

		; Enable noise if the mixing's byte
		; bit 1 is 1, else disable it
		ld a,ixl
		and a,%00000010 ; Get noise enable bit
		srl a
		ld c,a                   ; Enable/Disable parameter
		ld e,SSGCNT_MIX_EN_NOISE ; Tune/Noise select parameter
		call SSGCNT_set_mixing

return$:
	pop bc
	pop af
	pop de
	pop ix
	ret

; This just flips the SSGCNT_mix_flags byte and
; sets the YM2610's registers accordingly
SSGCNT_update_mixing:
	push de
	push af
		ld d,REG_SSG_MIX_ENABLE
		ld a,(SSGCNT_mix_flags)
		xor a,$3F ; Flip all flags, since the SSG mixing register uses negative enable flags
		ld e,a
		rst RST_YM_WRITEA
	pop af
	pop de
	ret

SSGCNT_update_noise_tune:
	push de
	push af
		ld d,REG_SSG_CHN_NOISE_TUNE
		ld a,(SSGCNT_noise_tune)
		ld e,a
		rst RST_YM_WRITEA
	pop af
	pop de
	ret

; a: channel
; c: volume
SSGCNT_set_vol:
	push bc
	push hl
	push af
		ld b,a ; \
		ld a,c ; | Swap a and c
		ld c,b ; /

		ld b,0
		ld hl,SSGCNT_volumes
		add hl,bc
		ld (hl),a
	pop af
	pop hl
	pop bc
	ret

; c: channel
; a: volume
SSGCNT_set_vol_opt:
	push bc
	push hl
	push af
		ld b,a ; \
		ld a,c ; | Swap a and c
		ld c,b ; /

		ld b,0
		ld hl,SSGCNT_volumes
		add hl,bc
		ld (hl),a
	pop af
	pop hl
	pop bc
	ret

; a: noise tune
; 	Everyone needs a useless
;	subroutine that is there
;	only for consistency!
SSGCNT_set_noise_tune:
	ld (SSGCNT_noise_tune),a
	ret

; a: channel
SSGCNT_set_buffered_note:
	push hl
	push de
		ld hl,SSGCNT_buffered_note
		ld e,a
		ld d,0
		add hl,de
		ld c,(hl)
	pop de
	pop hl
	; this then goes to SSGCNT_set_note...

; a: channel
; c: note
; Also resets any pitch offset modified by a pitch slide
SSGCNT_set_note:
	push bc
	push hl
	push af
		ld b,a ; \
		ld a,c ; | Swap a and c
		ld c,b ; /

		; Store note into WRAM
		ld b,0
		ld hl,SSGCNT_notes
		add hl,bc
		ld (hl),a

		; Set buffered note
		ld hl,SSGCNT_buffered_note
		add hl,bc
		ld (hl),a

		; Reset pitch offset
		ld hl,SSGCNT_pitch_ofs
		add hl,bc
		add hl,bc
		ld (hl),0
		inc hl
		ld (hl),0
	pop af
	pop hl
	pop bc
	ret

; [INPUT]
;   l: note
; [OUTPUT]
;   de: pitch
; DOESN'T BACKUP REGISTER HL
SSGCNT_get_pitch_from_note:
	ld h,0
	ld de,SSGCNT_note_LUT
	add hl,hl
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ret

; e: flag type to set/clear (SSGCNT_MIX_EN_TUNE = 0; SSGCNT_MIX_EN_NOISE = 3)
; d: SSG channel (0~2)
; c: 0 if the flag needs to be cleared, 1 if the flag needs to be set
; POSITIVE ENABLE!
SSGCNT_set_mixing:
	push af
	push bc
	push hl
	push de
		; bit <<= ssg_channel + flag_type
		ld a,e
		add a,d
		ld b,a
		call shift_left_c_by_b_bits ; Clears b
		ld a,e   ; \
		add a,d  ; | Calculate b again
		ld b,a   ; /
		ld e,c ; backup bit in e

		; Calculate mask
		;	mask = 1 << (ssg_channel + flag_type)
		ld c,1
		call shift_left_c_by_b_bits

		; mix_flags = ~mask $ SSGCNT_mix_flags
		ld hl,SSGCNT_mix_flags
		ld a,c
		xor a,$FF
		and a,(hl)

		; mix_flags |= bit
		or a,e
		ld (hl),a
	pop de
	pop hl
	pop bc
	pop af
	ret

; a: channel
SSGCNT_enable_channel:
	push hl
	push de
		ld hl,SSGCNT_channel_enable
		ld e,a
		ld d,0
		add hl,de
		ld (hl),$FF
	pop de
	pop hl
	ret

; a: channel
SSGCNT_disable_channel:
	push hl
	push de
		ld hl,SSGCNT_channel_enable
		ld e,a
		ld d,0
		add hl,de
		ld (hl),0
	pop de
	pop hl
	ret

; a: channel
;  Starts's all channel's macros
SSGCNT_start_channel_macros:
	push ix
	push de
		; Calculate address to channel's mix macro,
		; and set mix_macro.curr_pt to 0
		ld ixl,a
		ld ixh,0
		ld de,SSGCNT_mix_macro_A
		add ix,ix ; \
		add ix,ix ; | ix *= 8
		add ix,ix ; /
		add ix,de
		ld (ix+ControlMacro.curr_pt),0

		; Set channel's volume macro.curr_pt to 0
		ld de,ControlMacro.SIZE*3
		add ix,de
		ld (ix+ControlMacro.curr_pt),0
		
		; Set channel's arpeggio macro.curr_pt to 0
		add ix,de
		ld (ix+ControlMacro.curr_pt),0
	pop de
	pop ix
	ret

; ==== LOOKUP TABLES ====
SSGCNT_note_LUT:
	incbin "ssg_pitch_lut.bin"

SSGCNT_vol_LUT:
	incbin "ssg_vol_lut.bin"
	