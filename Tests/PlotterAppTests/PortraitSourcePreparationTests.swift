import CoreGraphics
import Foundation
import Testing
@testable import PlotterApp

@Suite("Portrait reusable source preparation")
struct PortraitSourcePreparationTests {
  @Test("one source analysis supplies different crops and resolutions with exact source coordinates")
  func cropReuse() throws {
    var faceCalls = 0, maskCalls = 0
    let data = try portraitTestImage()
    let extent = try PortraitSourceCropExtent(widthPixels: 6_000, heightPixels: 8_000)
    let prepared = try PortraitImageAnalyzer.prepareSource(data: data, sourcePixelExtent: extent,
      faceAnalyzer: { image in faceCalls += 1; return sourceFixtureFace(image) },
      personMaskAnalyzer: { image in
        maskCalls += 1
        return .init(image: try sourceFixtureImage(width: image.width, height: image.height) { _, y in
          y < image.height / 2 ? 255 : 0
        }, status: .applied, requestRevision: 1, unavailableReason: nil)
      })
    var rasters: [PortraitRaster] = []
    var maximumCoordinateError = 0.0
    for (margin, dimension) in [(0.05, 160), (0.5, 320), (0.8, 160)] {
      let raster = try PortraitImageAnalyzer.analyze(preparedSource: prepared,
        options: .init(cropToFace: true, removeBackground: true, faceCropMargin: margin),
        maximumDimension: dimension)
      let geometry = try #require(raster.analysisGeometry)
      let face = try #require(prepared.faceAnalysis.boundingBox)
      #expect(raster.faceAnalysis == prepared.faceAnalysis)
      let normalizedFace = try #require(raster.faceBounds)
      let xError = abs(Double(normalizedFace.minX) - (face.x - geometry.crop.x) / geometry.crop.width)
      let yError = abs(Double(normalizedFace.minY) - (face.y - geometry.crop.y) / geometry.crop.height)
      // CGRect uses CGFloat arithmetic; independent Double reconstruction can
      // differ by a few ULP. This is below 2e-15 of a crop, not a pixel tolerance.
      maximumCoordinateError = max(maximumCoordinateError, xError, yError)
      #expect(xError <= 8 * Double.ulpOfOne)
      #expect(yError <= 8 * Double.ulpOfOne)
      #expect(raster.sourceCropExtent?.widthPixels == geometry.crop.width * 100)
      #expect(raster.sourceCropExtent?.heightPixels == geometry.crop.height * 100)
      #expect(raster.personMask?.sourceMaskCrop == geometry.crop)
      #expect(raster.personMask?.status == .applied)
      #expect(geometry.preprocessingRevision == "portrait-analysis-v2")
      #expect(raster.provenance.contains("sourcePreparationRevision=1"))
      try raster.validateAnalysisEvidence()
      rasters.append(raster)
    }
    #expect(maximumCoordinateError <= 8 * Double.ulpOfOne)
    #expect(faceCalls == 1 && maskCalls == 1)
    #expect(rasters[0].analysisGeometry?.crop != rasters[1].analysisGeometry?.crop)
    #expect(max(rasters[1].width, rasters[1].height) == 320)
    #expect(Set(rasters.map(\.provenance)).count == 3)
  }

