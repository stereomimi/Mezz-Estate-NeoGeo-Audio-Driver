; DOESN'T BACKUP REGISTERS
MLM_irq:
	ld iyl,0 ; Clear active mlm channel counter

	; base time counter code
	ld a,(MLM_base_time)
	ld c,a
	ld a,(MLM_base_time_counter)	
	inc a
	cp a,c
	ld (MLM_base_time_counter),a
	jr nz,MLM_update_skip

	;ld b,13 ;; In deflemask mlm exports, only one channel is used, it's a waste to check all channels
MLM_update_loop:
	;ld c,b
	;dec c Just deal with channel 1
	ld c,0

	; if MLM_playback_control[ch] == 0 then
	; do not update this channel
	;ld h,0
	;ld l,c
	;ld de,MLM_playback_control
	;add hl,de
	;ld a,(hl)
	ld a,(MLM_playback_control)
	or a,a ; cp a,0
	jr z,MLM_update_loop_next

	inc iyl ; increment active mlm channel counter

	; hl = &MLM_playback_timings[channel]
	; de = *hl
	;ld h,0
	;ld l,c
	;ld de,MLM_playback_timings
	;add hl,hl
	;add hl,de
	ld hl,MLM_playback_timings
	ld e,(hl)
	inc hl
	ld d,(hl)

	; Decrement the timing and 
	; store it back into WRAM
	dec de 
	ld (hl),d
	dec hl
	ld (hl),e

	; if timing==0 update events
	; else save decremented timing
	push hl
		ld hl,0
		sbc hl,de
	pop hl

MLM_update_check_execute_events:
	call z,MLM_update_events

	; if MLM_playback_set_timings[ch] is 0
	; (thus the timing was set to 0 during this loop)
	; then execute the next event immediately
	ld h,0
	ld l,c
	ld de,MLM_playback_set_timings
	add hl,hl
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)

	; compare de to 0
	push hl
		ld hl,0
		sbc hl,de
	pop hl
	jr z,MLM_update_check_execute_events

MLM_update_loop_next:
	;djnz MLM_update_loop ;; only one channel is used for deflemask mlm export, no need for this loop :)

	; Clear MLM_base_time_counter
	xor a,a
	ld (MLM_base_time_counter),a

	; if active mlm channel counter is 0,
	; then all channels have stopped, proceed
	; to call MLM_stop
	ld a,iyl
	or a,a ; cp a,0
	call z,MLM_stop
	
MLM_update_skip:
	ret

; stop song
MLM_stop:
	push hl
	push de
	push bc
	push af
		; clear MLM WRAM
		ld hl,MLM_wram_start
		ld de,MLM_wram_start+1
		ld bc,MLM_wram_end-MLM_wram_start-1
		ld (hl),0
		ldir

		; clear FM WRAM
		ld hl,FM_wram_start
		ld de,FM_wram_start+1
		ld bc,FM_wram_end-FM_wram_start-1
		ld (hl),0
		ldir

		; Set WRAM variables
		;ld a,1
		;ld (MLM_base_time),a

		; Clear other WRAM variables
		xor a,a
		ld (EXT_2CH_mode),a

		; Reset the banking to its
		; starting state (ZONE3 
		; mapped to $4000~7FFF)
		ld a,1
		in a,($0B)

		call ssg_stop
		call fm_stop
		call pa_stop
		call pb_stop
	pop af
	pop bc
	pop de
	pop hl
	ret

MLM_default_channel_volumes:
	db &1F, &1F, &1F, &1F, &1F, &1F ; ADPCM-A channels
	db &00, &00, &00, &00           ; FM channels
	db &0F, &0F, &0F                ; SSG channels

; a: song
MLM_play_song:
	push hl
	push de
	push af
	push bc
	push ix
		call MLM_stop
		call set_default_banks

		; set all channel timings to 0
		ld b,13
MLM_play_song_set_timing_loop:
		push bc
			ld a,b
			dec a
			ld bc,0
			call MLM_set_timing
		pop bc
		djnz MLM_play_song_set_timing_loop

		; Load MLM song header (hl = &MLM_START[song])
		ld h,0
		ld l,a
		add hl,hl
		ld de,MLM_START
		add hl,de
		ld e,(hl)
		inc hl
		ld d,(hl)
		ld hl,MLM_START
		add hl,de

		; Load MLM playback pointers
		;
		; u16* src = MLM_START[song];
		; u16* dst = MLM_playback_pointers;
		;
		; for (int i = 13; i > 0; i--)
		; { 
		;     *dst = *src + MLM_START; 
		;     
		;	  u8 playback_cnt = 0;
		; 
		;     if (*src != NULL)
		;        playback_cnt++;
		;	  MLM_playback_control[ch] = playback_cnt;
		;
		;     dst++; 
		;     src++; 
	    ; }
		ld de,MLM_playback_pointers
		ld ix,MLM_playback_control		
		ld b,13

