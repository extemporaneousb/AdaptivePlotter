import CoreGraphics
import CoreVideo
import CryptoKit
import Foundation
import ImageIO
import PlotterModel
import PortraitCore
import Vision

/// Source-owned preparation, independent of crop, output resolution and style.
/// CGImages are immutable; this value crosses to the serial render worker only.
package struct PortraitSourcePreparation: @unchecked Sendable {
  package static let revision = 1

  package struct Key: Hashable, Sendable {
    package let contentDigest: String
    package let suppliedSourcePixelExtent: PortraitSourceCropExtent?
    package var revision = PortraitSourcePreparation.revision

    package init(data: Data, sourcePixelExtent: PortraitSourceCropExtent?) {
      contentDigest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      suppliedSourcePixelExtent = sourcePixelExtent
    }
  }

  package struct PersonMask: @unchecked Sendable {
    package let image: CGImage?
    package let status: PortraitPersonMaskStatus
    package let requestRevision: Int
    package let unavailableReason: String?

    package init(
      image: CGImage? = nil,
      status: PortraitPersonMaskStatus,
      requestRevision: Int,
      unavailableReason: String? = nil
    ) {
      self.image = image
      self.status = status
      self.requestRevision = requestRevision
      self.unavailableReason = unavailableReason
    }
  }

  /// Compact luminance levels are reused when resampling every framing. Crop
  /// coordinates stay on the decoded source; they are never rounded to a level.
  package struct Level: Sendable {
    package let width: Int
    package let height: Int
    package let luminance: [UInt8]

    package init(width: Int, height: Int, luminance: [UInt8]) {
      self.width = width
      self.height = height
      self.luminance = luminance
    }
  }

  private struct SampleSpan {
    let first: Int
    let offset: Int
    let count: Int
  }

  /// Pixel overlap is separable: each column's weights are the same on every
  /// row. Retain the exact scalar weights and summation order, including zeros.
  private static func sampleSpans(origin: Double, extent: Double, scale: Double,
    samples: Int, limit: Int) -> (spans: [SampleSpan], weights: [Double]) {
    var spans: [SampleSpan] = [], weights: [Double] = []
    spans.reserveCapacity(samples)
    for index in 0..<samples {
      let start = (origin + Double(index) * extent / Double(samples)) * scale
      let end = min(Double(limit), (origin + Double(index + 1) * extent / Double(samples)) * scale)
      let first = max(0, min(limit - 1, Int(floor(start))))
      let last = max(first, min(limit - 1, Int(ceil(end)) - 1))
      spans.append(.init(first: first, offset: weights.count, count: last - first + 1))
      for pixel in first...last {
        weights.append(max(0, min(end, Double(pixel + 1)) - max(start, Double(pixel))))
      }
    }
    return (spans, weights)
  }

  package let key: Key
  package let image: CGImage
  package let sourcePixelExtent: PortraitSourceCropExtent
  package let faceAnalysis: PortraitFaceAnalysis
  package let personMask: PersonMask
  package let levels: [Level]
  /// Inclusive source preparation phases from the one cold preparation.
  package let phaseTimings: PortraitSourcePhaseTimings

  /// Retained pixel/array payload, rather than a source-count approximation.
  /// Images count their row strides, including padding. Shared image storage may
  /// be counted twice, which makes eviction conservative rather than optimistic.
  package var retainedByteCount: Int {
    var bytes = image.bytesPerRow * image.height
    if let mask = personMask.image { bytes += mask.bytesPerRow * mask.height }
    for level in levels { bytes += level.luminance.count * MemoryLayout<UInt8>.stride }
    for region in faceAnalysis.regions {
      bytes += region.points.count * MemoryLayout<PortraitLandmarkPoint>.stride
      bytes += (region.precisionEstimates?.count ?? 0) * MemoryLayout<Double>.stride
    }
    bytes += key.contentDigest.utf8.count + faceAnalysis.platformVersion.utf8.count
    bytes += faceAnalysis.unavailableReason?.utf8.count ?? 0
    bytes += personMask.unavailableReason?.utf8.count ?? 0
    return bytes
  }

  package func sample(crop: CGRect, width: Int, height: Int) throws
    -> (values: [Double], levelWidth: Int, levelHeight: Int) {
    try Task.checkCancellation()
    guard width > 0, height > 0, crop.width > 0, crop.height > 0,
      crop.minX >= 0, crop.minY >= 0, crop.maxX <= Double(image.width),
      crop.maxY <= Double(image.height), !levels.isEmpty
    else { throw PortraitDrawingError.unreadableImage }
    // Choose a level with at least one evidence pixel per output sample.
    // Integrating the complete footprint supplies the low-pass filter needed
    // for reduction; point/bilinear sampling alone would alias fine texture.
    let level = levels.last(where: {
      crop.width * Double($0.width) / Double(image.width) >= Double(width)
        && crop.height * Double($0.height) / Double(image.height) >= Double(height)
    }) ?? levels[0]
    let sx = Double(level.width) / Double(image.width)
    let sy = Double(level.height) / Double(image.height)
    var values = [Double](repeating: 0, count: width * height)
    let columns = Self.sampleSpans(origin: crop.minX, extent: crop.width, scale: sx,
      samples: width, limit: level.width)
    let rows = Self.sampleSpans(origin: crop.minY, extent: crop.height, scale: sy,
      samples: height, limit: level.height)
    // Span construction bounds every address to the selected level. No pointer
    // escapes these scopes; cancellation still settles at each 16-row boundary.
    try level.luminance.withUnsafeBufferPointer { source in
      try values.withUnsafeMutableBufferPointer { target in
        try columns.spans.withUnsafeBufferPointer { columnSpans in
          try rows.spans.withUnsafeBufferPointer { rowSpans in
            try columns.weights.withUnsafeBufferPointer { columnWeights in
              try rows.weights.withUnsafeBufferPointer { rowWeights in
                let input = source.baseAddress!, output = target.baseAddress!
                let xs = columnSpans.baseAddress!, ys = rowSpans.baseAddress!
                let dxs = columnWeights.baseAddress!, dys = rowWeights.baseAddress!
                var y = 0
                while y < height {
                  if y.isMultiple(of: 16) { try Task.checkCancellation() }
                  let row = ys[y]
                  var x = 0
                  while x < width {
                    let column = xs[x]
                    var total = 0.0, area = 0.0, ry = 0
                    while ry < row.count {
                      let dy = dys[row.offset + ry]
                      let base = (row.first + ry) * level.width + column.first
                      var cx = 0
                      while cx < column.count {
                        let weight = dxs[column.offset + cx] * dy
                        total += Double(input[base + cx]) * weight
                        area += weight
                        cx += 1
                      }
                      ry += 1
                    }
                    guard area > 0 else { throw PortraitDrawingError.unreadableImage }
                    output[y * width + x] = min(1, max(0, total / (area * 255)))
                    x += 1
                  }
                  y += 1
                }
              }
            }
          }
        }
      }
    }
    return (values, level.width, level.height)
  }

  package init(
    key: Key,
    image: CGImage,
    sourcePixelExtent: PortraitSourceCropExtent,
    faceAnalysis: PortraitFaceAnalysis,
    personMask: PersonMask,
    levels: [Level], phaseTimings: PortraitSourcePhaseTimings = .init()
  ) {
    self.key = key
    self.image = image
    self.sourcePixelExtent = sourcePixelExtent
    self.faceAnalysis = faceAnalysis
    self.personMask = personMask
    self.levels = levels
    self.phaseTimings = phaseTimings
  }
}