  @Test("area reduction suppresses high-frequency aliasing without rounding fractional crops")
  func filteredSampling() throws {
    let image = try sourceFixtureImage(width: 600, height: 600) { x, _ in x.isMultiple(of: 2) ? 0 : 255 }
    let source = try sourceFixturePreparation(image: image, keyByte: 1)
    // Deliberately retain only the sharp finest level, so this tests the crop
    // reducer rather than relying on a previously blurred pyramid level.
    let striped = PortraitSourcePreparation(key: source.key, image: image, sourcePixelExtent: source.sourcePixelExtent,
      faceAnalysis: source.faceAnalysis, personMask: source.personMask,
      levels: [.init(width: 600, height: 600,
        luminance: (0..<360_000).map { ($0 % 600).isMultiple(of: 2) ? 0 : 255 })])
    let reduced = try striped.sample(crop: CGRect(x: 0.5, y: 1.5, width: 592, height: 592), width: 74, height: 74)
    #expect(reduced.values.allSatisfy { abs($0 - 0.5) < 1e-12 })
    let shifted = try striped.sample(crop: CGRect(x: 1.5, y: 1.5, width: 592, height: 592), width: 74, height: 74)
    #expect(shifted.values == reduced.values)
    // A one-pixel black/white boundary cut at x=.25 integrates 3/4 black + 1/4 white.
    let exact = try striped.sample(crop: CGRect(x: 0.25, y: 0, width: 1, height: 1), width: 1, height: 1)
    #expect(abs(exact.values[0] - 0.25) < 1e-12)
  }

  @Test("multiscale evidence is consumed by broad and tight crops")
  func multiscaleSelection() throws {
    let image = try sourceFixtureImage(width: 600, height: 600) { x, y in UInt8((x + y) % 256) }
    let source = try sourceFixturePreparation(image: image, keyByte: 3)
    #expect(source.levels.map(\.width) == [600, 300, 150])
    let broad = try source.sample(crop: CGRect(x: 0, y: 0, width: 600, height: 600), width: 160, height: 160)
    let tight = try source.sample(crop: CGRect(x: 200, y: 200, width: 180, height: 180), width: 160, height: 160)
    #expect(broad.levelWidth == 300)
    #expect(tight.levelWidth == 600)
    #expect(source.retainedByteCount >= image.bytesPerRow * image.height + 600*600 + 300*300 + 150*150)
  }

  @Test("unavailable analyses remain explicit and are reused across background and framing changes")
  func unavailableReuse() throws {
    var faceCalls = 0, maskCalls = 0
    let source = try PortraitImageAnalyzer.prepareSource(data: portraitTestImage(), faceAnalyzer: { image in
      faceCalls += 1
      return PortraitFaceLandmarkAnalyzer.unavailable(width: image.width, height: image.height, reason: "fixture face failure")
    }, personMaskAnalyzer: { _ in
      maskCalls += 1
      return .init(image: nil, status: .unavailable, requestRevision: 1, unavailableReason: "fixture mask failure")
    })
    for masking in [false, true, false, true] {
      let raster = try PortraitImageAnalyzer.analyze(preparedSource: source,
        options: .init(cropToFace: true, removeBackground: masking))
      #expect(raster.faceAnalysis?.status == .unavailable)
      #expect(raster.analysisSummary.contains("fixture face failure"))
      #expect(raster.personMask?.status == (masking ? .unavailable : .notRequested))
      #expect(raster.personMask?.unavailableReason == (masking ? "fixture mask failure" : nil))
      #expect(raster.personMask?.requestRevision == (masking ? 1 : nil))
    }
    #expect(faceCalls == 1 && maskCalls == 1)
  }

