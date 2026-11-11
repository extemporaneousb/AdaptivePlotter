// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "AdaptivePlotter",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "PlotterModel", targets: ["PlotterModel"]),
    .library(name: "PortraitCore", targets: ["PortraitCore"]),
    .library(name: "DrawingLibrary", targets: ["DrawingLibrary"]),
    .library(name: "PlotterRuntime", targets: ["PlotterRuntime"]),
    .executable(name: "AdaptivePlotter", targets: ["PlotterApp"]),
    .executable(name: "PortraitStudio", targets: ["PortraitStudio"]),
    .executable(name: "DrawingDestinationHarness", targets: ["DrawingDestinationHarness"]),
  ],
  targets: [
    .executableTarget(name: "DrawingDestinationHarness", dependencies: ["DrawingLibrary", "PortraitCore", "PortraitLibrary", "PlotterModel"]),
    .target(name: "EpisodeCore"),
    .target(
      name: "EpisodeRuntime",
      dependencies: ["EpisodeCore"]
    ),
    .target(name: "PlotterModel"),
    .target(name: "PortraitCore", dependencies: ["PlotterModel"]),
    .target(
      name: "DrawingLibrary",
      dependencies: ["PortraitCore", "PlotterModel", "CSQLite"]
    ),
    .target(
      name: "PortraitArtists",
      dependencies: ["PortraitCore", "PlotterModel", "PlotterRuntime"]
    ),
    .target(
      name: "PortraitLibrary",
      dependencies: ["DrawingLibrary", "PortraitCore", "PortraitArtists", "PlotterModel", "PlotterRuntime"]
    ),
    .target(
      name: "PortraitStudioUI",
      dependencies: ["DrawingLibrary", "PortraitCore", "PortraitArtists", "PortraitLibrary", "PlotterModel", "PlotterRuntime"]
    ),
    .executableTarget(
      name: "PortraitStudio",
      dependencies: [
        "DrawingLibrary", "PortraitCore", "PortraitArtists", "PortraitLibrary", "PortraitStudioUI", "PlotterModel", "PlotterRuntime",
      ]
    ),
    .target(
      name: "PlotterEpisodeModel",
      dependencies: ["EpisodeCore", "PlotterModel"]
    ),
    .systemLibrary(name: "CSQLite"),
    .target(
      name: "PlotterRuntime",
      dependencies: ["PlotterModel", "PortraitCore", "CSQLite"]
    ),
    .target(
      name: "PlotterEpisodeRuntime",
      dependencies: ["EpisodeCore", "EpisodeRuntime", "PlotterEpisodeModel", "PlotterRuntime", "PortraitCore"]
    ),
    .target(
      name: "PlotterUI",
      dependencies: ["PlotterEpisodeModel"]
    ),
    .executableTarget(
      name: "PlotterApp",
      dependencies: [
        "EpisodeCore", "EpisodeRuntime", "PlotterEpisodeModel", "PlotterEpisodeRuntime", "PlotterModel",
        "PlotterRuntime", "PlotterUI", "CSQLite",
        "DrawingLibrary", "PortraitCore", "PortraitArtists", "PortraitLibrary", "PortraitStudioUI",
      ]
    ),
    .target(
      name: "PlotterTestSupport",
      dependencies: ["PlotterModel", "PlotterRuntime"]
    ),
    .testTarget(
      name: "DrawingLibraryTests",
      dependencies: ["DrawingLibrary", "PortraitCore", "PlotterModel", "CSQLite"]
    ),
    .testTarget(
      name: "EpisodeCoreTests",
      dependencies: ["EpisodeCore"]
    ),
    .testTarget(
      name: "EpisodeStoreTests",
      dependencies: ["EpisodeCore", "EpisodeRuntime"]
    ),
    .testTarget(
      name: "EpisodeRuntimeTests",
      dependencies: ["EpisodeCore", "EpisodeRuntime"]
    ),
    .testTarget(
      name: "PlotterModelTests",
      dependencies: ["PlotterModel"]
    ),
    .testTarget(
      name: "PlotterEpisodeModelContractTests",
      dependencies: ["EpisodeCore", "PlotterEpisodeModel", "PlotterModel"]
    ),
    .testTarget(
      name: "PlotterEpisodeRuntimeTests",
      dependencies: [
        "EpisodeCore", "PlotterEpisodeModel", "PlotterEpisodeRuntime", "PlotterRuntime",
        "PlotterTestSupport",
      ]
    ),
    .testTarget(
      name: "PlotterRuntimeTests",
      dependencies: ["PlotterRuntime", "PlotterTestSupport"]
    ),
    .testTarget(
      name: "PortraitStudioTests",
      dependencies: ["PortraitStudio", "DrawingLibrary", "PortraitCore", "PortraitArtists", "PortraitLibrary", "PortraitStudioUI", "PlotterModel", "PlotterRuntime"]
    ),
    .testTarget(
      name: "PlotterAppTests",
      dependencies: [
        "EpisodeCore", "PlotterApp", "PlotterEpisodeModel", "PlotterEpisodeRuntime",
        "PlotterRuntime", "PlotterTestSupport",
        "DrawingLibrary", "PortraitCore", "PortraitArtists", "PortraitLibrary", "PortraitStudioUI",
      ]
    ),
    .testTarget(
      name: "PlotterEpisodeUIActionabilityTests",
      dependencies: [
        "PlotterApp", "PlotterEpisodeModel", "PlotterEpisodeRuntime", "PlotterModel", "PlotterUI",
      ]
    ),
  ],
  swiftLanguageModes: [.v5]
)
