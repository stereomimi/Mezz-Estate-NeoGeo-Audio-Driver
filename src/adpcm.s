;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                 ADPCM-A                 ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Note: anytime an ADPCM channel is stopped, the flags MUST be dealt with or they will stay stuck.
PA_stop:
	push de
		; Reset and mask all channel status flags
		ld de,REG_P_FLAGS_W<<8 | %00111111
		rst RST_YM_WRITEA

		; Unmask all channel status flags
		ld e,0
		rst RST_YM_WRITEA

		; Stop all channels
		ld de,REG_PA_CTRL<<8 | $BF
		rst RST_YM_WRITEB
	pop de
	ret

PA_reset:
	push de
	push bc
	push af
		call PA_stop

		; Set volumes to $1F and panning
		; to center for every channel
		ld b,6
		ld d,REG_PA_CVOL
		ld e,PANNING_CENTER | $1F
PA_reset_loop:
		rst RST_YM_WRITEB
		inc d
		djnz PA_reset_loop

		; Set master volume to $3F
		ld de,REG_PA_MVOL<<8 | $3F
		rst RST_YM_WRITEB
	pop af
	pop bc
	pop de
	ret
; a:  channel (0: ADPCM-A 1, ..., 5: ADPCM-A 6)
; ix: source (smp start LSB; smp start MSB; smp end LSB; smp start MSB)
PA_set_sample_addr:
	push af
	push de
		ld d,REG_PA_STARTL
		add a,d
		ld d,a
		ld e,(ix+0)
		rst RST_YM_WRITEB

		add a,REG_PA_STARTH-REG_PA_STARTL
		ld d,a
		ld e,(ix+1)
		rst RST_YM_WRITEB

		add a,REG_PA_ENDL-REG_PA_STARTH
		ld d,a
		ld e,(ix+2)
		rst RST_YM_WRITEB

		add a,REG_PA_ENDH-REG_PA_ENDL
		ld d,a
		ld e,(ix+3)
		rst RST_YM_WRITEB
	pop de
	pop af
	ret

; c: channel
PA_stop_sample:
	push hl
	push bc
	push af
	push de
		; Maybe the status register flag gets cleared
		; when resetting, masking and (especially) unmasking the status flags?
		call SFXPS_update_playback_status
		
		; Get pointer to channel mask
		ld hl,PA_channel_on_masks
		ld d,0
		ld e,c
		add hl,de
		ld a,(hl)

		; Reset and mask channel status flag
		ld d,REG_P_FLAGS_W
		ld e,a
		rst RST_YM_WRITEA

		; Unmask channel status flag
		ld e,0
		rst RST_YM_WRITEA

		; Stop sample
		or a,%10000000 ; Set dump bit
		ld e,a
		ld d,REG_PA_CTRL
		rst RST_YM_WRITEB
	pop de		
	pop af
	pop bc
	pop hl
	ret

; c: channel
; a: volume
; AF and B aren't backed up
PA_set_channel_volume:
	push de
	push hl
		; Store volume in 
		; PA_channel_volumes[channel]
		ld hl,PA_channel_volumes
		ld b,0
		add hl,bc
		ld (hl),a

		; Load panning from 
		; PA_channel_pannings[channel]
		; and OR it with the volume
		ld de,PA_channel_pannings-PA_channel_volumes
		add hl,de
		or a,(hl) ; ORs the volume and panning
		ld e,a
		
		; Set CVOL register
		ld a,c
		add a,REG_PA_CVOL
		ld d,a
		rst RST_YM_WRITEB
	pop hl
	pop de
	ret

; a: channel
; c: panning (0: none, 64: right, 128: left, 192: both)
PA_set_channel_panning:
	push hl
	push de
	push bc
		; Store panning in 
		; PA_channel_pannings[channel]
		ld h,0
		ld l,a
		ld de,PA_channel_pannings
		add hl,de
		ld (hl),c

		; Load volume from
		; MLM_channel_volumes[channel]
		; and OR it with the panning
		push af
			ld h,0
			ld l,a
			ld de,PA_channel_volumes
			add hl,de
			ld a,(hl)
			or a,c
			ld e,a
		pop af

		; Set CVOL register
		push af
			add a,REG_PA_CVOL
			ld d,a
		pop af
		rst RST_YM_WRITEB
	pop bc
	pop de
	pop hl
	ret

; e: channel
; CHANGES FLAGS!!!
;   Resets, masks, unmasks the channel
;   status flag of an ADPCM-A channel.
PA_channel_status_reset:
	push hl
	push de
		; Get pointer to channel mask
		ld hl,PA_channel_on_masks
		ld d,0
		add hl,de

		; Reset and mask channel
		ld e,(hl)
		ld d,REG_P_FLAGS_W
		rst RST_YM_WRITEA

		; Unmask channel
		ld e,0
		rst RST_YM_WRITEA
	pop de
	pop hl
	ret

; e: channel
;   Plays ADPCM-A channel and resets flags correctly
PA_play_sample:
	push hl
	push de
	push af
		; Maybe the status register flag gets cleared
		; when resetting, masking and (especially) unmasking the status flags?
		push de
			call SFXPS_update_playback_status
		pop de

		; Get pointer to channel mask
		ld hl,PA_channel_on_masks
		ld d,0
		add hl,de
		ld a,(hl)
 
		; Reset and mask channel status flag
		ld d,REG_P_FLAGS_W
		ld e,a
		rst RST_YM_WRITEA

		; Unmask channel status flag
		ld e,0
		rst RST_YM_WRITEA

		; Stop sample if one's playing first
		ld d,REG_PA_CTRL
		or a,%10000000 ; Set dump bit
		ld e,a
		rst RST_YM_WRITEB

		; Play sample
		ld d,REG_PA_CTRL
		and a,%01111111 ; Clear dump bit
		ld e,a
		rst RST_YM_WRITEB
	pop af
	pop de
	pop hl
	ret

; e: channel
;   Plays ADPCM-A channel and resets flags correctly
PA_retrigger_sample:
	push hl
	push de
	push af
		; Maybe the status register flag gets cleared
		; when resetting, masking and (especially) unmasking the status flags?
		push de
			call SFXPS_update_playback_status
		pop de

		; Get pointer to channel mask
		ld hl,PA_channel_on_masks
		ld d,0
		add hl,de
		ld a,(hl)
 
		; Reset and mask channel status flag
		ld d,REG_P_FLAGS_W
		ld e,a
		rst RST_YM_WRITEA

		; Unmask channel status flag
		ld e,0
		rst RST_YM_WRITEA

		; Play sample, without stopping the channel
		; first
		ld d,REG_PA_CTRL
		and a,%01111111 ; Clear dump bit
		ld e,a
		rst RST_YM_WRITEB
	pop af
	pop de
	pop hl
	ret

PA_channel_on_masks:
	db %00000001,%00000010,%00000100,%00001000,%00010000,%00100000
PA_channel_neg_masks:
	db ~%00000001,~%00000010,~%00000100,~%00001000,~%00010000,~%00100000

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                 ADPCM-B                 ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

pb_stop:
	push de
		ld de,REG_PB_CTRL<<8 | $01
		rst RST_YM_WRITEA

		dec e
		rst RST_YM_WRITEA
	pop de
	ret