package struct PortraitSourcePhaseTimings: Sendable {
  package var decodeMS = 0.0
  package var faceVisionMS = 0.0
  package var personVisionMS = 0.0
  package var pyramidMS = 0.0
  package var digestMS = 0.0
  package init() {}
}

package struct PortraitRenderTimings: Sendable {
  package var sourceCacheHit = false
  package var rasterCacheHit = false
  package var sourceMS = 0.0
  package var cropMS = 0.0
  package var flowMS = 0.0
  package var vectorMS = 0.0

  package init(
    sourceCacheHit: Bool = false,
    rasterCacheHit: Bool = false,
    sourceMS: Double = 0.0,
    cropMS: Double = 0.0,
    flowMS: Double = 0.0,
    vectorMS: Double = 0.0
  ) {
    self.sourceCacheHit = sourceCacheHit
    self.rasterCacheHit = rasterCacheHit
    self.sourceMS = sourceMS
    self.cropMS = cropMS
    self.flowMS = flowMS
    self.vectorMS = vectorMS
  }
}

extension PortraitImageAnalyzer {
  /// Dependencies are injectable for deterministic reuse/cancellation tests;
  /// production uses one full-frame Vision request for each analysis kind.
  package static func prepareSource(data: Data, sourcePixelExtent: PortraitSourceCropExtent? = nil,
    faceAnalyzer: (CGImage) throws -> PortraitFaceAnalysis = PortraitFaceLandmarkAnalyzer.analyze,
    personMaskAnalyzer: (CGImage) throws -> PortraitSourcePreparation.PersonMask = preparePersonMask
  ) throws -> PortraitSourcePreparation {
    try Task.checkCancellation()
    let clock = ContinuousClock()
    func ms(_ duration: Duration) -> Double {
      Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }
    var timings = PortraitSourcePhaseTimings(), began = clock.now
    let decoded = try decodedImage(from: data)
    timings.decodeMS = ms(began.duration(to: clock.now))
    let image = decoded.image
    began = clock.now
    let face = try faceAnalyzer(image)
    timings.faceVisionMS = ms(began.duration(to: clock.now))
    try Task.checkCancellation()
    began = clock.now
    let mask = try personMaskAnalyzer(image)
    timings.personVisionMS = ms(began.duration(to: clock.now))
    try Task.checkCancellation()
    began = clock.now
    var levels: [PortraitSourcePreparation.Level] = []
    let maximum = max(image.width, image.height)
    var dimension = maximum
    repeat {
      let scale = Double(dimension) / Double(maximum)
      let width = max(1, Int((Double(image.width) * scale).rounded()))
      let height = max(1, Int((Double(image.height) * scale).rounded()))
      let luminance = try grayscaleBytes(image, width: width, height: height)
      levels.append(.init(width: width, height: height, luminance: luminance))
      dimension /= 2
    } while dimension >= 150
    try Task.checkCancellation()
    timings.pyramidMS = ms(began.duration(to: clock.now))
    began = clock.now
    let key = PortraitSourcePreparation.Key(data: data, sourcePixelExtent: sourcePixelExtent)
    timings.digestMS = ms(began.duration(to: clock.now))
    return PortraitSourcePreparation(key: key,
      image: image, sourcePixelExtent: sourcePixelExtent ?? decoded.sourcePixelExtent,
      faceAnalysis: face, personMask: mask, levels: levels, phaseTimings: timings)
  }

