// swift-tools-version: 6.0
import Foundation
import PackageDescription
let repository = ProcessInfo.processInfo.environment["ADAPTIVEPLOTTER_REPOSITORY"]!
let package = Package(
  name: "DrawingLibraryPublicClient",
  platforms: [.macOS(.v14)],
  dependencies: [.package(name: "AdaptivePlotter", path: repository)],
  targets: [.executableTarget(name: "DrawingLibraryPublicClient", dependencies: [
    .product(name: "DrawingLibrary", package: "AdaptivePlotter"),
    .product(name: "PortraitCore", package: "AdaptivePlotter"),
    .product(name: "PlotterModel", package: "AdaptivePlotter"),
  ])],
  swiftLanguageModes: [.v5]
)
