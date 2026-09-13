APP := lope
SRC := Sources/C/Core/main.m
C_MODULES := $(shell find Sources/C -type f -name '*.c' -print | sort)
C_HEADERS := $(shell find Sources/C -type f -name '*.h' -print | sort)
C_INCLUDE_FLAGS := -I Sources/C/Core -I Sources/C/HID -I Sources/C/Profiles \
	-I Sources/C/Backup -I Sources/C/Commands -I Sources/C/CLI -I Sources/C/Testing
GUI_APP := LOPE.app
GUI_BIN := bin/LOPEGUI
GUI_SRC := $(shell find Sources/Swift -type f -name '*.swift' ! -path 'Sources/Swift/Tests/*' -print | sort)
PROFILE_FILES := $(wildcard Profiles/*.json)
GUI_TARGET := arm64-apple-macos13.0
GUI_BUNDLE := outputs/$(GUI_APP)
SWIFT_MODULE_CACHE := .build/module-cache
C_SRC := $(SRC) $(C_MODULES) $(C_HEADERS)
# Release builds can provide the tag version/build number and a secure
# timestamp without changing the checked-in source plist.
APP_VERSION ?=
APP_BUILD ?=
CODESIGN_EXTRA_FLAGS ?=
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

.PHONY: all build gui app test clean format format-check lint install-hooks \
	coverage coverage-c coverage-swift coverage-check coverage-check-c coverage-check-swift

all: app

build: $(APP)

$(APP): $(SRC) $(C_MODULES) $(C_HEADERS)
	@mkdir -p bin
	clang $(CFLAGS) $(C_INCLUDE_FLAGS) $(FRAMEWORKS) $(SRC) $(C_MODULES) -o bin/$(APP)
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
	@if [ -n "$(APP_VERSION)" ]; then \
		/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(APP_VERSION)" $(GUI_BUNDLE)/Contents/Info.plist; \
	fi
	@if [ -n "$(APP_BUILD)" ]; then \
		/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(APP_BUILD)" $(GUI_BUNDLE)/Contents/Info.plist; \
	fi
	@codesign --force --deep --options runtime $(CODESIGN_EXTRA_FLAGS) --sign "$(SIGNING_IDENTITY)" $(GUI_BUNDLE) >/dev/null

# Swift package tests deliberately exercise the no-bundled-engine path. Remove
# the CLI artifacts generated for the C self-test before running XCTest.
test: $(APP)
	./$(APP) self-test
	@rm -f $(APP) bin/$(APP)
	swift test

SWIFT_FORMAT_CONFIG := .swift-format
SWIFT_FORMAT_PATHS := Sources/Swift Package.swift

format:
	xcrun swift-format format --configuration $(SWIFT_FORMAT_CONFIG) --in-place --recursive $(SWIFT_FORMAT_PATHS)
	clang-format -i $(C_SRC)

format-check:
	xcrun swift-format lint --configuration $(SWIFT_FORMAT_CONFIG) --strict --recursive $(SWIFT_FORMAT_PATHS)
	clang-format --dry-run --Werror $(C_SRC)

lint: format-check

install-hooks:
	@mkdir -p .git/hooks
	cp scripts/git-hooks/pre-commit .git/hooks/pre-commit
	chmod +x .git/hooks/pre-commit

# Coverage uses Clang/LLVM source-based instrumentation (-fprofile-instr-generate
# -fcoverage-mapping) for both languages so one toolchain (llvm-cov) reads both
# reports. The Swift frontend does not currently emit branch-region coverage
# mapping, so branch coverage is only meaningful for the C core; Swift is
# judged on line/region coverage only. See docs/development-standards.md.
COVERAGE_DIR := .build/coverage
COVERAGE_MIN_REGION ?= 90
COVERAGE_MIN_FUNCTION ?= 90
COVERAGE_MIN_LINE ?= 90
COVERAGE_MIN_BRANCH ?= 90
C_COVERAGE_BIN := $(COVERAGE_DIR)/lope-coverage
C_COVERAGE_PROFRAW := $(COVERAGE_DIR)/lope.profraw
C_COVERAGE_PROFDATA := $(COVERAGE_DIR)/lope.profdata
SWIFT_BIN_PATH = $(shell swift build --show-bin-path)
SWIFT_COVERAGE_PROFDATA = $(SWIFT_BIN_PATH)/codecov/default.profdata
SWIFT_TEST_BINARY = $(SWIFT_BIN_PATH)/LOPEPackageTests.xctest/Contents/MacOS/LOPEPackageTests

$(C_COVERAGE_PROFDATA): $(SRC) $(C_MODULES)
	@mkdir -p $(COVERAGE_DIR)
	@clang -std=c11 -Wall -Wextra -Wpedantic -fprofile-instr-generate -fcoverage-mapping $(C_INCLUDE_FLAGS) $(FRAMEWORKS) $(SRC) $(C_MODULES) -o $(C_COVERAGE_BIN)
	@LLVM_PROFILE_FILE=$(C_COVERAGE_PROFRAW) scripts/run-c-selftest-quiet.sh $(C_COVERAGE_BIN) self-test
	@xcrun llvm-profdata merge -sparse $(C_COVERAGE_PROFRAW) -o $(C_COVERAGE_PROFDATA)

coverage-c: $(C_COVERAGE_PROFDATA)
	@xcrun llvm-cov report $(C_COVERAGE_BIN) -instr-profile=$(C_COVERAGE_PROFDATA) --show-branch-summary --ignore-filename-regex='/Sources/C/Testing/|Core/types\.h|Profiles/g600\.h'

coverage-swift:
	@rm -f $(APP) bin/$(APP)
	@scripts/run-swift-test-quiet.sh --enable-code-coverage
	@xcrun llvm-cov report "$(SWIFT_TEST_BINARY)" -instr-profile="$(SWIFT_COVERAGE_PROFDATA)" --ignore-filename-regex='/Tests/|/Shims/|\.derived/'

coverage: coverage-c coverage-swift

coverage-check-c: $(C_COVERAGE_PROFDATA)
	@scripts/check-coverage.sh "C core" "Sources/(?!C/Testing/)" $(COVERAGE_MIN_REGION) $(COVERAGE_MIN_FUNCTION) $(COVERAGE_MIN_LINE) $(COVERAGE_MIN_BRANCH) -- $(C_COVERAGE_BIN) -instr-profile=$(C_COVERAGE_PROFDATA)

coverage-check-swift:
	@rm -f $(APP) bin/$(APP)
	@scripts/run-swift-test-quiet.sh --enable-code-coverage
	@scripts/check-coverage.sh "Swift" "/Sources/(?!Swift/Model/Shims/|Swift/Tests/)" $(COVERAGE_MIN_REGION) $(COVERAGE_MIN_FUNCTION) $(COVERAGE_MIN_LINE) -1 -- "$(SWIFT_TEST_BINARY)" -instr-profile="$(SWIFT_COVERAGE_PROFDATA)"

# Run both language gates even when the first one fails, so a single CI run
# reports the complete coverage picture instead of short-circuiting at C.
coverage-check:
	@coverage_status=0; \
	$(MAKE) coverage-check-c || coverage_status=$$?; \
	$(MAKE) coverage-check-swift || coverage_status=$$?; \
	exit $$coverage_status

clean:
	rm -rf $(APP) bin/$(APP) $(GUI_BIN) .build