  package static func preparePersonMask(_ image: CGImage) throws -> PortraitSourcePreparation.PersonMask {
    try Task.checkCancellation()
    let request = VNGeneratePersonSegmentationRequest()
    request.qualityLevel = .accurate
    request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    do {
      try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
      try Task.checkCancellation()
      guard let buffer = request.results?.first?.pixelBuffer else {
        return .init(image: nil, status: .noPerson, requestRevision: request.revision,
          unavailableReason: "Vision returned no person mask")
      }
      return .init(image: try maskImage(buffer), status: .applied,
        requestRevision: request.revision, unavailableReason: nil)
    } catch is CancellationError { throw CancellationError() }
    catch {
      return .init(image: nil, status: .unavailable, requestRevision: request.revision,
        unavailableReason: error.localizedDescription)
    }
  }
}

// MARK: - Native Flow drawing production

/// Serial, bounded preparation owned by the concrete native producer. Callers
/// may request analysis but cannot install rasters or validation capabilities.
/// The only cached raster originates in analyze(), whose validation postcondition
/// is sealed here; recipe/pen-sensitive rendering and admission still run fully.
package actor PortraitFlowPreparationCache {
  private struct Key: Equatable {
    let source: PortraitSourcePreparation.Key
    let options: PortraitAnalysisOptions
    let photo: PhotoRef?
    let maximumDimension: Int
    let analysisRevision = "portrait-analysis-v2"
  }
  package struct Statistics: Sendable {
    package let sourceBytes: Int
    package let workspaceBytes: Int
    package let rasterPixelBytes: Int
    package let inputBytes: Int
  }
  private let sourceByteLimit: Int
  private let workspaceByteLimit: Int
  private var source: PortraitSourcePreparation?
  private var key: Key?
  private var raster: PortraitRaster?
  private var rasterSHA256: String?
  private struct InputBinding {
    let width: Double
    let height: Double
    let input: FrozenImageInputRecord
    var retainedByteCount: Int {
      input.assets.reduce(0) { $0 + $1.bytes.count } + input.photo.assets.reduce(0) { $0 + $1.bytes.count }
        + input.record.originalJSON.count + input.photo.record.originalJSON.count
    }
  }
  private var inputBinding: InputBinding?
  private var workspace: PortraitFlowRenderer.Workspace?

  package init(sourceByteLimit: Int = 48 * 1_024 * 1_024,
    workspaceByteLimit: Int = 64 * 1_024 * 1_024) {
    self.sourceByteLimit = max(0, sourceByteLimit)
    self.workspaceByteLimit = max(0, workspaceByteLimit)
  }

  package func statistics() -> Statistics {
    .init(sourceBytes: source?.retainedByteCount ?? 0,
      workspaceBytes: workspace?.retainedByteCount ?? 0,
      rasterPixelBytes: raster.map { ($0.luminance.count + ($0.personMask?.alpha?.count ?? 0)) * 8 } ?? 0,
      inputBytes: inputBinding?.retainedByteCount ?? 0)
  }

  private func prepare(data: Data, extent: PortraitSourceCropExtent?, options: PortraitAnalysisOptions,
    photo: PhotoRef? = nil)
    throws -> (PortraitSourcePreparation, PortraitRaster, Key, PortraitRenderTimings, String) {
    try Task.checkCancellation()
    let clock = ContinuousClock(), began = clock.now
    let sourceKey = PortraitSourcePreparation.Key(data: data, sourcePixelExtent: extent)
    var timings = PortraitRenderTimings()
    let prepared: PortraitSourcePreparation
    if let source, source.key == sourceKey {
      prepared = source; timings.sourceCacheHit = true
    } else {
      prepared = try PortraitImageAnalyzer.prepareSource(data: data, sourcePixelExtent: extent)
      try Task.checkCancellation()
      source = prepared.retainedByteCount <= sourceByteLimit ? prepared : nil
    }
    timings.sourceMS = Self.ms(began.duration(to: clock.now))
    let nextKey = Key(source: sourceKey, options: options, photo: photo, maximumDimension: 320)
    let analyzed: PortraitRaster
    if key == nextKey, let raster {
      analyzed = raster; timings.rasterCacheHit = true
    } else {
      let started = clock.now
      analyzed = try PortraitImageAnalyzer.analyze(preparedSource: prepared, options: options, maximumDimension: 320)
      timings.cropMS = Self.ms(started.duration(to: clock.now))
      try Task.checkCancellation()
      // Encode only this owning analyzer's immutable output, never an externally
      // supplied raster/digest. Claims may reuse this exact bound serialization.
      let digest = PortraitCandidateCoding.digest(try PortraitCandidateCoding.encoder().encode(analyzed))
      try Task.checkCancellation()
      key = nextKey; raster = analyzed; rasterSHA256 = digest
      workspace = nil; inputBinding = nil
    }
    return (prepared, analyzed, nextKey, timings, rasterSHA256!)
  }

  package func analyzedRaster(data: Data, options: PortraitAnalysisOptions,
    sourcePixelExtent: PortraitSourceCropExtent? = nil, photoReference: PhotoRef? = nil) throws -> PortraitRaster {
    try prepare(data: data, extent: sourcePixelExtent, options: options, photo: photoReference).1
  }

  fileprivate func render(input: PortraitFlowDrawingProducer.Input,
    settings: PortraitFlowDrawingProducer.Settings) async throws -> (PortraitRenderResult, String) {
    let (prepared, analyzed, requestKey, preparationTimings, rasterDigest) = try prepare(data: input.data,
      extent: input.sourcePixelExtent, options: settings.analysisOptions, photo: input.photo?.reference)
    // This cachedRaster is private producer-owned analysis, not caller-supplied
    // evidence. Await may reenter the actor: only the matching key may publish.
    var result = try await PortraitImageAnalyzer().render(.init(data: input.data,
      pose: .front, style: .flowEdges, options: settings.analysisOptions, cachedRaster: analyzed,
      strokeStyle: settings.strokeStyle, vectorOptions: settings.vectorOptions,
      sourcePixelExtent: input.sourcePixelExtent, flowWorkspace: workspace, preparedSource: prepared))
    try Task.checkCancellation()
    if key == requestKey, let completed = result.flowWorkspace {
      workspace = completed.retainedByteCount <= workspaceByteLimit ? completed : nil
    }
    result.timings?.sourceCacheHit = preparationTimings.sourceCacheHit
    result.timings?.rasterCacheHit = preparationTimings.rasterCacheHit
    result.timings?.sourceMS = preparationTimings.sourceMS
    result.timings?.cropMS = preparationTimings.cropMS
    return (result, rasterDigest)
  }

  /// ImageInput is a derivation of this Photo and analysis into one field, not
  /// a Drawing occurrence. It may truthfully be shared by multiple fresh Drawings.
  fileprivate func imageInput(result: PortraitRenderResult, input: PortraitFlowDrawingProducer.Input,
    settings: PortraitFlowDrawingProducer.Settings) throws -> FrozenImageInputRecord? {
    try Task.checkCancellation()
    guard let photo = input.photo else { return nil }
    let requestKey = Key(source: .init(data: input.data, sourcePixelExtent: input.sourcePixelExtent),
      options: settings.analysisOptions, photo: photo.reference, maximumDimension: 320)
    let matches = key == requestKey && raster == result.raster
    if matches, let binding = inputBinding,
      binding.width == result.program.fieldExtent.width, binding.height == result.program.fieldExtent.height {
      return binding.input
    }
    let frozen = try PortraitDrawingImages.input(result: result, data: input.data, photo: photo,
      identity: .init(issuer: photo.reference.issuer))
    try Task.checkCancellation()
    if matches, let frozen {
      let binding = InputBinding(width: result.program.fieldExtent.width, height: result.program.fieldExtent.height, input: frozen)
      // Conservatively count repeated/shared assets too. Oversize inputs remain
      // valid outputs but are rematerialized rather than retained indefinitely.
      inputBinding = binding.retainedByteCount <= 16 * 1_024 * 1_024 ? binding : nil
    }
    return frozen
  }

  private static func ms(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
  }
}

