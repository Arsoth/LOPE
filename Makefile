APP := lope
SRC := Sources/logitech_onboard.m
# The C implementation is intentionally one translation unit, assembled from
# focused .inc modules so static helper linkage and original call ordering stay intact.
C_MODULES := $(wildcard Sources/logitech_onboard_*.inc)
GUI_APP := LOPE.app
GUI_BIN := bin/LOPEGUI
GUI_SRC := $(wildcard Sources/*.swift)
PROFILE_FILES := $(wildcard Profiles/*.json)
GUI_TARGET := arm64-apple-macos13.0
GUI_BUNDLE := outputs/$(GUI_APP)
SWIFT_MODULE_CACHE := .build/module-cache
SWIFT_PROFILE_PARSER_TEST := .build/profile-output-parser-self-test
SWIFT_PROFILE_WRITE_TEST := .build/profile-write-self-test
GUI_MODEL_SRC := $(filter-out Sources/AppMain.swift Sources/ContentView.swift,$(GUI_SRC))
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

$(GUI_BIN): $(GUI_SRC) $(PROFILE_FILES)
	@mkdir -p bin $(SWIFT_MODULE_CACHE)
	swiftc -O -parse-as-library -target $(GUI_TARGET) -module-cache-path $(SWIFT_MODULE_CACHE) -framework SwiftUI -framework AppKit -framework ApplicationServices -framework IOKit $(GUI_SRC) -o $(GUI_BIN)

app: build gui
	@mkdir -p $(GUI_BUNDLE)/Contents/MacOS $(GUI_BUNDLE)/Contents/Resources/MouseProfiles
	cp -f $(GUI_BIN) $(GUI_BUNDLE)/Contents/MacOS/LOPE
	cp -f bin/$(APP) $(GUI_BUNDLE)/Contents/Resources/$(APP)
	cp -f $(PROFILE_FILES) $(GUI_BUNDLE)/Contents/Resources/MouseProfiles/
	cp -f App/Info.plist $(GUI_BUNDLE)/Contents/Info.plist
	@codesign --force --deep --sign "$(SIGNING_IDENTITY)" $(GUI_BUNDLE) >/dev/null

test: $(APP) $(SWIFT_PROFILE_PARSER_TEST) $(SWIFT_PROFILE_WRITE_TEST)
	./$(APP) self-test
	./$(SWIFT_PROFILE_PARSER_TEST)
	./$(SWIFT_PROFILE_WRITE_TEST)

$(SWIFT_PROFILE_PARSER_TEST): Sources/AppModels.swift Sources/AppSupport.swift Sources/BackupStorage.swift Sources/DeviceClassification.swift Sources/DPIModel.swift Sources/MouseProfileCatalog.swift Sources/PollingRateModel.swift Sources/ProfileOutputParser.swift Sources/ProfileSelection.swift Sources/RefreshGuidance.swift Sources/RGBModel.swift $(PROFILE_FILES) Tests/ProfileOutputParserSelfTest.swift
	@mkdir -p .build
	swiftc -O -target $(GUI_TARGET) Sources/AppModels.swift Sources/AppSupport.swift Sources/BackupStorage.swift Sources/DeviceClassification.swift Sources/DPIModel.swift Sources/MouseProfileCatalog.swift Sources/PollingRateModel.swift Sources/ProfileOutputParser.swift Sources/ProfileSelection.swift Sources/RefreshGuidance.swift Sources/RGBModel.swift Tests/ProfileOutputParserSelfTest.swift -o $(SWIFT_PROFILE_PARSER_TEST)

$(SWIFT_PROFILE_WRITE_TEST): $(GUI_MODEL_SRC) $(PROFILE_FILES) Tests/ProfileWriteSelfTest.swift
	@mkdir -p .build
	swiftc -O -parse-as-library -target $(GUI_TARGET) -module-cache-path $(SWIFT_MODULE_CACHE) -framework AppKit -framework ApplicationServices -framework IOKit $(GUI_MODEL_SRC) Tests/ProfileWriteSelfTest.swift -o $(SWIFT_PROFILE_WRITE_TEST)

clean:
	rm -f $(APP) bin/$(APP) $(GUI_BIN) $(SWIFT_PROFILE_PARSER_TEST) $(SWIFT_PROFILE_WRITE_TEST)
