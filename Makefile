APP := logitech-onboard
SRC := Sources/logitech_onboard.m
# The C implementation is intentionally one translation unit, assembled from
# focused .inc modules so static helper linkage and original call ordering stay intact.
C_MODULES := $(wildcard Sources/logitech_onboard_*.inc)
GUI_APP := LogitechOnboardProfileManager.app
GUI_BIN := bin/LogitechOnboardProfileManager
GUI_SRC := $(wildcard Sources/*.swift)
GUI_TARGET := arm64-apple-macos13.0
GUI_BUNDLE := outputs/$(GUI_APP)
SWIFT_MODULE_CACHE := .build/module-cache
# A stable signing identity lets macOS recognize rebuilt versions of the app
# as the same app for Input Monitoring. Override this when several identities
# are installed, for example:
#   make SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)"
SIGNING_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development:|Developer ID Application:/ {print $$2; exit}')
ifeq ($(strip $(SIGNING_IDENTITY)),)
SIGNING_IDENTITY := -
endif

CFLAGS := -std=c11 -Wall -Wextra -Wpedantic -O2
FRAMEWORKS := -framework IOKit -framework CoreFoundation

.PHONY: all build gui app test clean

all: app

build: $(APP)

$(APP): $(SRC) $(C_MODULES)
	@mkdir -p bin
	clang $(CFLAGS) $(FRAMEWORKS) $(SRC) -o bin/$(APP)
	@ln -sf bin/$(APP) $(APP)

gui: $(GUI_BIN)

$(GUI_BIN): $(GUI_SRC)
	@mkdir -p bin $(SWIFT_MODULE_CACHE)
	swiftc -O -parse-as-library -target $(GUI_TARGET) -module-cache-path $(SWIFT_MODULE_CACHE) -framework SwiftUI -framework AppKit $(GUI_SRC) -o $(GUI_BIN)

app: build gui
	@mkdir -p $(GUI_BUNDLE)/Contents/MacOS $(GUI_BUNDLE)/Contents/Resources
	cp -f $(GUI_BIN) $(GUI_BUNDLE)/Contents/MacOS/LogitechOnboardProfileManager
	cp -f bin/$(APP) $(GUI_BUNDLE)/Contents/Resources/$(APP)
	cp -f App/Info.plist $(GUI_BUNDLE)/Contents/Info.plist
	@codesign --force --deep --sign "$(SIGNING_IDENTITY)" $(GUI_BUNDLE) >/dev/null

test: $(APP)
	./$(APP) self-test

clean:
	rm -f $(APP) bin/$(APP) $(GUI_BIN)
