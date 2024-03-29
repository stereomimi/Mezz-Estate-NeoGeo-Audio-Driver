    include "def.inc"

#target rom

#code SDATA_FBANK,$6000,$2000
MLM_header:
	dw MLM_odata_smp_lut-MLM_header ; Point to ADPCM-A sample table
	db 13 ; Song count
	.long (MLM_song_pa1-MLM_header) << 8 | 0
	.long (MLM_song_pa2-MLM_header) << 8 | 0
	.long (MLM_song_pa3-MLM_header) << 8 | 0
	.long (MLM_song_pa4-MLM_header) << 8 | 0
	.long (MLM_song_pa5-MLM_header) << 8 | 0
	.long (MLM_song_pa6-MLM_header) << 8 | 0
	.long (MLM_song_fm1-MLM_header) << 8 | 1
	.long (MLM_song_fm2-MLM_header) << 8 | 1
	.long (MLM_song_fm3-MLM_header) << 8 | 1
	.long (MLM_song_fm4-MLM_header) << 8 | 1
	.long (MLM_song_ssg1-MLM_header) << 8 | 2
	.long (MLM_song_ssg2-MLM_header) << 8 | 2
	.long (MLM_song_ssg3-MLM_header) << 8 | 2

MLM_song_instruments:
	; Instrument 0 (ADPCM-A)
	dw MLM_odata_smp_lut-MLM_header ; Point to ADPCM-A sample LUT (in Zone 1)
	ds 30,0 ; padding

	; Instrument 1 (SSG)
	db 1                               ; Mixing: Tone ON; Noise OFF
	db 0                               ; EG enable: OFF
	ds 3                               ; Skip EG information since EG is disabled
	dw $0000                           ; Mix macro      | MLM_odata_mix_macro1-MLM_header
	dw $0000                           ; Volume macro   | MLM_odata_vol_macro1-MLM_header
	dw $0000                           ; Arpeggio macro | MLM_odata_arp_macro1-MLM_header
	ds 21 ; Padding
	
	; Instrument 2 (FM)
	fm_ch_data 2,0,0,0                 ; feedback, algorithm, pms, ams
	db $F0                             ; Enable all 4 operators
	fm_op_data 3,1,38,2,31,0,4,6,1,7,0 ; dt,mul,tl,rs,a,am,d,d2,s,r,eg
	fm_op_data 3,0,40,2,31,0,4,5,1,7,0
	fm_op_data 3,0,13,0,31,0,9,5,1,7,0
	fm_op_data 3,1,10,0,31,0,4,3,1,7,0
	ds 1,0 ; Padding

MLM_odata_smp_lut:
	incbin "adpcma_sample_lut.bin"
MLM_odata_mix_macro1:
	db (30*3)-1 ; Macro length
	db 30       ; Set loop point to 30
	ds 15,$11  ; 30 frames with tone enabled and noise disabled
	ds 15,$22  ; 30 frames with tone disabled and noise enabled
	ds 15,$33  ; 30 frames with tone and noise enabled

MLM_odata_vol_macro1:
	db 24-1 ; Macro length
	db 16   ; Loop point
	;  F E  D C  B A  9 8  7 6  5 4  3 2  1 0
	db $EF, $CD, $AB, $89, $67, $45, $23, $01
	;  2 4  6 8  A C  E F 
	db $42, $86, $CA, $FE

MLM_odata_arp_macro1:
	db 10-1 ; Macro length
	db 2    ; Loop point
	db -2,-2,-1,-1, 0, 0, 1, 1, 2, 2

#code SDATA_BANK0,$8000,$8000
MLM_song_pa1:
	dw MLM_el_pa-MLM_header
	ds 12*2, 0
	dw 98 ; Timer A frequency
	db 1  ; base time (0 is invalid)
	dw MLM_song_instruments-MLM_header

MLM_song_pa2
	dw 0
	dw MLM_el_pa-MLM_header
	ds 11*2,0
	dw 98 ; Timer A frequency
	db 1  ; base time (0 is invalid)
	dw MLM_song_instruments-MLM_header

MLM_song_pa3:
	ds 2*2,0
	dw MLM_el_pa-MLM_header
	ds 10*2,0
	dw 98 ; Timer A frequency
	db 1  ; base time (0 is invalid)
	dw MLM_song_instruments-MLM_header

MLM_song_pa4:
	ds 3*2,0
	dw MLM_el_pa-MLM_header
	ds 9*2,0
	dw 98 ; Timer A frequency
	db 1  ; base time (0 is invalid)
	dw MLM_song_instruments-MLM_header

MLM_song_pa5:
	ds 4*2,0
	dw MLM_el_pa-MLM_header
	ds 8*2,0
	dw 98 ; Timer A frequency
	db 1  ; base time (0 is invalid)
	dw MLM_song_instruments-MLM_header

MLM_song_pa6:
	ds 5*2,0
	dw MLM_el_pa-MLM_header
	ds 7*2,0
	dw 98 ; Timer A frequency
	db 1  ; base time (0 is invalid)
	dw MLM_song_instruments-MLM_header