/// Transient rendering and authored admission share the same materialized
/// program. This producer has no retention or filesystem-writing capability.
package struct PortraitFlowDrawingProducer: DrawingProducing {
  package struct Input: Sendable {
    package let data: Data
    package let sourcePixelExtent: PortraitSourceCropExtent?
    package let preparedSource: PortraitSourcePreparation?
    package let input: SourceLink<ImageInputRef>
    package let parent: SourceLink<DrawingRef>
    package let photo: FrozenPhotoRecord?

    package init(data: Data, sourcePixelExtent: PortraitSourceCropExtent? = nil,
      preparedSource: PortraitSourcePreparation? = nil,
      input: SourceLink<ImageInputRef> = .unavailable(reason: "Transient Flow input has not been retained", knownRef: nil),
      parent: SourceLink<DrawingRef> = .none, photo: FrozenPhotoRecord? = nil) {
      self.data = data; self.sourcePixelExtent = sourcePixelExtent
      self.preparedSource = preparedSource; self.input = input; self.parent = parent; self.photo = photo
    }
  }

  package struct Settings: Codable, Equatable, Sendable {
    package let recipe: FlowArtistRecipe
    package let analysisOptions: PortraitAnalysisOptions
    package let strokeStyle: StrokeStyle
    package let nominalPenWidthMM: Double?
    package let materialContext: PortraitMaterialContext?
    package var vectorOptions: PortraitVectorOptions {
      var value = recipe.vectorOptions; value.materialContext = materialContext; return value
    }

    package init(recipe: FlowArtistRecipe, analysisOptions: PortraitAnalysisOptions,
      strokeStyle: StrokeStyle, nominalPenWidthMM: Double? = nil, materialContext: PortraitMaterialContext? = nil) {
      self.recipe = recipe; self.analysisOptions = analysisOptions
      self.strokeStyle = strokeStyle; self.nominalPenWidthMM = nominalPenWidthMM; self.materialContext = materialContext
    }
  }

  /// External artifact admission explicitly does not assert a fresh render.
  package enum Origin: String, Codable, Sendable {
    case providedArtifacts, reusedArtifacts
  }

  /// A validator's caller supplies the expected frozen origin. Recognizing a
  /// rendered receipt verifies artifact binding, not renderer authentication or
  /// deterministic reproduction. Only produce invokes the live renderer.
  package enum ReceiptOrigin: String, Sendable {
    case rendered, providedArtifacts, reusedArtifacts
  }

  package init() {}

  package func produce(input: Input, settings: Settings) async throws -> DrawingProduction<PortraitRenderResult> {
    try await produce(input: input, settings: settings, preparationCache: nil)
  }

  package func produce(input: Input, settings: Settings,
    preparationCache: PortraitFlowPreparationCache?) async throws -> DrawingProduction<PortraitRenderResult> {
    let (rendered, initialClaim) = try await PortraitFlowProducerClaim.renderAndClaim(input: input, settings: settings, preparationCache: preparationCache)
    var result = rendered
    let boundInput: Input
    let claim: PortraitFlowProducerClaim
    let frozen: FrozenImageInputRecord?
    if let preparationCache {
      frozen = try await preparationCache.imageInput(result: rendered, input: input, settings: settings)
    } else if let photo = input.photo {
      frozen = try PortraitDrawingImages.input(result: rendered, data: input.data, photo: photo,
        identity: .init(issuer: photo.reference.issuer))
    } else { frozen = nil }
    if let photo = input.photo, let frozen {
      result.drawingInput = frozen
      boundInput = Input(data: input.data, sourcePixelExtent: input.sourcePixelExtent, preparedSource: input.preparedSource,
        input: .present(frozen.reference), parent: input.parent, photo: photo)
      // Only the ImageInput link changed. The concrete render's raster/program,
      // source/settings and validated proof remain the identical values.
      claim = initialClaim.bindingImageInput(frozen.reference)
    } else { boundInput = input; claim = initialClaim }
    // Prepared render failures from rendering pass through unchanged. If later
    // admission fails, the same valid preparation remains reusable by the worker.
    do {
      return try Self.admitBound(result: result, input: boundInput, settings: settings, claim: claim)
    } catch is CancellationError { throw CancellationError() }
    catch {
      guard let preparedSource = result.preparedSource else { throw error }
      throw PortraitPreparedRenderFailure(underlyingError: error,
        preparedSource: preparedSource, timings: result.timings ?? .init())
    }
  }

  package static func admit(result: PortraitRenderResult, input: Input, settings: Settings,
    origin: Origin) throws -> DrawingProduction<PortraitRenderResult> {
    if let photo = input.photo, let frozen = try PortraitDrawingImages.input(result: result, data: input.data, photo: photo,
      identity: .init(issuer: photo.reference.issuer)) {
      var bound = result; bound.drawingInput = frozen
      let prepared = Input(data: input.data, sourcePixelExtent: input.sourcePixelExtent, preparedSource: input.preparedSource,
        input: .present(frozen.reference), parent: input.parent, photo: photo)
      return try admitBound(result: bound, input: prepared, settings: settings, origin: origin.rawValue)
    }
    return try admitBound(result: result, input: input, settings: settings, origin: origin.rawValue)
  }

  /// Reusable semantic validator for this exact supplied artifact set.
  /// The expected origin is explicit; frozen bytes cannot upgrade a reuse to a
  /// fresh-render assertion. Core owns unknown producer handling.
  package static func validator(result: PortraitRenderResult, input: Input,
    settings: Settings, origin: Origin) throws -> DrawingProducerValidator {
    try validator(result: result, input: input, settings: settings,
      expectedOrigin: origin == .providedArtifacts ? .providedArtifacts : .reusedArtifacts)
  }

  package static func validator(result: PortraitRenderResult, input: Input,
    settings: Settings, expectedOrigin: ReceiptOrigin) throws -> DrawingProducerValidator {
    let claim = try PortraitFlowProducerClaim(result: result, input: input,
      settings: settings, origin: expectedOrigin.rawValue)
    return boundValidator(claim: claim, program: result.program)
  }

  private static func boundValidator(claim: PortraitFlowProducerClaim,
    program expectedProgram: DrawingProgram) -> DrawingProducerValidator {
    { receipt, context in
      guard receipt.id == PortraitFlowProducerClaim.producerID,
        receipt.version == PortraitFlowProducerClaim.version,
        receipt.record == .hash(receipt.originalJSON),
        context.program.contentHash == expectedProgram.contentHash,
        context.input == claim.input, context.parent == claim.parent,
        context.units.nominalPenWidthMM == claim.settings.nominalPenWidthMM,
        context.units.intendedPhysicalFieldMM == nil,
        context.units.historical == nil, context.units.historicalReceipt == nil else {
        throw DrawingExchangeError.invalidProducer(receipt.id)
      }
      let frozen: PortraitFlowProducerClaim
      do { frozen = try JSONDecoder().decode(PortraitFlowProducerClaim.self, from: receipt.originalJSON) }
      catch { throw DrawingExchangeError.invalidProducer(receipt.id) }
      guard frozen == claim else { throw DrawingExchangeError.invalidProducer(receipt.id) }
    }
  }

  private static func admitBound(result: PortraitRenderResult, input: Input, settings: Settings,
    origin: String) throws -> DrawingProduction<PortraitRenderResult> {
    let claim = try PortraitFlowProducerClaim(result: result, input: input, settings: settings, origin: origin)
    return try admitBound(result: result, input: input, settings: settings, claim: claim)
  }

  private static func admitBound(result: PortraitRenderResult, input: Input, settings: Settings,
    claim: PortraitFlowProducerClaim) throws -> DrawingProduction<PortraitRenderResult> {
    let receipt = try DrawingProducerReceipt(id: PortraitFlowProducerClaim.producerID,
      version: PortraitFlowProducerClaim.version,
      recordJSON: PortraitCandidateCoding.encoder().encode(claim))
    let validator = boundValidator(claim: claim, program: result.program)
    let drawing = try DrawingAdmission.produced(program: result.program, input: input.input, parent: input.parent,
      producer: receipt, units: DrawingUnits(nominalPenWidthMM: settings.nominalPenWidthMM),
      validator: validator)
    return DrawingProduction(drawing: drawing, artifacts: result)
  }
}

