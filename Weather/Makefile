CLANG ?= xcrun clang
IOS_SDK ?= $(HOME)/Downloads/AppleTV3/theos-sdks/iPhoneOS11.4.sdk
MIN_IOS ?= 8.0
LANGUAGE ?= zh
BUILD ?= build/weather-$(LANGUAGE)

ifeq ($(LANGUAGE),en)
LANGFLAG := -DWEATHER_LANG_EN=1
else ifeq ($(LANGUAGE),zh)
LANGFLAG := -DWEATHER_LANG_EN=0
else
$(error LANGUAGE must be en or zh)
endif

SOURCES := \
	Sources/Weather/WeatherAppliance.m \
	Sources/Weather/WeatherBackRow.m

OBJECTS := $(patsubst Sources/Weather/%.m,$(BUILD)/armv7/%.o,$(SOURCES))

COMMON := \
	-fblocks \
	-fno-objc-arc \
	-Wall \
	-Wextra \
	-Wno-unused-parameter \
	-Wno-deprecated-declarations \
	-ISources/Weather \
	$(LANGFLAG)

ARMFLAGS := \
	-target armv7-apple-ios$(MIN_IOS) \
	-isysroot "$(IOS_SDK)" \
	$(COMMON)

.PHONY: all weather clean

all: weather

$(BUILD)/armv7/%.o: Sources/Weather/%.m
	@mkdir -p $(@D)
	$(CLANG) $(ARMFLAGS) -MMD -MP -c $< -o $@

weather: $(OBJECTS)
	@mkdir -p $(BUILD)/Weather.frappliance
	cp Weather.frappliance/Info.plist $(BUILD)/Weather.frappliance/
	cp Weather.frappliance/AppIcon.png $(BUILD)/Weather.frappliance/
	cp Weather.frappliance/AppIcon@1080.png $(BUILD)/Weather.frappliance/
	cp Weather.frappliance/TopRowIcon.png $(BUILD)/Weather.frappliance/
	cp Weather.frappliance/TopRowIcon@1080.png $(BUILD)/Weather.frappliance/
	cp -R Weather.frappliance/English.lproj $(BUILD)/Weather.frappliance/
	$(CLANG) $(ARMFLAGS) \
		-bundle \
		$(OBJECTS) \
		-framework Foundation -framework CoreGraphics -framework CoreText -framework ImageIO \
		-lobjc \
		-o $(BUILD)/Weather.frappliance/Weather

clean:
	rm -rf build

-include $(OBJECTS:.o=.d)
