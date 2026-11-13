.PHONY: help build app portrait-studio-app validate-portrait-studio-app launcher run-app run-app-simulated validate-app validate-launcher preview-performance-gate docs-check wave-capsule-test responsiveness-test portrait-baseline-check portrait-experiment-check drawing-app-test quick-test journey-test native-layout-test drawing-architecture-test test check strict-check

.DEFAULT_GOAL := help

SWIFT_FLAGS ?=
APP_CONFIGURATION ?= debug
NATIVE_LAYOUT_TEST_FILTER := PortraitStudioWorkspaceLayoutTests|PortraitStudioNativeLayoutTests
JOURNEY_TEST_FILTER := $(NATIVE_LAYOUT_TEST_FILTER)|PlotterApplicationRuntimeSparseTipCalibrationTests/(fullFourCornerMarkAcceptance|checkpointRevalidationRestoresWithoutAnotherMark|stageFourConsumesExactTipRevision)|PlotterBoundaryEpisodeTests/(boundaryRepeatActionsAggregateAndReplaceAcceptedSet|boundaryAtomicFailurePreservesAcceptedAuthority)|PlotterApplicationRuntimeTests/(resetBoundaryForwardRetainsEarlierLearning|resetObservedTrialAtomically)|PlotterCausalEpisodeEnvironmentTests/(drawingCompletion|cooperativeBoundaryStopRaces|cooperativeBoundaryAtTruth)
RESPONSIVENESS_TEST_FILTER := Plotter(PenInteraction|CameraCalibration|SpeechEffect|ControllerSession)EpisodeTests|PlotterEpisodeCompositionTests|PlotterApplicationRuntimeTests/resetAllKeepsCameraCalibrationReusable|OperatorWorkspaceAuthorityTests|OperatorWorkspaceSparseTipCalibrationTests|CameraCaptureTests|OverlayStateTests|WorkbenchTopBarLayoutTests|PlotterEpisodeUIActionabilityTests|PlotterLearningPresentationCompilerTests
DRAWING_APP_TEST_FILTER := DrawingBrowserTests|DrawingEditLifetimeTests|DrawingTransferRouteTests|DrawingLibraryAtomicRetentionTests|DrawingLibraryPhotoQueryTests|DrawingLibraryResultDiscoveryTests/discoverDrawingAfterReopen|FlowAuthoringNavigationTests|DrawingLibraryNavigationTests|DrawingLibraryAdoptionTests|DrawingLibraryWorkspaceTests|DrawingReviewerLayoutTests|WorkbenchStopCompositionTests

help:
	@printf '%s\n' \
		'Usage: make <target> [SWIFT_FLAGS="..."] [APP_CONFIGURATION=debug|release]' \
		'' \
		'Targets:' \
		'  help               Show this help.' \
		'  build              Compile the Swift package.' \
		'  release            Build optimized signed apps and refresh both Desktop app items.' \
		'  release-build      Build both optimized signed apps without publishing.' \
		'  publish-desktop    Safely refresh Desktop items from prepared release bundles.' \
		'  desktop-release-test Test publication, rollback, and collision handling in disposable homes.' \
		'  app                Build the signed debug app (APP_CONFIGURATION=release enables optimization).' \
		'  portrait-studio-app Build the independent signed Portrait Studio app.' \
		'  validate-portrait-studio-app Validate the independent Studio bundle without launching.' \
		'  launcher           Build the single-instance application launcher.' \
		'  run-app            Build and launch the supported local application.' \
		'  run-app-simulated  Launch signed causal simulation without camera startup.' \
		'  validate-app       Validate the application bundle and launcher.' \
		'  validate-launcher  Test launcher identity and instance handling.' \
		'  preview-performance-gate Run the signed app against the preferred camera and enforce preview isolation/CPU thresholds.' \
		'  docs-check         Validate canonical documents, vocabulary, and execution protocol.' \
		'  wave-capsule-test  Validate hash-bound wave capsule creation and consumption.' \
		'  responsiveness-test Validate Learning transitions and truthful workbench controls.' \
		'  portrait-baseline-check Compare the three current artists with frozen software outputs.' \
		'  portrait-experiment-check Run renderer baseline and SwiftSketch adapter checks.' \
		'  drawing-app-test   Exercise current Drawing browsing, editing, retention, reopen and Plotter handoff.' \
		'  quick-test         Run unit and component tests, excluding retained journeys.' \
		'  journey-test       Run retained causal and native layout journeys sequentially.' \
		'  native-layout-test Run native geometry, rendered controls and scrolling checks.' \
		'  drawing-architecture-test Verify the evaluated Drawing dependency closure.' \
		'  test               Run the complete Swift test suite in parallel.' \
		'  check              Validate the app, tests, and repository contract.' \
		'  strict-check       Run check with strict concurrency and warnings as errors.'

build:
	swift build $(SWIFT_FLAGS)

