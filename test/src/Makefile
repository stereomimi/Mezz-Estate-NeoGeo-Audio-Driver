######## Mezz'Estate Studios NeoGeo PROM Makefile ########

include ../../Makefile.config

AS        := $(CROSS)as
LD        := $(CROSS)gcc
CC        := $(CROSS)gcc
OBJCOPY   := $(CROSS)objcopy

SFILES := $(wildcard *.s)
CFILES := $(wildcard *.c) $(wildcard neogeo/*.c)

SOBJS := $(SFILES:.s=.o)
COBJS := $(CFILES:.c=.o)
OBJS := $(SOBJS) $(COBJS)

#ASFLAGS :=
#CFLAGS  := -std=c99 -fomit-frame-pointer -g -Og -Wall -Wextra -Wpedantic -Winline -funsigned-char
CFLAGS  := -std=c99 -fomit-frame-pointer -O2 -Wall -Wextra -Wpedantic -Winline -funsigned-char
LDFLAGS := $(shell pkg-config --libs ngdevkit) -Wl,--defsym,rom_eye_catcher_mode=2 

build: prom.bin

prom.bin: prom.elf
	$(OBJCOPY) -v -O binary -S -R .comment $< $@
	$(DD) if=$@ of=$@ conv=notrunc,swab

prom.elf: $(OBJS)
	$(LD) $^ $(LDFLAGS) -o $@

# COBJS are compiled automatically

$(SOBJS): %.o : %.s
	$(AS) $(ASFLAGS) $< -o $@

.PHONY: clean

clean:
	rm -fvr $(OBJS) prom.elf prom.bin history