MLM_play_song_loop:
		push bc
		push hl
		push de
			ld c,(hl)
			inc hl
			ld b,(hl)

			ld hl,MLM_START
			add hl,bc

			ex de,hl
			ld (hl),e
			inc hl
			ld (hl),d

			
			; if bc is zero jump to...
			push hl
				ld hl,0
				or a,a ; reset carry flag
				sbc hl,bc
			pop hl
			ld a,0
			jr z,MLM_play_song_loop_skip

			;xor a,a ; clear a
			;add a,c
			;add a,b
			;ld a,0
			;jr c,MLM_play_song_loop_dont_skip
			;jr z,MLM_play_song_loop_skip

MLM_play_song_loop_dont_skip:
			inc a

MLM_play_song_loop_skip:
			ld (ix+0),a
		pop de
		pop hl
		pop bc

		inc hl
		inc hl
		inc de
		inc de
		inc ix
		djnz MLM_play_song_loop

		; Load and set timer a
		ld e,(hl)
		inc hl
		ld d,(hl)
		ex de,hl
		call ta_counter_load_set

		; Load and set base time
		ex de,hl
		inc hl
		ld a,(hl)
		ld (MLM_base_time),a

		; Set other WRAM variables
		ld a,2
		ld (MLM_unused_block),a
		dec a ; ld a,1
		ld (MLM_current_block),a
		
		; Copy MLM_playback_pointers
		; to MLM_playback_start_pointers
		ld hl,MLM_playback_pointers
		ld de,MLM_playback_start_pointers
		ld bc,2*CHANNEL_COUNT
		ldir
	pop ix
	pop bc
	pop af
	pop de
	pop hl
	ret

; c: channel
; 225 t-states at worst, excluding function calls inside it.
MLM_update_events:
	push hl
	push de
	push af
	push ix
		; de = MLM_playback_pointers[ch]
		;ld h,0
		;ld l,c
		;add hl,hl
		;ld de,MLM_playback_pointers
		;add hl,de
		ld hl,MLM_playback_pointers
		ld e,(hl)
		inc hl
		ld d,(hl)

		; if MLM_playback_pointers[ch] == NULL then return
		push hl
			ld hl,0
			or a,a    ; clear carry flag
			sbc hl,de ; compare
		pop hl
		jr z,MLM_update_events_skip

		; If the first byte's most significant bit is 0, then
		; parse it and evaluate it as a note, else parse 
		; and evaluate it as a command
		ex de,hl
		;ld a,(hl)
		;bit 7,a
		;call z,MLM_parse_command
		;call nz,MLM_parse_note

		ld a,(hl)
		call MLM_parse_command

MLM_update_events_skip:
	pop ix
	pop af
	pop de
	pop hl
	ret

;   c:  channel
;   hl: source (playback pointer)
;   de: &MLM_playback_pointers[channel]+1
MLM_parse_note:
	push af
	push bc
	push hl
	push de
		ld a,c
		ld b,(hl)
		inc hl
		ld c,(hl)
		inc hl
		
		; if (channel < 6) MLM_parse_note_pa()
		cp a,6
		jp c,MLM_play_sample_pa

		cp a,10
		jp c,MLM_play_note_fm
		jp MLM_play_note_ssg
MLM_parse_note_end:
		; store playback pointer into WRAM
		ex de,hl
		ld (hl),d
		dec hl
		ld (hl),e
	pop de
	pop hl
	pop bc
	pop af
	ret

; [INPUT]
;   a:  channel
;   bc: source   (-TTTTTTS SSSSSSSS (Timing; Sample))
MLM_play_sample_pa:
	push de
	push bc
	push hl
		; Set sample
		push af
			ld a,b
			and a,%00000001
			ld d,a
			ld e,c
		pop af
		call PA_set_sample_addr

		; Set timing
		push af
			ld a,b
			srl a
			and a,%00111111
			ld c,a
			ld b,0
		pop af
		call MLM_set_timing

		; play sample
		ld h,0
		ld l,a
		ld de,PA_channel_on_masks
		add hl,de
		ld d,REG_PA_CTRL
		ld e,(hl) 
		rst RST_YM_WRITEB
	pop hl
	pop bc
	pop de
	jp MLM_parse_note_end