  @Test("content, source metric and preparation revision identify reusable analysis")
  func sourceIdentity() throws {
    let data = try portraitTestImage()
    let first = PortraitSourcePreparation.Key(data: data, sourcePixelExtent: nil)
    #expect(first == PortraitSourcePreparation.Key(data: data, sourcePixelExtent: nil))
    #expect(first != PortraitSourcePreparation.Key(data: data + Data([0]), sourcePixelExtent: nil))
    #expect(first != PortraitSourcePreparation.Key(data: data,
      sourcePixelExtent: try .init(widthPixels: 600, heightPixels: 800)))
    var differentRevision = first; differentRevision.revision += 1
    #expect(first != differentRevision)
  }

  @Test("byte-bounded LRU shares identical source content, evicts least recent and drops removed photos")
  func sourceRetention() throws {
    let image = try sourceFixtureImage(width: 80, height: 80) { x, _ in UInt8(x) }
    let first = try sourceFixturePreparation(image: image, keyByte: 1)
    let second = try sourceFixturePreparation(image: image, keyByte: 2)
    let third = try sourceFixturePreparation(image: image, keyByte: 3)
    let ids = (0..<4).map { _ in UUID() }
    var cache = PortraitRenderCache(sourceByteLimit: first.retainedByteCount * 2)
    cache.insertSourcePreparation(first, for: ids[0])
    cache.insertSourcePreparation(second, for: ids[1])
    #expect(cache.sourcePreparationCount == 2)
    #expect(cache.sourcePreparation(for: ids[0])?.key == first.key)
    cache.insertSourcePreparation(third, for: ids[2])
    #expect(cache.sourcePreparation(for: ids[1]) == nil)
    #expect(cache.sourcePreparationBytes <= first.retainedByteCount * 2)
    cache.insertSourcePreparation(first, for: ids[3])
    #expect(cache.sourcePreparationCount == 2)
    cache.remove(photoID: ids[0])
    #expect(cache.sourcePreparation(for: ids[3])?.key == first.key)
    cache.remove(photoID: ids[3])
    #expect(cache.sourcePreparationCount == 1)
    cache.insertSourcePreparation(first, for: ids[2])
    #expect(cache.sourcePreparation(for: ids[2])?.key == first.key)
    #expect(cache.sourcePreparationCount == 1)
    var tooSmall = PortraitRenderCache(sourceByteLimit: first.retainedByteCount - 1)
    tooSmall.insertSourcePreparation(first, for: ids[0])
    #expect(tooSmall.sourcePreparationCount == 0)
  }

  @Test("render accepts prepared analysis across resolution changes and records warm stage timing")
  func warmRender() async throws {
    let data = try portraitTestImage()
    let prepared = try PortraitImageAnalyzer.prepareSource(data: data,
      faceAnalyzer: { PortraitFaceLandmarkAnalyzer.retain(observations: [], width: $0.width, height: $0.height) },
      personMaskAnalyzer: { _ in .init(image: nil, status: .noPerson, requestRevision: 1, unavailableReason: "fixture") })
    let result = try await PortraitImageAnalyzer().render(.init(data: data, pose: .front, style: .hatch,
      options: .init(cropToFace: false, removeBackground: false), cachedRaster: nil,
      strokeStyle: portraitTestStyle(), preparedSource: prepared))
    #expect(result.timings?.sourceCacheHit == true)
    #expect(result.timings?.rasterCacheHit == false)
    #expect(try #require(result.timings?.cropMS) >= 0)
    #expect(result.preparedSource?.key == prepared.key)
    let key = PortraitRenderCacheKey(photoID: UUID(), configuration: .init(style: .hatch, vectors: .init(),
      analysis: .init(cropToFace: false, removeBackground: false)), strokeStyle: try portraitTestStyle())
    var cache = PortraitRenderCache()
    cache.insert(result, for: key)
    #expect(cache.sourcePreparation(for: key.photoID)?.key == prepared.key)
    #expect(cache.result(for: key)?.preparedSource == nil)
  }

  @Test("a no-lines recipe returns reusable preparation for the next crop")
  func failedRecipeReuse() async throws {
    let image = try sourceFixtureImage(width: 80, height: 80) { _, _ in 100 }
    let data = try PortraitImageAnalyzer.encodedImage(image)
    var faceCalls = 0, maskCalls = 0
    let source = try PortraitImageAnalyzer.prepareSource(data: data, faceAnalyzer: { image in
      faceCalls += 1; return sourceFixtureFace(image)
    }, personMaskAnalyzer: { _ in
      maskCalls += 1
      return .init(image: nil, status: .noPerson, requestRevision: 1, unavailableReason: "fixture")
    })
    let analyzer = PortraitImageAnalyzer(), pen = try portraitTestStyle(), photoID = UUID()
    var cache = PortraitRenderCache()
    do {
      _ = try await analyzer.render(.init(data: data, pose: .front, style: .contours,
        options: .init(cropToFace: true, removeBackground: false, faceCropMargin: 0.05),
        cachedRaster: nil, strokeStyle: pen, preparedSource: source))
      Issue.record("A constant field unexpectedly produced contour lines")
    } catch let failure as PortraitPreparedRenderFailure {
      guard let underlying = failure.underlyingError as? PortraitDrawingError, case .noLines = underlying else {
        Issue.record("Expected the original noLines failure"); return
      }
      #expect(failure.timings.sourceCacheHit)
      cache.insertSourcePreparation(failure.preparedSource, for: photoID)
    }
    let cached = cache.sourcePreparation(for: photoID)
    let retained = try #require(cached)
    let recovered = try await analyzer.render(.init(data: data, pose: .front, style: .hatch,
      options: .init(cropToFace: true, removeBackground: false, faceCropMargin: 0.8),
      cachedRaster: nil, strokeStyle: pen, preparedSource: retained))
    #expect(recovered.timings?.sourceCacheHit == true)
    #expect(!recovered.program.strokes.isEmpty)
    #expect(recovered.raster.faceAnalysis == source.faceAnalysis)
    #expect(faceCalls == 1 && maskCalls == 1)
  }

  @Test("cancellation prevents source publication between analysis stages and during reuse")
  func cancellation() async throws {
    let data = try portraitTestImage()
    let task = Task {
      try PortraitImageAnalyzer.prepareSource(data: data, faceAnalyzer: { image in
        withUnsafeCurrentTask { $0?.cancel() }
        return sourceFixtureFace(image)
      }, personMaskAnalyzer: { _ in
        Issue.record("mask analysis ran after cancellation")
        return .init(image: nil, status: .noPerson, requestRevision: 1, unavailableReason: "fixture")
      })
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    let source = try sourceFixturePreparation(image: sourceFixtureImage(width: 80, height: 80) { _, _ in 100 }, keyByte: 1)
    let reused = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try PortraitImageAnalyzer.analyze(preparedSource: source, options: .init())
    }
    await #expect(throws: CancellationError.self) { try await reused.value }
  }
}

