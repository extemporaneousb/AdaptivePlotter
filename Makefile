.PHONY: help build app launcher run-app run-app-simulated validate-app validate-launcher quick-test journey-test test check strict-check

.DEFAULT_GOAL := help

SWIFT_FLAGS ?=
JOURNEY_TEST_FILTER := OperatorWorkspaceSparseTipCalibrationTests/(fullFiveMarkAcceptance|checkpointRevalidationRestoresWithoutAnotherMark|stageFourConsumesExactTipRevision)|OperatorWorkspaceTests/(boundaryRepeatActionsAggregateAndReplaceAcceptedSet|boundaryAtomicFailurePreservesAcceptedAuthority|resetBoundaryForwardRetainsEarlierLearning|resetComparisonOnlyPreservesObservedLine)|SimulatedLearningRuntimeTests/(drawingCompletion|cooperativeBoundaryStopRaces|cooperativeBoundaryAtTruth)

help:
	@printf '%s\n' \
		'Usage: make <target> [SWIFT_FLAGS="..."]' \
		'' \
		'Targets:' \
		'  help               Show this help.' \
		'  build              Compile the Swift package.' \
		'  app                Build the signed local application bundle.' \
		'  launcher           Build the single-instance application launcher.' \
		'  run-app            Build and launch the supported local application.' \
		'  run-app-simulated  Launch signed causal simulation without camera startup.' \
		'  validate-app       Validate the application bundle and launcher.' \
		'  validate-launcher  Test launcher identity and instance handling.' \
		'  quick-test         Run unit and component tests, excluding retained journeys.' \
		'  journey-test       Run retained causal journeys sequentially.' \
		'  test               Run the complete Swift test suite in parallel.' \
		'  check              Validate the app, tests, and repository contract.' \
		'  strict-check       Run check with strict concurrency and warnings as errors.'

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

run-app-simulated: app launcher
	@.build/AdaptivePlotterLauncher --simulated "$(CURDIR)/.build/AdaptivePlotter.app"

quick-test:
	swift test --parallel --skip '$(JOURNEY_TEST_FILTER)' $(SWIFT_FLAGS)

journey-test:
	swift test --no-parallel --filter '$(JOURNEY_TEST_FILTER)' $(SWIFT_FLAGS)

test:
	swift test --parallel $(SWIFT_FLAGS)

check: validate-app test
	@sh Scripts/check_repository_contract.sh
	@git diff --check

strict-check:
	@$(MAKE) check SWIFT_FLAGS='-Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors'
