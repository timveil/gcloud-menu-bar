SCHEME       := GCloudMenuBar
BUILD_DIR    := build
ARCHIVE_PATH := $(BUILD_DIR)/$(SCHEME).xcarchive
EXPORT_PATH  := $(BUILD_DIR)/export

.PHONY: generate open build archive export clean help

## Generate Xcode project from project.yml (requires: brew install xcodegen)
generate:
	xcodegen generate

## Generate and open in Xcode
open: generate
	open $(SCHEME).xcodeproj

## Build Debug (no signing)
build: generate
	xcodebuild -scheme $(SCHEME) -configuration Debug \
	  -derivedDataPath $(BUILD_DIR)/derived build \
	  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
	  | xcpretty 2>/dev/null || true

## Create Release archive
archive: generate
	xcodebuild -scheme $(SCHEME) -configuration Release \
	  -archivePath $(ARCHIVE_PATH) archive

## Export Developer ID signed .app (requires ExportOptions.plist with your team ID)
export: archive
	xcodebuild -exportArchive -archivePath $(ARCHIVE_PATH) \
	  -exportPath $(EXPORT_PATH) -exportOptionsPlist ExportOptions.plist

## Remove build artifacts
clean:
	rm -rf $(BUILD_DIR)

## Show available targets
help:
	@grep -E '^##' Makefile | sed 's/## //'
