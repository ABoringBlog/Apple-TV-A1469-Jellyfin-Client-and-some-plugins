CLANG ?= xcrun clang

IOS_SDK ?= $(HOME)/Downloads/AppleTV3/theos-sdks/iPhoneOS11.4.sdk
MIN_IOS ?= 8.0

BUILD ?= build/clock-0.1

SOURCES := \
	Sources/Clock/ClockAppliance.m \
	Sources/Clock/ClockBackRow.m

OBJECTS := $(patsubst Sources/Clock/%.m,$(BUILD)/armv7/%.o,$(SOURCES))

COMMON := \
	-fblocks \
	-fno-objc-arc \
	-Wall \
	-Wextra \
	-Wno-unused-parameter \
	-Wno-deprecated-declarations \
	-ISources/Clock

ARMFLAGS := \
	-target armv7-apple-ios$(MIN_IOS) \
	-isysroot "$(IOS_SDK)" \
	$(COMMON)

.PHONY: all clock

all: clock

$(BUILD)/armv7/%.o: Sources/Clock/%.m
	@mkdir -p $(@D)
	$(CLANG) $(ARMFLAGS) -MMD -MP -c $< -o $@

clock: $(OBJECTS)
	@mkdir -p $(BUILD)/Clock.frappliance
	cp Clock.frappliance/Info.plist $(BUILD)/Clock.frappliance/
	cp Clock.frappliance/AppIcon.png $(BUILD)/Clock.frappliance/
	cp Clock.frappliance/TopRowIcon.png $(BUILD)/Clock.frappliance/
	cp -R Clock.frappliance/English.lproj $(BUILD)/Clock.frappliance/
	$(CLANG) $(ARMFLAGS) \
		-bundle \
		$(OBJECTS) \
		-framework Foundation -framework CoreGraphics -framework ImageIO \
		-lobjc \
		-o $(BUILD)/Clock.frappliance/Clock

-include $(OBJECTS:.o=.d)
