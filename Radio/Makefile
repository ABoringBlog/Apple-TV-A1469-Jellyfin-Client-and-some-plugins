CLANG ?= /usr/bin/clang
IOS_SDK ?= $(HOME)/Downloads/AppleTV3/theos-sdks/iPhoneOS11.4.sdk
MIN_IOS ?= 8.0
LANGUAGE ?= zh
BUILD ?= build/radio-$(LANGUAGE)

ifeq ($(LANGUAGE),en)
LANGFLAG := -DRADIO_LANG_EN=1
LOCALE := Localizations/en/InfoPlist.strings
else ifeq ($(LANGUAGE),zh)
LANGFLAG := -DRADIO_LANG_EN=0
LOCALE := Localizations/zh/InfoPlist.strings
else
$(error LANGUAGE must be en or zh)
endif

OUT := $(BUILD)/Radio.frappliance
SOURCES := Sources/Radio/RadioAppliance.m Sources/Radio/RadioBackRow.m
OBJECTS := $(patsubst Sources/Radio/%.m,$(BUILD)/armv7/%.o,$(SOURCES))
CFLAGS := -arch armv7 -isysroot "$(IOS_SDK)" -miphoneos-version-min=$(MIN_IOS) -fno-objc-arc -fblocks -I Sources/Radio $(LANGFLAG)
LDFLAGS := -Wl,-no_uuid -Wl,-install_name,/Applications/Radio.frappliance/InternetRadio -framework Foundation -framework CoreGraphics -framework CoreText -framework ImageIO -framework AVFoundation -framework CoreMedia -lobjc

.PHONY: all radio clean
all: radio

$(BUILD)/armv7/%.o: Sources/Radio/%.m
	@mkdir -p $(@D)
	$(CLANG) $(CFLAGS) -MMD -MP -c $< -o $@

radio: $(OBJECTS)
	@mkdir -p $(OUT)/English.lproj
	cp Radio.frappliance/Info.plist $(OUT)/Info.plist
	cp Radio.frappliance/AppIcon.png $(OUT)/
	cp Radio.frappliance/AppIcon@1080.png $(OUT)/
	cp $(LOCALE) $(OUT)/English.lproj/InfoPlist.strings
	$(CLANG) $(CFLAGS) -dynamiclib $(OBJECTS) $(LDFLAGS) -o $(OUT)/InternetRadio

clean:
	rm -rf build

-include $(OBJECTS:.o=.d)