; [INPUT]
;   a:  channel+6
;   bc: source
MLM_play_note_fm:
	; Set Timing
	push bc
		; Mask timing
		push af
			ld a,b
			and a,%01111111
			ld c,a
			ld b,0
		pop af

		call MLM_set_timing
	pop bc

	; Play note
	push af
	push hl
	push de
	push bc
		; backup MLM channel number into b
		ld b,a

		; Lookup correct FM channel number
		sub a,6
		ld h,0
		ld l,a
		ld de,FM_channel_LUT
		add hl,de
		ld a,(hl)

		call FM_stop_channel

		; Set panning
		push bc
		push af
			ld h,0
			ld l,b
			ld de,MLM_channel_pannings
			add hl,de
			ld c,(hl)
			ld a,b
			call FM_set_panning
		pop af
		pop bc

		; Load instrument
		push bc
			ld h,0
			ld l,b
			ld de,MLM_channel_instruments
			add hl,de
			ld b,a
			ld c,(hl)
			call FM_load_instrument
		pop bc

		; Set attenuator
		push bc
			ld l,b
			ld h,0
			ld de,MLM_channel_volumes
			add hl,de
			ld c,(hl)
			call FM_set_attenuator
		pop bc

		ld b,a
		call FM_set_note

		ld d,REG_FM_KEY_ON
		or a,%11110000
		ld e,a
		rst RST_YM_WRITEA
	pop bc
	pop de
	pop hl
	pop af
	jp MLM_parse_note_end

; [INPUT]
;   a:  channel+10
;   bc: source (-TTTTTTT NNNNNNNN (Timing; Note))
MLM_play_note_ssg:
	push af
	push hl
	push bc
	push de
		; Set timing
		push bc
			push af
				ld a,b
				and a,%01111111
				ld c,a
			pop af

			ld b,0
			call MLM_set_timing
		pop bc

		ld b,a   ; backup MLM channel into b
		sub a,10 ; MLM channel to SSG channel (0~2)
		call SSG_set_note

		; Set attenuator
		ld h,0
		ld l,b
		ld de,MLM_channel_volumes
		add hl,de
		ld c,(hl)
		call SSG_set_attenuator

		; Set instrument
		ld h,0
		ld l,b
		ld de,MLM_channel_instruments
		add hl,de
		ld c,(hl)
		call SSG_set_instrument
	pop de
	pop bc
	pop hl
	pop af
	jp MLM_parse_note_end

;   c:  channel
;   hl: source (playback pointer)
;   de: &MLM_playback_pointers[channel]+1
MLM_parse_command:
	push af
	push bc
	push ix
	push hl
	push de
	push iy
		; Backup &MLM_playback_pointers[channel]+1
		; into ix
		ld ixl,e
		ld ixh,d

		; backup the command's first byte into iyl
		ld a,(hl)
		ld iyl,a

		; Lookup command argc and store it into a
		push hl
			ld l,(hl)
			ld h,0
			ld de,MLM_command_argc
			add hl,de
			ld a,(hl)
		pop hl

		; Lookup command vector and store it into de
		push hl
			ld l,(hl)
			ld h,0
			ld de,MLM_command_vectors
			add hl,hl
			add hl,de
			ld e,(hl)
			inc hl
			ld d,(hl)
		pop hl

		inc hl

		; If the command's argc is 0, 
		; just execute the command
		or a,a ; cp a,0
		jr z,MLM_parse_command_execute

		; if it isn't, load arguments into
		; MLM_event_arg_buffer beforehand
		; and add argc to hl
		push de
		push bc
			ld de,MLM_event_arg_buffer
			ld b,0
			ld c,a
			ldir
		pop bc
		pop de

MLM_parse_command_execute:
		ex de,hl
		jp (hl)

MLM_parse_command_end:
		ex de,hl
		
		; Load &MLM_playback_pointers[channel]
		; back into de
		ld e,ixl
		ld d,ixh

		; store playback pointer into WRAM
		ex de,hl
		ld (hl),d
		dec hl
		ld (hl),e

MLM_parse_command_end_skip_playback_pointer_set:
	pop iy
	pop de
	pop hl
	pop ix
	pop bc
	pop af
	ret

MLM_command_vectors:
	dw MLMCOM_end_of_list,         MLMCOM_note_off
	dw MLMCOM_set_instrument,      MLMCOM_wait_ticks_byte
	dw MLMCOM_wait_ticks_word,     MLMCOM_set_channel_volume
	dw MLMCOM_set_channel_panning, MLMCOM_set_master_volume
	dw MLMCOM_set_base_time,       MLMCOM_set_timer_b
	dw MLMCOM_small_position_jump, MLMCOM_big_position_jump
	dw MLMCOM_portamento_slide,    MLMCOM_porta_write
	dw MLMCOM_portb_write,         MLMCOM_set_timer_a
	dsw 16,  MLMCOM_wait_ticks_nibble
	dw MLMCOM_nop,                 MLMCOM_jump_in_current_zone
	dw MLMCOM_bankswitch_current_zone_and_jump_to_unused_zone
	dsw 13,  MLMCOM_invalid ; Invalid commands
	dsw 16,  MLMCOM_multi_porta_write
	dsw 16,  MLMCOM_multi_portb_write
	dsw 192, MLMCOM_invalid ; Invalid commands

