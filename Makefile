APP_NAME := EZCal
APP      := build/$(APP_NAME).app

.DEFAULT_GOAL := help
.PHONY: help build run restart install uninstall test debug quit clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

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
