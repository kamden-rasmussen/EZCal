APP_NAME := EZCal
APP      := build/$(APP_NAME).app

.DEFAULT_GOAL := help
.PHONY: help version release build run restart install uninstall test debug quit clean ios-test ios-device ios-testflight

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

version: ## Print the current app version
	@/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist

release: ## Sign, notarize, publish to the tap, bump the cask (VERSION=x.y.z; PUBLISH=0 to only build)
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

# Simulator to test on: IOS_UDID=<udid> wins, else the iPhone named IOS_SIM (see `xcrun simctl list devices available`).
IOS_SIM ?= iPhone 17
IOS_DEST = $(if $(IOS_UDID),platform=iOS Simulator$(comma)id=$(IOS_UDID),platform=iOS Simulator$(comma)name=$(IOS_SIM))
IOS_WORKERS ?= 4
# A hung gesture test fails after this instead of stalling the run (slowest tests take ~110s under parallel load).
IOS_TIMEOUTS = -test-timeouts-enabled YES -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 300
comma := ,

# Fast tier for day-to-day work: one test per area. The full suite gates ios-testflight.
IOS_SMOKE_ARGS = \
	-only-testing:EZCaliOSUITests/AgendaNavigationUITests/testAgendaShowsEventsAndDetailSheet \
	-only-testing:EZCaliOSUITests/AgendaNavigationUITests/testTabSwitchAndNavigation \
	-only-testing:EZCaliOSUITests/AgendaNavigationUITests/testSettingsSheetShowsAccountStatus \
	-only-testing:EZCaliOSUITests/AgendaNavigationUITests/testSearchFindsEventsAndOpensDetail \
	-only-testing:EZCaliOSUITests/EventEditingUITests/testCreateEditDeleteEvent \
	-only-testing:EZCaliOSUITests/DayWeekGridUITests/testDayEventBlockOpensDetail \
	-only-testing:EZCaliOSUITests/DayWeekGridUITests/testLongPressDragMovesEvent \
	-only-testing:EZCaliOSUITests/MonthDetailUITests/testMonthShowsTodaySelectedAndEvents \
	-only-testing:EZCaliOSUITests/StackedEventsUITests/testStackedCardAppearsOnceForMultiCalendarMeeting

ios-test-smoke: ## Run the fast iOS UI smoke tier (serial, ~2 min)
	cd Apps/iOS && xcodegen generate
	xcodebuild test -project Apps/iOS/EZCaliOS.xcodeproj -scheme EZCaliOS \
		-destination '$(IOS_DEST)' -derivedDataPath build/ios-dd CODE_SIGNING_ALLOWED=NO \
		-parallel-testing-enabled NO $(IOS_TIMEOUTS) $(IOS_SMOKE_ARGS) $(ARGS)

ios-test: ## Run the full iOS XCUITests in parallel on simulator clones (IOS_WORKERS=4)
	cd Apps/iOS && xcodegen generate
	xcodebuild test -project Apps/iOS/EZCaliOS.xcodeproj -scheme EZCaliOS \
		-destination '$(IOS_DEST)' -derivedDataPath build/ios-dd CODE_SIGNING_ALLOWED=NO \
		-parallel-testing-enabled YES -parallel-testing-worker-count $(IOS_WORKERS) $(IOS_TIMEOUTS) $(ARGS)

# Real iPhone: needs your Apple Team ID (TEAM=ABCDE12345 or Apps/iOS/Config/Local.xcconfig). See Apps/iOS/README.md.
ios-device: ## Build & install on a connected iPhone (TEAM=<team id> DEVICE=<udid>)
	@test -n "$(DEVICE)" || { echo "Set DEVICE=<udid> (xcrun devicectl list devices)"; exit 1; }
	cd Apps/iOS && xcodegen generate
	xcodebuild build -project Apps/iOS/EZCaliOS.xcodeproj -scheme EZCaliOS \
		-destination 'platform=iOS,id=$(DEVICE)' -derivedDataPath build/ios-device-dd \
		-allowProvisioningUpdates $(if $(TEAM),DEVELOPMENT_TEAM=$(TEAM),)
	xcrun devicectl device install app --device $(DEVICE) build/ios-device-dd/Build/Products/Debug-iphoneos/EZCaliOS.app
	xcrun devicectl device process launch --device $(DEVICE) com.ezcal.app.ios

# Archive + export an .ipa to build/ios/export (UPLOAD=1 uploads to App Store Connect instead). See Apps/iOS/README.md.
ios-testflight: ios-test ## Run the full UI suite, then archive iOS app for TestFlight (TEAM=<team id> BUILD=<n> UPLOAD=1 to upload)
	scripts/ios_testflight.sh