MLM_command_argc:
	db &00, &01, &01, &01, &02, &02, &01, &02
	db &02, &02, &01, &02, &02, &02, &02, &02
	dsb 16, &00 ; Wait ticks nibble
	db &00, &02, &03
	dsb 13, 0   ; Invalid commands all have no arguments

	; multi port a write argcs
	db &04, &06, &08, &0A, &0C, &0E, &10, &12
	db &14, &16, &18, &1A, &1C, &1E, &20, &22

	; multi port b write argcs
	db &04, &06, &08, &0A, &0C, &0E, &10, &12
	db &14, &16, &18, &1A, &1C, &1E, &20, &22

	dsb 192, 0 ; Invalid commands all have no arguments

; a:  channel
; bc: timing
MLM_set_timing:
	push hl
	push de
		ld h,0
		ld l,a
		ld de,MLM_playback_timings
		add hl,hl
		add hl,de
		ld (hl),c
		inc hl
		ld (hl),b

		ld de,MLM_playback_set_timings-MLM_playback_timings
		add hl,de
		ld (hl),b
		dec hl
		ld (hl),c
	pop de
	pop hl
	ret

; c: channel
MLM_stop_channel:
	push hl
	push de
	push af
		ld h,0
		ld l,c
		ld de,MLM_stop_channel_LUT
		add hl,hl
		add hl,de
		ld e,(hl)
		inc hl
		ld d,(hl)
		ex de,hl
		jp (hl)
MLM_stop_channel_return:
	pop af
	pop de
	pop hl
	ret

MLM_stop_channel_LUT:
	dsw 6, MLM_stop_channel_return
	dsw 4, MLM_stop_channel_FM
	dsw 3, MLM_stop_channel_return

; c: channel
MLM_stop_channel_FM:
	push bc
	push hl
	push af
		ld hl,FM_channel_LUT
		ld b,0
		add hl,bc
		ld a,(hl)
		call FM_stop_channel
	pop af
	pop hl
	pop bc
	jp MLM_stop_channel_return

