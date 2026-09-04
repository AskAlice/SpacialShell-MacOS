# SpacialShell — thin wrappers over Scripts/ and swift build/test.
.PHONY: build release test test-all bundle dmg dev run clean raycast raycast-dev hooks install

hooks:            ## enable repo git hooks (pre-commit: build + fast tests + install)
	git config core.hooksPath .githooks
	@echo "hooks enabled; SPACIAL_SKIP_INSTALL=1 or --no-verify to bypass"

install: bundle   ## bundle + install to /Applications (same as the pre-commit hook)
	rm -rf /Applications/SpacialShell.app
	cp -R build/SpacialShell.app /Applications/SpacialShell.app

build:            ## debug build
	swift build

release:          ## release build
	swift build -c release

test:             ## CI-safe unit gate (skips AX/hotkey suites)
	swift test --skip SpacialShellPlatformTests --skip PlatformIntegrationTests

test-all:         ## everything, needs Accessibility grant for the test host
	swift test

dev: run
run:              ## debug build + run in foreground (Ctrl-C restores windows)
	Scripts/dev.sh

bundle:           ## build/SpacialShell.app, ad-hoc signed
	Scripts/bundle.sh

dmg:              ## bundle + UDZO DMG (VERSION= overrides name)
	Scripts/package-dmg.sh

raycast:          ## typecheck the Raycast extension
	cd raycast && npm install && npm run typecheck

raycast-dev:      ## hot-reload the extension into Raycast
	cd raycast && npm install && npm run dev

clean:
	rm -rf .build build

help:             ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'
