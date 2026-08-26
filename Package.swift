// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "AdaptivePlotter",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "PlotterModel", targets: ["PlotterModel"]),
    .library(name: "PlotterRuntime", targets: ["PlotterRuntime"]),
    .executable(name: "AdaptivePlotter", targets: ["PlotterApp"]),
  ],
  targets: [
    .target(name: "EpisodeCore"),
    .target(
      name: "EpisodeRuntime",
      dependencies: ["EpisodeCore"]
    ),
    .target(name: "PlotterModel"),
    .target(
      name: "PlotterEpisodeModel",
      dependencies: ["EpisodeCore", "PlotterModel"]
    ),
    .systemLibrary(name: "CSQLite"),
    .target(
      name: "PlotterRuntime",
      dependencies: ["PlotterModel", "CSQLite"]
    ),
    .executableTarget(
      name: "PlotterApp",
      dependencies: ["PlotterModel", "PlotterRuntime"]
    ),
    .target(
      name: "PlotterTestSupport",
      dependencies: ["PlotterModel", "PlotterRuntime"]
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
      name: "PlotterRuntimeTests",
      dependencies: ["PlotterRuntime", "PlotterTestSupport"]
    ),
    .testTarget(
      name: "PlotterAppTests",
      dependencies: ["PlotterApp", "PlotterRuntime", "PlotterTestSupport"]
    ),
  ],
  swiftLanguageModes: [.v5]
)