; c: channel
MLMCOM_end_of_list:
	push hl
	push de
	push af
	push bc
		; Set playback control to 0
		ld h,0
		ld l,c
		ld de,MLM_playback_control
		add hl,de
		ld (hl),0

		; Set timing to 1
		; (This is done to be sure that
		;  the next event won't be executed)
		ld a,c
		ld bc,1
		call MLM_set_timing
MLMCOM_end_of_list_return:
	pop bc
	pop af
	pop de
	pop hl
	jp MLM_parse_command_end

; c: channel
; Arguments:
; 	1. timing
MLMCOM_note_off:
	push hl
	push af
	push de
	push bc
		; switch (channel) {
		; case is_adpcma:
		;   PA_stop_sample(channel);
		;   break;
		;
		; case is_ssg:
		;   SSG_stop_channel(channel-10);
		;   break;
		;
		; default: // is fm
		;   FM_stop_channel(FM_channel_LUT[channel-6]);
		;   break;
		; }
		ld a,c
		cp a,6
		call c,PA_stop_sample
		jr c,MLMCOM_note_off_break

		cp a,10
		sub a,10
		call nc,SSG_stop_note
		jr nc,MLMCOM_note_off_break

		ld a,c
		sub a,6
		ld h,0
		ld l,a 
		ld de,FM_channel_LUT
		add hl,de
		ld a,(hl)
		call FM_stop_channel

MLMCOM_note_off_break:
		ld hl,MLM_event_arg_buffer
		ld a,c
		ld b,0
		ld c,(hl)
		call MLM_set_timing
	pop bc
	pop de
	pop af
	pop hl
	jp MLM_parse_command_end

; c: channel
; Arguments
;   1. instrument
MLMCOM_set_instrument:
	push af
	push hl
	push bc
		ld hl,MLM_event_arg_buffer
		ld a,(hl)
		ld b,0
		ld hl,MLM_channel_instruments
		add hl,bc
		ld (hl),a

		ld a,c
		ld bc,0
		call MLM_set_timing
	pop bc
	pop hl
	pop af
	jp MLM_parse_command_end

; c: channel
; Arguments:
;   1. timing
MLMCOM_wait_ticks_byte:
	push hl
	push bc
	push af
		ld hl,MLM_event_arg_buffer
		ld a,c
		ld b,0
		ld c,(hl)
		call MLM_set_timing
	pop af
	pop bc
	pop hl
	jp MLM_parse_command_end

; c: channel
; Arguments:
;   1. timing (LSB)
;   2. timing (MSB)
MLMCOM_wait_ticks_word:
	push hl
	push bc
	push af
	push ix
		ld ix,MLM_event_arg_buffer
		ld a,c
		ld b,(ix+1)
		ld c,(ix+0)
		call MLM_set_timing
	pop ix
	pop af
	pop bc
	pop hl
	jp MLM_parse_command_end

; c: channel
; Arguments:
;   1. Volume
;   2. Timing
MLMCOM_set_channel_volume:
	push ix
	push af
	push hl
	push bc
		ld ix,MLM_event_arg_buffer
		ld a,c ; backup channel into a

		; Store volume in 
		; MLM_channel_volumes[channel]
		ld h,0
		ld l,a
		ld bc,MLM_channel_volumes
		add hl,bc
		ld c,(ix+0)
		ld (hl),c

		; if channel is adpcma...
		cp a,6
		call c,PA_set_channel_volume
		jr c,MLMCOM_set_channel_volume_set_timing

		; elseif channel is fm...
		cp a,10
		jr c,MLMCOM_set_channel_volume_fm

		; else (channel is ssg)...
		push af
			sub a,10
			call SSG_set_attenuator
		pop af

MLMCOM_set_channel_volume_set_timing:
		ld c,(ix+1)
		ld b,0
		call MLM_set_timing
	pop bc
	pop hl
	pop af
	pop ix
	jp MLM_parse_command_end

MLMCOM_set_channel_volume_fm:
	push af
	push hl
	push de
		; Load actual FM channel number
		; from LUT into a
		sub a,6
		ld h,0
		ld l,a
		ld de,FM_channel_LUT
		add hl,de
		ld a,(hl)

		call FM_set_attenuator
	pop de
	pop hl
	pop af
	jr MLMCOM_set_channel_volume_set_timing

; c: channel
; Arguments:
;   1. %LRTTTTTT (Left on; Right on; Timing)
MLMCOM_set_channel_panning:
	push af
	push hl
	push bc
	push de
		; Load panning into c
		ld a,(MLM_event_arg_buffer)
		and a,%11000000
		ld b,a ; \
		ld a,c ;  |- Swap a and c sacrificing b
		ld c,b ; /

		; Store panning into 
		; MLM_channel_pannings[channel]
		ld h,0
		ld l,a
		ld de,MLM_channel_pannings
		add hl,de
		ld (hl),c

		; if channel is adpcma...
		cp a,6
		call c,PA_set_channel_panning
		jr c,MLMCOM_set_channel_panning_set_timing

		; elseif channel is FM...
		cp a,10
		call c,FM_set_panning

		; else channel is SSG, the panning will be
		; ignored since the SSG channels are mono

MLMCOM_set_channel_panning_set_timing:
		ld b,a ; backup channel in b
		ld a,(MLM_event_arg_buffer)
		and a,%00111111 ; Get timing
		ld c,a
		ld a,b
		ld b,0
		call MLM_set_timing
	pop de
	pop bc
	pop hl
	pop af
	jp MLM_parse_command_end

; c: channel
; Arguments:
;   1. %VVVVVVTT (Volume; Timing MSB)
;   2. %TTTTTTTT (Timing LSB)
MLMCOM_set_master_volume:
	push ix
	push af
	push de
	push bc
		ld ix,MLM_event_arg_buffer

		; Set master volume
		ld a,(ix+0)
		srl a ; %VVVVVV-- -> %-VVVVVV-
		srl a ; %-VVVVVV- -> %--VVVVVV
		ld d,REG_PA_MVOL
		ld e,a
		rst RST_YM_WRITEB

		; Set timing
		ld a,(ix+0)
		and a,%00000011
		ld b,a
		ld a,c
		ld c,(ix+1)
		call MLM_set_timing
	pop bc
	pop de
	pop af
	pop ix
	jp MLM_parse_command_end

; c: channel
; Arguments:
;   1. %BBBBBBBB (Base time)
;   2. %TTTTTTTT (Timing)
MLMCOM_set_base_time:
	push ix
	push af
		ld ix,MLM_event_arg_buffer

		; Set base time
		ld a,(ix+0)
		ld (MLM_base_time),a

		; Set timing
		ld a,c
		ld b,0
		ld c,(ix+1)
		call MLM_set_timing
	pop af
	pop ix
	jp MLM_parse_command_end

; c: channel
; Arguments:
;   1. %BBBBBBBB (timer B)
;   2. %TTTTTTTT (Timing)
MLMCOM_set_timer_b:
	jp MLM_parse_command_end
	push ix
	push de
	push bc
	push af
		ld ix,MLM_event_arg_buffer

		; Set Timer B (will be loaded later)
		ld e,(ix+0)
		ld d,REG_TMB_COUNTER 
		rst RST_YM_WRITEA

		; Set timing
		ld a,c
		ld c,(ix+1)
		ld b,0
		call MLM_set_timing
	pop af
	pop bc
	pop de
	pop ix
	jp MLM_parse_command_end

; c:  channel
; ix: &MLM_playback_pointers[channel]+1
; de: source (playback pointer)
; Arguments:
;   1. %OOOOOOOO (Offset)
MLMCOM_small_position_jump:
	push hl
	push de
	push ix
		ld hl,MLM_event_arg_buffer

		; Load offset and sign extend 
		; it to 16bit (result in bc)
		ld a,(hl)
		ld l,c     ; Backup channel into l
		call AtoBCextendendsign

		; Add offset to playback 
		; pointer and store it into 
		; MLM_playback_pointers[channel]
		ld a,l ; Backup channel into a
		ld l,e
		ld h,d
		add hl,bc
		ld (ix-1),l
		ld (ix-0),h

		; Set timing to 0
		ld bc,0
		call MLM_set_timing
	pop ix
	pop de
	pop hl
	jp MLM_parse_command_end_skip_playback_pointer_set

; c:  channel
; ix: &MLM_playback_pointers[channel]+1
; de: source (playback pointer)
; Arguments:
;   1. %OOOOOOOO (Offset)
MLMCOM_big_position_jump:
	push hl
	push de
	push ix
		ld hl,MLM_event_arg_buffer

		; Load offset into bc
		ld a,c ; Backup channel into a
		ld c,(hl)
		inc hl
		ld b,(hl)

		; Add offset to playback 
		; pointer and store it into 
		; MLM_playback_pointers[channel]
		ld l,e
		ld h,d
		add hl,bc
		ld (ix-1),l
		ld (ix-0),h

		; Set timing to 0
		ld bc,0
		call MLM_set_timing
	pop ix
	pop de
	pop hl
	jp MLM_parse_command_end_skip_playback_pointer_set

; c: channel
; Arguments:
;   1. %SSSSSSSS (Signed pitch offset per tick)
;   2. %TTTTTTTT (Timing)
MLMCOM_portamento_slide:
	jp MLM_parse_command_end
	push hl
	push de
	push ix
	push bc
	push af
		ld ixl,c ; Backup MLM channel into ixl

		; Jump to the end of the subroutine
		; if the channel isn't FM
		ld a,c
		cp a,MLM_CH_FM1   ; if a < MLM_CH_FM1
		jr c,MLMCOM_portamento_slide_skip
		cp a,MLM_CH_FM4+1 ; if a > MLM_CH_FM4
		jr nc,MLMCOM_portamento_slide_skip

		; Load internal fm channel into l
		ld h,0
		ld l,c
		ld de,FM_channel_LUT-MLM_CH_FM1
		add hl,de
		ld l,(hl)

		; Load 8bit signed pitch offset, sign extend
		; it to 16bit, then store it into WRAM
		ld a,(MLM_event_arg_buffer)
		;call AtoBCextendendsign
		ld h,0
		;ld de,FM_portamento_slide
		add hl,hl
		add hl,de
		ld (hl),c
		inc hl
		ld (hl),b
		
MLMCOM_portamento_slide_skip:
		ld a,(MLM_event_arg_buffer+1)
		ld c,a
		ld a,ixl
		ld b,0
		call MLM_set_timing
	pop af
	pop bc
	pop ix
	pop de
	pop hl
	jp MLM_parse_command_end

; c: channel
; Arguments:
;   1. %AAAAAAAA (Address)
;   2. %DDDDDDDD (Data)
MLMCOM_porta_write:
	push de
	push ix
	push af
	push bc
		ld ix,MLM_event_arg_buffer

		ld d,(ix+0)
		ld e,(ix+1)
		rst RST_YM_WRITEA

		ld a,c
		ld bc,0
		call MLM_set_timing

		; If address isn't equal to 
		; REG_TIMER_CNT return
		ld a,d
		cp a,REG_TIMER_CNT
		jr nz,MLMCOM_porta_write_return

		; If address is equal to &27, then
		; store the data's 7th bit in WRAM
		ld a,e
		and a,%01000000 ; bit 6 enables 2CH mode
		ld (EXT_2CH_mode),a
		
MLMCOM_porta_write_return:
	pop bc
	pop af
	pop ix
	pop de
	jp MLM_parse_command_end

; c: channel
; Arguments:
;   1. %AAAAAAAA (Address)
;   2. %DDDDDDDD (Data)
MLMCOM_portb_write:
	push de
	push ix
	push af
	push bc
		ld ix,MLM_event_arg_buffer

		ld d,(ix+0)
		ld e,(ix+1)
		rst RST_YM_WRITEB

		ld a,c
		ld bc,0
		call MLM_set_timing
	pop bc
	pop af
	pop ix
	pop de
	jp MLM_parse_command_end

; c: channel
; Arguments:
;   1. %AAAAAAAA (timer A MSB) 
;   2. %TTTTTTAA (Timing; timer A LSB)
MLMCOM_set_timer_a:
	push ix
	push bc
	push af
	push de
		ld ix,MLM_event_arg_buffer
		ld e,c ; backup channel in e

		; Set timer a counter load
		ld d,REG_TMA_COUNTER_MSB
		ld e,(ix+0)
		rst RST_YM_WRITEA
		inc d
		ld e,(ix+1)
		rst RST_YM_WRITEA
		ld de,(REG_TIMER_CNT<<8) | %10101
		RST RST_YM_WRITEA

		ld b,0
		ld a,(ix+1)
		srl a
		srl a
		ld c,a
		ld a,e
		call MLM_set_timing
	pop de
	pop af
	pop bc
	pop ix
	jp MLM_parse_command_end

; c: channel
; de: playback pointer
MLMCOM_wait_ticks_nibble:
	push hl
	push af
	push bc
		; Load command ($1T) in a
		ld h,d
		ld l,e
		dec hl
		ld a,(hl)
		ld l,c ; backup channel

		and a,&0F ; get timing
		ld c,a
		ld b,0
		ld a,l
		call MLM_set_timing
	pop bc
	pop af
	pop hl
	jp MLM_parse_command_end

; c: channel
MLMCOM_nop:
	push af
	push bc
		ld a,c
		ld bc,0
		call MLM_set_timing
	pop bc
	pop af
	jp MLM_parse_command_end

; c:  channel
; ix: &MLM_playback_pointers[channel]+1
; Arguments:
;	1. %AAAAAAAA (Address LSB) 
;   2. %---AAAAA (Address MSB)
MLMCOM_jump_in_current_zone:
	push af
	push bc
	push iy
	push hl
		ld iy,MLM_event_arg_buffer

		ld a,(MLM_current_block)  ; - Store current block in b
		ld b,a                    ; /
		call MLM_get_current_zone ; Store current zone in a
		ld l,(iy+0)               ; - Store relative addr. in hl
		ld h,(iy+1)               ; /
		call MLM_zone_relative_addr_to_ptr

		ld (ix-1),l
		ld (ix-0),h

		ld a,c
		ld bc,0
		call MLM_set_timing
	pop hl
	pop iy
	pop bc
	pop af
	jp MLM_parse_command_end_skip_playback_pointer_set

; c:  channel
; ix: &MLM_playback_pointers[channel]+1
; Arguments:
;   1. %AAAAAAAA (Address LSB) 
;   2. %-----AAA (Address MSB)
;   3. %BBBBBBBB (Bank)
MLMCOM_bankswitch_current_zone_and_jump_to_unused_zone:
	push iy
	push af
	push bc
	push hl
		ld a,&39
		ld (breakpoint),a
		
		ld iy,MLM_event_arg_buffer

		; Convert relative addr. inbetween 
		; $0000 and $07FF to actual pointer
		ld a,(MLM_unused_block)
		ld b,a                    ; backup precedent unused block
		ld (MLM_current_block),a  ; The currently unused block will soon be the current block
		call MLM_get_current_zone ; - Get unused zone by negating current zone's bit 0.
		xor a,1                   ; / 
		ld l,(iy+0)               ; - Load relative address from argument buffer
		ld h,(iy+1)               ; /
		call MLM_zone_relative_addr_to_ptr

		; MLM_playback_pointers[channel] = hl
		ld (ix-1),l
		ld (ix-0),h

		ld a,(iy+2)
		call MLM_bankswitch_unused_zone

		ld a,c
		ld bc,0
		call MLM_set_timing
	pop hl
	pop bc
	pop af
	pop iy
	jp MLM_parse_command_end_skip_playback_pointer_set

; [input]
; 	ix: &playback_ptr + 1
; [output]
;   a: current zone (0: Zone 3; 1: Zone 2)
; Changes flags!! (WORKS CORRECTLY)
MLM_get_current_zone:
	; Assert that playback ptr is in valid bounds,
	; ($8000~$DFFF) if it isn't, crash the driver.
	ld a,(ix-0)
	cp a,&80
	call c,softlock  ; if a < &80  then...
	cp a,&E0
	call nc,softlock ; if a >= &E0 then...

	; If playback ptr is inbetween $8000~$BFFF,
	; it's in Zone 3, thus return 0. If that isn't
	; the case, then it must be in Zone 2 (inbetween)
	cp a,&C0
	ld a,0 
	ret c  ; if a < &C0 then...

	ld a,1
	ret    ; else...

; [input]
;   a: zone (0: Zone 3; 1: Zone 2)
;   b: bank
;   hl: relative address
; [output]
;   hl: pointer
; Changes flags!!!
MLM_zone_relative_addr_to_ptr:
	; Make sure relative addr. is inbetween $0000 and $07FF
	push af
		ld a,h
		and a,%00011111
		ld h,a
	pop af

	cp a,0
	jr z,MLM_zone_zone3_addr_to_ptr ; if a == ZONE3 then...

	; else... (a == ZONE2)
	push bc
		ld bc,BANK2
		add hl,bc
	pop bc
	ret

MLM_zone_zone3_addr_to_ptr:
	push bc
	push af
		; if bank is even, then return relative addr. + $8000
		; else, return relative addr. + $A000.
		;   It does this branchless by multiplying bit 0 by 32
		;   and then by 256 and then add it to the relative addr+$8000.
		;   if the bit was 0, then nothing else will be added, if the bit
		;   was 1 then $2000 will also be added. a+$8000+$2000 = a+$A000.
		ld a,b
		and a,1
		sla a ; \
		sla a ;  \
		sla a ;  | a *= 32
		sla a ;  /
		sla a ; /
		ld b,a
		ld c,0

		add hl,bc
		ld bc,$8000
		add hl,bc
	pop af
	pop bc
	ret

; ix: &playback_ptr + 1
; a: bank
MLM_bankswitch_unused_zone:
	push af
	push bc
		ld (MLM_unused_block),a
		ld b,a ; backup bank in b

		; Store current zone into a
		call MLM_get_current_zone
		
		; If current zone is Zone 3 (a=0),
		; then bankswitch Zone 2. Else, the
		; current zone is Zone 2, proceed
		; to bankswitch Zone 3.
		or a,a ; cp a,0
		jr z,MLM_bankswitch_zone2

		ld a,b ; load bank in a
		srl a  ; a /= 2
		in a,($0B)
	pop bc
	pop af
	ret

MLM_bankswitch_zone2:
		ld a,b ; load bank in a
		in a,($0A)
	pop bc
	pop af
	ret

; invalid command, plays a noisy beep
; and softlocks the driver
MLMCOM_invalid:
	call softlock

; c: channel
; de: playback pointer
; iyl: first command byte
; Arguments:
;   1. %AAAAAAAA (Address)
;   2. %DDDDDDDD (Data)
;   ...
MLMCOM_multi_porta_write:
	push de
	push ix
	push af
	push bc
		ld a,iyl
		and a,&0F
		ld b,a
		inc b
		inc b

		ld ix,MLM_event_arg_buffer

MLMCOM_multi_porta_write_loop:
		; Write to the YM2610
		ld d,(ix+0)
		ld e,(ix+1)
		rst RST_YM_WRITEA

		; If address isn't equal to 
		; REG_TIMER_CNT return
		ld a,d
		cp a,REG_TIMER_CNT
		jr nz,MLMCOM_porta_write_continue

		; If address is equal to &27, then
		; store the data's 7th bit in WRAM
		ld a,e
		and a,%01000000 ; bit 6 enables 2CH mode
		ld (EXT_2CH_mode),a
		
MLMCOM_porta_write_continue:
		inc ix
		inc ix
		djnz MLMCOM_multi_porta_write_loop

		; Set timing to 0
		ld a,c
		ld bc,0
		call MLM_set_timing
	pop bc
	pop af
	pop ix
	pop de
	jp MLM_parse_command_end

; c: channel
; de: playback pointer
; iyl: first command byte
; Arguments:
;   1. %AAAAAAAA (Address)
;   2. %DDDDDDDD (Data)
;   ...
MLMCOM_multi_portb_write:
	push de
	push ix
	push af
	push bc
		ld a,iyl
		and a,&0F
		ld b,a
		inc b
		inc b

		ld ix,MLM_event_arg_buffer

MLMCOM_multi_portb_write_loop:
		; Write to the YM2610
		ld d,(ix+0)
		ld e,(ix+1)
		rst RST_YM_WRITEB
		
		inc ix
		inc ix
		djnz MLMCOM_multi_portb_write_loop

		; Set timing to 0
		ld a,c
		ld bc,0
		call MLM_set_timing
	pop bc
	pop af
	pop ix
	pop de
	jp MLM_parse_command_end