CLANG ?= /usr/bin/clang
IOS_SDK ?= $(HOME)/Downloads/AppleTV3/theos-sdks/iPhoneOS11.4.sdk
MIN_IOS ?= 8.0
LANGUAGE ?= zh
BUILD ?= build/cloudtune-$(LANGUAGE)

ifeq ($(LANGUAGE),en)
LANGFLAG := -DCLOUDTUNE_LANG_EN=1
LOCALE := Localizations/en/InfoPlist.strings
else ifeq ($(LANGUAGE),zh)
LANGFLAG := -DCLOUDTUNE_LANG_EN=0
LOCALE := Localizations/zh/InfoPlist.strings
else
$(error LANGUAGE must be en or zh)
endif

OUT := $(BUILD)/CloudTune.frappliance
SOURCES := Sources/Music/MusicAppliance.m Sources/Music/MusicBackRow.m
OBJECTS := $(patsubst Sources/Music/%.m,$(BUILD)/armv7/%.o,$(SOURCES))

CFLAGS := -arch armv7 -isysroot "$(IOS_SDK)" -miphoneos-version-min=$(MIN_IOS) -fno-objc-arc -fblocks -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations -I Sources/Music $(LANGFLAG)
LDFLAGS := -Wl,-no_uuid -framework Foundation -framework CoreGraphics -framework CoreText -framework ImageIO -framework AVFoundation -framework CoreMedia -lobjc

.PHONY: all cloudtune clean
all: cloudtune

$(BUILD)/armv7/%.o: Sources/Music/%.m
	@mkdir -p $(@D)
	$(CLANG) $(CFLAGS) -MMD -MP -c $< -o $@

cloudtune: $(OBJECTS)
	@mkdir -p $(OUT)/English.lproj
	cp CloudTune.frappliance/Info.plist $(OUT)/Info.plist
	cp CloudTune.frappliance/AppIcon.png $(OUT)/
	cp CloudTune.frappliance/AppIcon@1080.png $(OUT)/
	cp $(LOCALE) $(OUT)/English.lproj/InfoPlist.strings
	$(CLANG) $(CFLAGS) -bundle $(OBJECTS) $(LDFLAGS) -o $(OUT)/CloudTune

clean:
	rm -rf build

-include $(OBJECTS:.o=.d)