app:
	swift build $(SWIFT_FLAGS) -c "$(APP_CONFIGURATION)"
	@binary_directory="$$(swift build $(SWIFT_FLAGS) -c "$(APP_CONFIGURATION)" --show-bin-path)" && \
	case "$$binary_directory" in /*) ;; *) echo 'SwiftPM returned no absolute binary directory' >&2; exit 1 ;; esac && \
	APP_BINARY_DIRECTORY="$$binary_directory" sh Scripts/build_local_app.sh "$(APP_CONFIGURATION)"

portrait-studio-app:
	swift build $(SWIFT_FLAGS) -c "$(APP_CONFIGURATION)" --product PortraitStudio
	@binary_directory="$$(swift build $(SWIFT_FLAGS) -c "$(APP_CONFIGURATION)" --show-bin-path)" && \
	case "$$binary_directory" in /*) ;; *) echo 'SwiftPM returned no absolute binary directory' >&2; exit 1 ;; esac && \
	APP_BINARY_DIRECTORY="$$binary_directory" sh Scripts/build_portrait_studio_app.sh "$(APP_CONFIGURATION)"

validate-portrait-studio-app: portrait-studio-app
	@sh Scripts/validate_portrait_studio_app_bundle.sh .build/PortraitStudio.app

launcher:
	@sh Scripts/build_local_app_launcher.sh

validate-launcher: app launcher
	@sh Scripts/test_local_app_launcher.sh "$(CURDIR)/.build/AdaptivePlotter.app" "$(CURDIR)/.build/AdaptivePlotterLauncher"

validate-app: app validate-launcher
	@sh Scripts/validate_local_app_bundle.sh .build/AdaptivePlotter.app
	@sh Scripts/test_local_app_bundle_validation.sh .build/AdaptivePlotter.app

preview-performance-gate: app launcher
	@sh Scripts/check_running_app_preview_performance.sh \
		"$(CURDIR)/.build/AdaptivePlotter.app" \
		"$(PREVIEW_PERFORMANCE_EVIDENCE)" "$(or $(PREVIEW_PERFORMANCE_SCENARIO),preview)"

docs-check:
	@./.VE/bin/python Scripts/check_drawing_exchange_fixture.py
	@sh Scripts/check_episode_documentation.sh
	@./.VE/bin/python Scripts/check_episode_contract.py
	@PYTHONDONTWRITEBYTECODE=1 ./.VE/bin/python Scripts/test_episode_pilot_gate.py
	@PYTHONDONTWRITEBYTECODE=1 ./.VE/bin/python Scripts/test_episode_pilot_metrics.py
	@$(MAKE) wave-capsule-test
	@sh Scripts/check_repository_contract.sh
	@./.VE/bin/python Scripts/test_repository_contract.py

wave-capsule-test:
	@PYTHONDONTWRITEBYTECODE=1 ./.VE/bin/python Scripts/test_episode_wave_capsule.py

responsiveness-test:
	swift test --filter '$(RESPONSIVENESS_TEST_FILTER)' $(SWIFT_FLAGS)

portrait-baseline-check:
	swift test $(SWIFT_FLAGS) --no-parallel --filter PortraitBaselineTests

portrait-experiment-check:
	swift test $(SWIFT_FLAGS) --no-parallel --filter 'SwiftSketch|PortraitBaseline'

drawing-app-test:
	swift test $(SWIFT_FLAGS) --no-parallel --filter '$(DRAWING_APP_TEST_FILTER)'

run-app: app launcher
	@.build/AdaptivePlotterLauncher "$(CURDIR)/.build/AdaptivePlotter.app"

run-app-simulated: app launcher
	@.build/AdaptivePlotterLauncher --simulated "$(CURDIR)/.build/AdaptivePlotter.app"

quick-test:
	swift test --no-parallel --skip '$(JOURNEY_TEST_FILTER)' $(SWIFT_FLAGS)

native-layout-test:
	swift test --no-parallel --filter '$(NATIVE_LAYOUT_TEST_FILTER)' $(SWIFT_FLAGS)

drawing-architecture-test:
	@sh Scripts/check_drawing_architecture.sh $(SWIFT_FLAGS)

journey-test:
	swift test --no-parallel --filter '$(JOURNEY_TEST_FILTER)' $(SWIFT_FLAGS)

test: drawing-architecture-test
	swift test --parallel $(SWIFT_FLAGS)

check: validate-app test docs-check
	@git diff --check

strict-check:
	@$(MAKE) check SWIFT_FLAGS='-Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors'

# Optimized two-product release. Build serially so SwiftPM shares one build path.
.PHONY: release release-build publish-desktop
release: release-build
	@$(MAKE) publish-desktop

release-build:
	@$(MAKE) app APP_CONFIGURATION=release
	@$(MAKE) portrait-studio-app APP_CONFIGURATION=release
	@sh Scripts/validate_local_app_bundle.sh .build/AdaptivePlotter.app
	@sh Scripts/validate_portrait_studio_app_bundle.sh .build/PortraitStudio.app

publish-desktop:
	@python3 Scripts/publish_desktop_apps.py

.PHONY: desktop-release-test
desktop-release-test:
	@PYTHONDONTWRITEBYTECODE=1 python3 Scripts/test_desktop_release.py
	@PYTHONDONTWRITEBYTECODE=1 python3 Scripts/test_drawing_app_packaging.py
