APP_NAME := EZCal
APP      := build/$(APP_NAME).app

.DEFAULT_GOAL := help
.PHONY: help version release build run restart install uninstall test debug quit clean ios-test ios-device

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

version: ## Print the current app version
	@/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist

release: ## Sign, notarize and zip (VERSION=x.y.z)
	VERSION=$(VERSION) scripts/release.sh

build: ## Build build/EZCal.app
	scripts/build_app.sh

run: quit ## Quit any running copy, rebuild, and launch
	scripts/build_app.sh --run

restart: run ## Alias for run

install: quit ## Build and copy to /Applications
	scripts/build_app.sh --install

uninstall: quit ## Remove /Applications/EZCal.app
	rm -rf /Applications/$(APP_NAME).app

test: ## Run unit tests
	swift test

debug: ## Debug build, run the binary in the foreground with logs
	swift build
	.build/debug/$(APP_NAME)

quit: ## Quit the running app (if any)
	-@pkill -x $(APP_NAME) 2>/dev/null; true

clean: quit ## Remove build artifacts
	rm -rf build .build

IOS_UDID ?= 0E8B2ED5-63C3-4C99-BB6F-82F51B4FF290
ios-test: ## Run iOS XCUITests on the simulator
	cd Apps/iOS && xcodegen generate
	xcodebuild test -project Apps/iOS/EZCaliOS.xcodeproj -scheme EZCaliOS \
		-destination 'platform=iOS Simulator,id=$(IOS_UDID)' \
		-derivedDataPath build/ios-dd CODE_SIGNING_ALLOWED=NO $(ARGS)

# Real iPhone: needs your Apple Team ID (TEAM=ABCDE12345 or Apps/iOS/Config/Local.xcconfig). See Apps/iOS/README.md.
ios-device: ## Build & install on a connected iPhone (TEAM=<team id> DEVICE=<udid>)
	@test -n "$(DEVICE)" || { echo "Set DEVICE=<udid> (xcrun devicectl list devices)"; exit 1; }
	cd Apps/iOS && xcodegen generate
	xcodebuild build -project Apps/iOS/EZCaliOS.xcodeproj -scheme EZCaliOS \
		-destination 'platform=iOS,id=$(DEVICE)' -derivedDataPath build/ios-device-dd \
		-allowProvisioningUpdates $(if $(TEAM),DEVELOPMENT_TEAM=$(TEAM),)
	xcrun devicectl device install app --device $(DEVICE) build/ios-device-dd/Build/Products/Debug-iphoneos/EZCaliOS.app
	xcrun devicectl device process launch --device $(DEVICE) com.ezcal.app.ios