MLM_el_pa: ; Start in Zone 3
	db $30 | 8 | (8-1) ; Offset volume by -8
	db $80 | 30, 0     ; Play ADPCM-A sample 0 (C)
	db $01, 30         ; Stop note and wait 30 ticks

	db $30 | (8-1)     ; Offset volume by +8
	db $80 | 30, 2     ; Play ADPCM-A sample 2 (D)
	db $01, 30
	db $0B
	dw MLM_el_pa-MLM_header

	db $00 ; End of song

#code SDATA_BANK1,$8000,$8000
MLM_song_fm1:
	ds 6*2,0
	dw MLM_el_fm-MLM_header
	ds 6*2,0
	dw 98 ; Timer A frequency
	db 1  ; base time (0 is invalid)
	dw MLM_song_instruments-MLM_header

MLM_song_fm2:
	ds 7*2,0
	dw MLM_el_fm-MLM_header
	ds 5*2,0
	dw 98 ; Timer A frequency
	db 1  ; base time (0 is invalid)
	dw MLM_song_instruments-MLM_header

MLM_song_fm3:
	ds 8*2,0
	dw MLM_el_fm-MLM_header
	ds 4*2,0
	dw 98 ; Timer A frequency
	db 1  ; base time (0 is invalid)
	dw MLM_song_instruments-MLM_header

MLM_song_fm4:
	ds 9*2,0
	dw MLM_el_fm-MLM_header
	ds 3*2,0
	dw 98 ; Timer A frequency
	db 1  ; base time (0 is invalid)
	dw MLM_song_instruments-MLM_header

MLM_el_fm2:
	db $02,2                     ; Set instrument to 2
	db $05,$FF                   ; Set channel volume
	db $06,%11000000             ; Set panning to CENTER
	db $80 | (8*3), 0 | (4 << 4) ; Play FM note C4 and wait 8*3 ticks
	db $80 | (8*3), 2 | (4 << 4) ; Play FM note D4 and wait 8*3 ticks
	db $01, 30                   ; Stop note and wait 30 ticks
	db $05,$E8                   ; Set channel volume
	db $06,%10000000             ; Set panning to LEFT
	db $80 | (8*3), 4 | (4 << 4) ; Play FM note E4 and wait 8*3 ticks
	db $06,%01000000             ; Set panning to RIGHT
	db $80 | (8*3), 5 | (4 << 4) ; Play FM note C4 and wait 8*3 ticks
	db $01, 30                   ; Stop note and wait 30 ticks
	db $0B
	dw MLM_el_fm-MLM_header

MLM_el_fm1:
	db $02,2                 ; Set instrument to 2
	db $22,255               ; Set pitch slide to -255
	db $80 | 2, 0 | (4 << 4) ; Play FM note C4 and wait 2 ticks
	db $21,32                ; Set pitch slide to +32
	db $03,16                ; Wait 16 ticks
	db $23                   ; Reset pitch slide
	db $03,64                ; Wait 64 ticks
	db $0B
	dw MLM_el_fm-MLM_header  ; Jump to MLM_el_fm

MLM_el_fm:
	db $02,2                   ; Set instrument to 2
	db $80 | 24, 11 | (3 << 4) ; Play A3 then wait 24 ticks
	db $0C, 32                 ; Slide (down) at 32 per tick
	db 2 | (3 << 4)            ; until D3
	db $03, 24-1               ; Wait 24 ticks
	db $0C, 64                 ; Slide (up) at 64 per tick
	db 4 | (4 << 4)            ; until E4
	db $03,128-1               ; Wait 128 ticks
	db $00

MLM_fm_vib_macro:
	db 8-1 ; Length: 8
	db 0   ; Loop point: 0
	db 0, 24, 32, 24, 0, -24, 32, -24

#code SDATA_BANK2,$8000,$8000
MLM_song_ssg1:
	ds 10*2,0
	dw MLM_el_ssg-MLM_header
	ds 2*2,0
	dw 98 ; Timer A frequency
	db 1  ; base time (0 is invalid)
	dw MLM_song_instruments-MLM_header

MLM_song_ssg2:
	ds 11*2,0
	dw MLM_el_ssg-MLM_header
	dw 0
	dw 98 ; Timer A frequency
	db 1  ; base time (0 is invalid)
	dw MLM_song_instruments-MLM_header

MLM_song_ssg3:
	ds 12*2,0
	dw MLM_el_ssg-MLM_header
	dw 98 ; Timer A frequency
	db 1  ; base time (0 is invalid)
	dw MLM_song_instruments-MLM_header
	
MLM_el_ssg:
	db $02,1                    ; Set instrument to 1
	db $80 | 24, 12*(4-2) + 0   ; Play C4 then wait 24 ticks
	db $0C, 32                  ; Slide at 32 per tick
	db 12*(3-2) + 9             ; till A3
	db $03, 24-1                ; Wait 24 ticks
	db $0C, 64                  ; Slide at 64 per tick
	db 12*(4-2) + 7             ; till G4
	db $03, 128-1               ; Wait 128 ticks
	db $00

MLM_ssg_pmacro:
	db 16-1 ; Length:     16
	db 8    ; Loop point: 8
	db 0,  8,  16, 32, 48, 64, 80, 96
	db 127, 80, 127, 80, 127, 80, 127, 80 