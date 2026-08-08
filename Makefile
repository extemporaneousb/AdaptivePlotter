.PHONY: build app launcher run-app validate-app validate-launcher test check strict-check

SWIFT_FLAGS ?=

build:
	swift build $(SWIFT_FLAGS)

app: build
	@sh Scripts/build_local_app.sh

launcher:
	@sh Scripts/build_local_app_launcher.sh

validate-launcher: app launcher
	@sh Scripts/test_local_app_launcher.sh "$(CURDIR)/.build/AdaptivePlotter.app" "$(CURDIR)/.build/AdaptivePlotterLauncher"

validate-app: app validate-launcher
	@sh Scripts/validate_local_app_bundle.sh .build/AdaptivePlotter.app
	@sh Scripts/test_local_app_bundle_validation.sh .build/AdaptivePlotter.app

run-app: app launcher
	@.build/AdaptivePlotterLauncher "$(CURDIR)/.build/AdaptivePlotter.app"

test:
	swift test --parallel $(SWIFT_FLAGS)

check: validate-app test
	@sh Scripts/check_repository_contract.sh
	@git diff --check

strict-check:
	@$(MAKE) check SWIFT_FLAGS='-Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors'
