@testable import PortraitArtists
@testable import PortraitLibrary
@testable import PortraitStudioUI
import AppKit
import Foundation
import PlotterModel
import SwiftUI
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Portrait authoring")
struct PortraitDrawingTests {
  @Test("supplied reference photo produces face-localized portrait styles",
        .enabled(if: ProcessInfo.processInfo.environment["PORTRAIT_REFERENCE_PHOTO"] != nil))
  @MainActor
  func referencePhoto() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["PORTRAIT_REFERENCE_PHOTO"])
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let start = ContinuousClock.now
    let raster = try await Task.detached {
      try PortraitImageAnalyzer.analyze(data: data, options: PortraitAnalysisOptions())
    }.value
    #expect(raster.analysisSummary.contains("Face crop"))
    #expect(raster.analysisSummary.contains("Person background removed"))
    var programs: [DrawingProgram] = []
    for style in PortraitStyle.allCases {
      programs.append(try PortraitVectorizer.program(
        from: raster, pose: .front, style: style, strokeStyle: portraitTestStyle()))
    }
    print("Portrait reference: \(raster.analysisSummary); styles \(programs.map { $0.strokes.count }); elapsed \(start.duration(to: .now))")
    let comparison = HStack {
      ForEach(Array(programs.enumerated()), id: \.offset) { index, program in
        VStack {
          Text(PortraitStyle.allCases[index].rawValue).font(.headline)
          PortraitPlaneProgramPreview(preview: PortraitPlanePreviewSource().resolve(program: program, nominalWidth: 0.4)).frame(width: 300, height: 420)
        }
      }
    }.padding().background(.background)
    let renderer = ImageRenderer(content: comparison)
    let image = try #require(renderer.cgImage)
    try PortraitImageAnalyzer.encodedImage(image).write(to: URL(fileURLWithPath: "/tmp/adaptiveplotter-portrait-styles.png"))
    let presets = PortraitVectorPreset.allCases
    let variants = try presets.map { preset in
      try PortraitStyle.allCases.map { style in
        try PortraitVectorizer.program(from: raster, pose: .front, style: style,
          strokeStyle: portraitTestStyle(), vectorOptions: preset.options)
      }
    }
    let grid = VStack(alignment: .leading, spacing: 16) {
      Text("Marker estimate: 1.5 mm ink at 180 mm drawing height").font(.headline)
      ForEach(presets.indices, id: \.self) { row in
        Text(presets[row].rawValue).font(.headline)
        HStack {
          ForEach(PortraitStyle.allCases.indices, id: \.self) { column in
            VStack {
              Text(PortraitStyle.allCases[column].rawValue).font(.caption)
              PortraitPlaneProgramPreview(preview: PortraitPlanePreviewSource().resolve(program: variants[row][column], nominalWidth: 1.5))
                .frame(width: 180, height: 230)
              Text("\(variants[row][column].strokes.count) strokes").font(.caption2)
            }
          }
        }
      }
    }.padding().background(.white).foregroundStyle(.black)
    let gridImage = try #require(ImageRenderer(content: grid).cgImage)
    try PortraitImageAnalyzer.encodedImage(gridImage)
      .write(to: URL(fileURLWithPath: "/tmp/adaptiveplotter-portrait-marker-presets.png"))
    let recipes = PortraitStyle.allCases.map {
      PortraitStyleRecipe(id: "algorithm-\($0.rawValue)", title: $0.rawValue, seed: 0,
        style: $0, vectorOptions: PortraitVectorPreset.broadMarker.options, analysisOptions: .init())
    }
    let results = try await Task.detached(priority: .userInitiated) {
      var results: [PortraitRenderResult] = []
      for recipe in recipes {
        results.append(try await PortraitImageAnalyzer().render(.init(data: data,
          pose: .front, style: recipe.style, options: recipe.analysisOptions,
          cachedRaster: nil, strokeStyle: portraitTestStyle(), vectorOptions: recipe.vectorOptions)))
      }
      return results
    }.value
    let recipeGrid = ImageRenderer(content: VStack(spacing: 8) {
      Text("Drawing Studio · reproducible recipes · 1.2 mm marker at 180 mm height").font(.headline)
      HStack(alignment: .top, spacing: 8) {
        ForEach(recipes.indices, id: \.self) { index in
          VStack {
            Text(recipes[index].title).font(.headline)
            PortraitPlaneProgramPreview(preview: PortraitPlanePreviewSource().resolve(program: results[index].program, nominalWidth: 1.2))
              .frame(width: 220, height: 300)
            Text("\(results[index].program.strokes.count) strokes").font(.caption)
            Text(results[index].transformationSummary ?? "Original proportions").font(.caption2)
          }
        }
      }
    }.padding(12).background(.white).environment(\.colorScheme, .light))
    let recipeImage = try #require(recipeGrid.cgImage)
    try PortraitImageAnalyzer.encodedImage(recipeImage)
      .write(to: URL(fileURLWithPath: "/tmp/adaptiveplotter-portrait-recipes.png"))
  }

  @Test("older drawing evidence without source metadata remains readable")
  func legacyProgramReference() throws {
    let program = try PortraitVectorizer.program(from: portraitTestRaster(), pose: .front,
      style: .hatch, strokeStyle: portraitTestStyle())
    let reference = DrawingProgramEvidenceReference(programID: program.id, contentHash: program.contentHash)
    let decoded = try JSONDecoder().decode(DrawingProgramEvidenceReference.self, from: JSONEncoder().encode(reference))
    #expect(decoded.source == nil)
    #expect(decoded.contentHash == program.contentHash)
  }

  @Test("styles preserve deterministic vectors and source identity", arguments: PortraitStyle.allCases)
  func deterministicStyles(_ style: PortraitStyle) throws {
    let strokeStyle = try portraitTestStyle()
    let raster = portraitTestRaster()
    let first = try PortraitVectorizer.program(from: raster, pose: .front, style: style, strokeStyle: strokeStyle)
    let second = try PortraitVectorizer.program(from: raster, pose: .front, style: style, strokeStyle: strokeStyle)
    #expect(first == second)
    #expect(!first.strokes.isEmpty)
    #expect(first.strokes.allSatisfy { $0.style == strokeStyle && $0.semanticRole == .drawing })
    let decoded = try JSONDecoder().decode(DrawingProgram.self, from: JSONEncoder().encode(first))
    #expect(decoded == first)
    let left = try PortraitVectorizer.program(from: raster, pose: .left, style: style, strokeStyle: strokeStyle)
    #expect(left.contentHash != first.contentHash)
    #expect(left.source.sourceIdentifier.contains("pose=Left"))
  }

  @Test("tonal contours join into closed strokes without flattening the shape")
  func closedContours() throws {
    let width = 41
    let values = (0..<(width*width)).map { index in
      hypot(Double(index%width-20), Double(index/width-20)) < 12 ? 0.0 : 1.0
    }
    let raster = PortraitRaster(width: width, height: width, luminance: values,
                                provenance: "circle", analysisSummary: "fixture")
    let program = try PortraitVectorizer.program(from: raster, pose: .front, style: .contours,
                                                 levels: 1, strokeStyle: portraitTestStyle())
    #expect(program.strokes.count == 1)
    let path = try #require(program.strokes.first?.path)
    #expect(path.start == path.end)
    #expect(path.points.count > 8)
    #expect(path.points.count < 60)
    #expect(path.length > 170 && path.length < 210)
  }

  @Test("image decoding and FieldSpace conversion preserve the top of the portrait")
  func imageAndDrawingOrientation() throws {
    let data = try portraitTestImage()
    let raster = try PortraitImageAnalyzer.analyze(
      data: data, options: PortraitAnalysisOptions(cropToFace: false, removeBackground: false))
    #expect(raster.luminance[0] < 0.1)
    #expect(try #require(raster.luminance.last) > 0.9)
    let program = try PortraitVectorizer.program(from: raster, pose: .left, style: .hatch,
                                                 strokeStyle: portraitTestStyle())
    #expect(program.strokes.flatMap(\.path.points).allSatisfy { $0.y > 65 })
  }

  @Test("missed face detection retains the image for vectorization")
  func noFaceDoesNotBlockDrawing() throws {
    let raster = try PortraitImageAnalyzer.analyze(data: portraitTestImage(), options: PortraitAnalysisOptions())
    #expect(raster.analysisSummary.lowercased().contains("full photo"))
    let program = try PortraitVectorizer.program(from: raster, pose: .right, style: .hatch,
                                                 strokeStyle: portraitTestStyle())
    #expect(!program.strokes.isEmpty)
  }

  @Test("continuous hatch scans retain full runs instead of individual cell marks")
  func continuousHatching() throws {
    let raster = PortraitRaster(width: 100, height: 100, luminance: Array(repeating: 0.1, count: 10_000),
                                provenance: "dark", analysisSummary: "fixture")
    let hatch = try PortraitVectorizer.program(from: raster, pose: .front, style: .hatch, strokeStyle: portraitTestStyle())
    let cross = try PortraitVectorizer.program(from: raster, pose: .front, style: .crosshatch, strokeStyle: portraitTestStyle())
    #expect(hatch.strokes.count == 49)
    #expect(cross.strokes.count == 98)
    #expect(hatch.strokes.allSatisfy { $0.path.length == 100 })
  }

}

func portraitTestStyle() throws -> PlotterModel.StrokeStyle {
  try PlotterModel.StrokeStyle(nominalLineWidth: 0.4,
                  penProfileID: PenProfileID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))
}

func portraitTestRaster() -> PortraitRaster {
  let width = 80, height = 100
  let values = (0..<(width*height)).map { index -> Double in
    let x = Double(index%width-40)/30, y = Double(index/width-50)/42
    let radius = x*x+y*y
    return radius > 1 ? 1 : min(0.9, 0.15+radius*0.5+(x+1)*0.1)
  }
  return PortraitRaster(width: width, height: height, luminance: values,
                        provenance: "synthetic-tonal-ellipse", analysisSummary: "Synthetic fixture")
}

func portraitTestImage() throws -> Data {
  let width = 60, height = 80
  let bytes = Data((0..<(width*height)).map { $0/width < 20 ? UInt8(0) : UInt8(255) })
  let provider = try #require(CGDataProvider(data: bytes as CFData))
  let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8,
                                  bitsPerPixel: 8, bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
  return try PortraitImageAnalyzer.encodedImage(image)
}