private func sourceFixtureFace(_ image: CGImage) -> PortraitFaceAnalysis {
  PortraitFaceAnalysis(requestRevision: 3, constellation: 1, platformVersion: "fixture", status: .detected,
    unavailableReason: nil, decodedWidth: image.width, decodedHeight: image.height,
    boundingBox: .init(x: 18, y: 18, width: 24, height: 36), observationConfidence: 1, landmarksConfidence: 1,
    roll: nil, yaw: nil, pitch: nil, regions: [.init(kind: .leftEye,
      points: [.init(x: 24, y: 30)], precisionEstimates: nil, pointsClassification: 0)])
}

private func sourceFixtureImage(width: Int, height: Int, sample: (Int, Int) -> UInt8) throws -> CGImage {
  let bytes = Data((0..<(width * height)).map { sample($0 % width, $0 / width) })
  let provider = try #require(CGDataProvider(data: bytes as CFData))
  return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
    bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
}

private func sourceFixturePreparation(image: CGImage, keyByte: UInt8) throws -> PortraitSourcePreparation {
  let data = try PortraitImageAnalyzer.encodedImage(image)
  let source = try PortraitImageAnalyzer.prepareSource(data: data,
    faceAnalyzer: { PortraitFaceLandmarkAnalyzer.retain(observations: [], width: $0.width, height: $0.height) },
    personMaskAnalyzer: { _ in .init(image: nil, status: .noPerson, requestRevision: 1, unavailableReason: "fixture") })
  return PortraitSourcePreparation(key: .init(data: Data([keyByte]), sourcePixelExtent: nil), image: source.image,
    sourcePixelExtent: source.sourcePixelExtent, faceAnalysis: source.faceAnalysis, personMask: source.personMask,
    levels: source.levels)
}