/// Metadata only: image/raster bytes stay in the transient artifacts, not JSON.
/// Verification binds a supplied artifact set; it is not deterministic replay
/// or proof that arbitrary geometry was produced by a particular algorithm.
package struct PortraitFlowProducerClaim: Codable, Equatable, Sendable {
  package static let producerID = "adaptiveplotter.flow-native"
  package static let version = "2"
  package let schemaVersion: Int
  package let origin: String
  package let sourceSHA256: String
  package let sourcePixelExtent: PortraitSourceCropExtent?
  package let sourceWidth: Int
  package let sourceHeight: Int
  package let input: SourceLink<ImageInputRef>
  package let parent: SourceLink<DrawingRef>
  package let rasterSHA256: String
  package let rasterWidth: Int
  package let rasterHeight: Int
  package let settings: PortraitFlowDrawingProducer.Settings
  package let recipeRevision: String
  package let rendererRevision: String
  package let warpManifest: PortraitHeadWarpManifest?
  package let programHash: String

  /// External artifacts always pass the owning validator, regardless of origin.
  package init(result: PortraitRenderResult, input: PortraitFlowDrawingProducer.Input,
    settings: PortraitFlowDrawingProducer.Settings, origin: String) throws {
    try result.raster.validateAnalysisEvidence()
    try self.init(result: result, input: input, settings: settings, origin: origin,
      validation: .validated)
  }

  private enum ValidationPostcondition { case validated }

  /// Both paths own concrete analysis: fresh render takes analyze(), or the
  /// sealed cache supplies a raster that only its own analyze() can install.
  /// Neither path accepts arbitrary cached raster evidence from an Input.
  fileprivate static func renderAndClaim(input: PortraitFlowDrawingProducer.Input,
    settings: PortraitFlowDrawingProducer.Settings,
    preparationCache: PortraitFlowPreparationCache? = nil) async throws -> (PortraitRenderResult, Self) {
    let result: PortraitRenderResult
    let cachedRasterDigest: String?
    if let preparationCache {
      let rendered = try await preparationCache.render(input: input, settings: settings)
      result = rendered.0; cachedRasterDigest = rendered.1
    }
    else { cachedRasterDigest = nil; result = try await PortraitImageAnalyzer().render(.init(data: input.data,
      pose: .front, style: .flowEdges, options: settings.analysisOptions, cachedRaster: nil,
      strokeStyle: settings.strokeStyle, vectorOptions: settings.vectorOptions,
      sourcePixelExtent: input.sourcePixelExtent, preparedSource: input.preparedSource)) }
    do {
      let claim = try Self(result: result, input: input, settings: settings, origin: "rendered",
        validation: .validated, rasterDigest: cachedRasterDigest)
      return (result, claim)
    } catch is CancellationError { throw CancellationError() }
    catch {
      guard let preparedSource = result.preparedSource else { throw error }
      throw PortraitPreparedRenderFailure(underlyingError: error,
        preparedSource: preparedSource, timings: result.timings ?? .init())
    }
  }

  fileprivate func bindingImageInput(_ reference: ImageInputRef) -> Self {
    Self(copying: self, imageInput: reference)
  }

  private init(copying claim: Self, imageInput: ImageInputRef) {
    schemaVersion = claim.schemaVersion; origin = claim.origin
    sourceSHA256 = claim.sourceSHA256; sourcePixelExtent = claim.sourcePixelExtent
    sourceWidth = claim.sourceWidth; sourceHeight = claim.sourceHeight
    input = .present(imageInput); parent = claim.parent
    rasterSHA256 = claim.rasterSHA256; rasterWidth = claim.rasterWidth; rasterHeight = claim.rasterHeight
    settings = claim.settings; recipeRevision = claim.recipeRevision; rendererRevision = claim.rendererRevision
    warpManifest = claim.warpManifest; programHash = claim.programHash
  }

  private init(result: PortraitRenderResult, input: PortraitFlowDrawingProducer.Input,
    settings: PortraitFlowDrawingProducer.Settings, origin: String,
    validation: ValidationPostcondition, rasterDigest: String? = nil) throws {
    guard !input.data.isEmpty, ["rendered", "providedArtifacts", "reusedArtifacts"].contains(origin),
      settings.nominalPenWidthMM.map({ $0.isFinite && $0 > 0 }) ?? true else {
      throw DrawingExchangeError.invalidProducer(Self.producerID)
    }
    if case .none = input.input { throw DrawingExchangeError.invalidProducer("Flow requires an image input declaration") }
    let encoder = PortraitCandidateCoding.encoder()
    // Read encoded source dimensions without materializing a second image or
    // rerunning source analysis. Orientation is separately in raster geometry.
    guard let image = CGImageSourceCreateWithData(input.data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
      let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
      width.intValue > 0, height.intValue > 0 else {
      throw DrawingExchangeError.invalidProducer("Unreadable Flow source dimensions")
    }
    schemaVersion = 2; self.origin = origin
    sourceSHA256 = PortraitCandidateCoding.digest(input.data)
    sourcePixelExtent = input.sourcePixelExtent; sourceWidth = width.intValue; sourceHeight = height.intValue
    self.input = input.input; parent = input.parent
    if let rasterDigest { rasterSHA256 = rasterDigest }
    else { rasterSHA256 = PortraitCandidateCoding.digest(try encoder.encode(result.raster)) }
    rasterWidth = result.raster.width; rasterHeight = result.raster.height
    self.settings = settings; recipeRevision = FlowArtistRecipe.revision
    rendererRevision = PortraitFlowRenderer.revision(for: settings.vectorOptions)
    warpManifest = result.warpManifest; programHash = result.program.contentHash.description
    if origin == "rendered" {
      var options = settings.vectorOptions.resolved(rasterHeight: result.raster.height)
      options.tonalStrength = max(PortraitStyle.flowEdges.tonalStrengthRange.lowerBound, options.tonalStrength)
      if let material = options.materialContext { options = try material.adapting(options, raster: result.raster) }
      let expected = "portrait-v3|metric=\(result.raster.metricProvenance)|\(result.raster.provenance)|pose=\(PortraitPose.front.rawValue)|style=\(PortraitStyle.flowEdges.rawValue)|\(options.provenance)|flow=\(rendererRevision)"
      guard result.program.source.kind == "portrait",
        result.program.source.sourceIdentifier == expected || result.program.source.sourceIdentifier.hasPrefix(expected + "|"),
        result.program.strokes.allSatisfy({ $0.style == settings.strokeStyle }),
        result.warpManifest == nil else { throw DrawingExchangeError.invalidProducer(Self.producerID) }
    }
  }
}
