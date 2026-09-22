import Foundation

/// Image-evidence curves plus separated, tensor-guided tonal streamlines.
/// All geometry is in analysis pixels. Tone never modifies the structural image;
/// coherence smooths the orientation field, not the facial features underneath it.
/// This is a deterministic 2D renderer, not inferred facial anatomy or depth.
enum PortraitFlowRenderer {
  static let revision = "flow-edge-v1"

  struct Layers: Sendable {
    let structure: [[CGPoint]]
    let tone: [[CGPoint]]
    let minimumSpacing: Double
  }

  struct Diagnostics: Sendable {
    var sourceBuilds = 0
    var structureBuilds = 0
    var rawStructureBuilds = 0
    var orientationBuilds = 0
    var supportBuilds = 0
    var supportLevelBuilds = 0
    var sourceMS = 0.0
    var structureMS = 0.0
    var rawStructureMS = 0.0
    var orientationMS = 0.0
    var tracingMS = 0.0
    var supportMS = 0.0
    var sourceCacheHit = false
    var structureCacheHit = false
    var rawStructureCacheHit = false
    var orientationCacheHit = false
    var supportCacheHit = false
  }

  /// Value-owned, source-specific preparation. The Studio owns at most two
  /// workspaces. Each retains at most two raw-curve, structural and orientation variants;
  /// neither an analyzer instance nor a process-global cache owns this memory.
  struct Workspace: Sendable {
    fileprivate var source: Source?
    fileprivate var structures: [(StructureKey, [[CGPoint]])] = []
    fileprivate var rawStructures: [(RawStructureKey, [[CGPoint]])] = []
    fileprivate var orientations: [(Int, Orientation)] = []
    fileprivate var support: SupportPyramid?
    fileprivate(set) var diagnostics = Diagnostics()
    init() {}
    var structureVariantCount: Int { structures.count }
    var rawStructureVariantCount: Int { rawStructures.count }
    var orientationVariantCount: Int { orientations.count }
    var supportLevelCount: Int { support?.levels.compactMap { $0 }.count ?? 0 }
  }

  fileprivate struct Source: Sendable {
    let luminance: [Double]
    let provenance: String
    let field: Evidence
    func matches(_ raster: PortraitRaster) -> Bool {
      field.width == raster.width && field.height == raster.height
        && provenance == raster.provenance && luminance == raster.luminance
    }
  }

  fileprivate struct StructureKey: Equatable, Sendable {
    let threshold: Double
    let minimumLength: Double
    let simplification: Double
    let spacing: Double
    let supportAmount: Double
    let supportScale: Double
  }

  fileprivate struct RawStructureKey: Equatable, Sendable {
    let threshold: Double
    let minimumLength: Double
    let simplification: Double
  }

  fileprivate struct Orientation: Sendable {
    let cos2: [Double]
    let sin2: [Double]
  }

  /// Three fixed source-image scales, independent of tone, path coherence and
  /// the support slider. Float maps cap retained storage at nine scalar arrays
  /// per source (about 3.6 MiB at 320 squared). Only levels required by the
  /// selected scale are built; disabled support builds none.
  fileprivate struct SupportPyramid: Sendable {
    struct Level: Sendable {
      let confidence: [Float]
      let cos2: [Float]
      let sin2: [Float]
    }
    var levels: [Level?] = .init(repeating: nil, count: 3)
  }

  private struct SupportSample {
    let confidence: Double
    let cos2: Double
    let sin2: Double
  }

  private struct SupportBilinear {
    let topLeft: Int, topRight: Int, bottomLeft: Int, bottomRight: Int
    let fx: Double, fy: Double

    init(_ point: CGPoint, width: Int, height: Int) {
      let px = min(Double(width - 1), max(0, point.x)), py = min(Double(height - 1), max(0, point.y))
      let x = Int(px), y = Int(py), x1 = min(width - 1, x + 1), y1 = min(height - 1, y + 1)
      topLeft = y * width + x; topRight = y * width + x1
      bottomLeft = y1 * width + x; bottomRight = y1 * width + x1
      fx = px - Double(x); fy = py - Double(y)
    }

    func read(_ values: [Float]) -> Double {
      (Double(values[topLeft]) * (1 - fx) + Double(values[topRight]) * fx) * (1 - fy)
        + (Double(values[bottomLeft]) * (1 - fx) + Double(values[bottomRight]) * fx) * fy
    }
  }

  static func paths(from raster: PortraitRaster, options: PortraitVectorOptions) throws -> [[CGPoint]] {
    let result = try layers(from: raster, options: options)
    return result.structure + result.tone
  }

  static func layers(from raster: PortraitRaster, options: PortraitVectorOptions) throws -> Layers {
    var workspace = Workspace()
    return try layers(from: raster, options: options, workspace: &workspace)
  }

  static func layers(from raster: PortraitRaster, options: PortraitVectorOptions,
    workspace: inout Workspace) throws -> Layers {
    try Task.checkCancellation()
    let clock = ContinuousClock()
    var started = clock.now
    let width = raster.width, height = raster.height
    guard width >= 3, height >= 3, width <= 512, height <= 512,
      raster.luminance.count == width * height,
      raster.luminance.allSatisfy(\.isFinite) else { throw PortraitDrawingError.unreadableImage }
    var diagnostics = workspace.diagnostics
    diagnostics.sourceCacheHit = workspace.source?.matches(raster) == true
    if !diagnostics.sourceCacheHit {
      // Fixed noise bandwidth; tone/coherence cannot blur away a facial mark.
      let values = raster.luminance.map { min(1, max(0, $0)) }
      let image = try blur(values, width: width, height: height, sigma: 0.65)
      let field = try Evidence(image: image, width: width, height: height)
      workspace.source = Source(luminance: raster.luminance, provenance: raster.provenance, field: field)
      workspace.structures = []; workspace.rawStructures = []; workspace.orientations = []
      workspace.support = nil
      diagnostics.sourceBuilds += 1
    }
    let field = workspace.source!.field
    diagnostics.sourceMS = milliseconds(started.duration(to: clock.now))
    let bounded = options.bounded
    let toneSupport = bounded.flowSupport ?? 0
    let structureSupport = bounded.flowStructureSupport ?? 0
    let supportScale = bounded.flowSupportScale ?? 0
    diagnostics.supportMS = 0; diagnostics.supportCacheHit = false
    if toneSupport > 0 || structureSupport > 0 {
      started = clock.now
      let position = min(2, max(0, supportScale * 2))
      let lower = Int(position), upper = min(2, lower + 1)
      let required = position > Double(lower) ? [lower, upper] : [lower]
      if workspace.support == nil {
        workspace.support = SupportPyramid()
        diagnostics.supportBuilds += 1
      }
      diagnostics.supportCacheHit = required.allSatisfy { workspace.support!.levels[$0] != nil }
      for index in required where workspace.support!.levels[index] == nil {
        workspace.support!.levels[index] = try supportLevel(field, radius: [2, 4, 8][index])
        diagnostics.supportLevelBuilds += 1
      }
      diagnostics.supportMS = milliseconds(started.duration(to: clock.now))
    }
    let materialSpacing = try minimumSpacing(raster: raster, options: options)
    let key = StructureKey(threshold: max(0.001, options.sketchThreshold),
      minimumLength: options.minimumContourLength,
      simplification: min(0.3, max(0, options.simplificationTolerance)), spacing: materialSpacing,
      supportAmount: structureSupport, supportScale: structureSupport > 0 ? supportScale : 0)
    started = clock.now
    diagnostics.rawStructureMS = 0; diagnostics.rawStructureCacheHit = false
    let structure: [[CGPoint]]
    if let index = workspace.structures.firstIndex(where: { $0.0 == key }) {
      let entry = workspace.structures.remove(at: index)
      workspace.structures.append(entry); structure = entry.1
      diagnostics.structureCacheHit = true
    } else {
      let rawStarted = clock.now
      let rawKey = RawStructureKey(threshold: key.threshold, minimumLength: key.minimumLength,
        simplification: key.simplification)
      let extracted: [[CGPoint]]
      if let index = workspace.rawStructures.firstIndex(where: { $0.0 == rawKey }) {
        let entry = workspace.rawStructures.remove(at: index)
        workspace.rawStructures.append(entry); extracted = entry.1
        diagnostics.rawStructureCacheHit = true
      } else {
        extracted = try structuralCurves(field: field, options: options)
        workspace.rawStructures.append((rawKey, extracted))
        if workspace.rawStructures.count > 2 { workspace.rawStructures.removeFirst() }
        diagnostics.rawStructureBuilds += 1
      }
      diagnostics.rawStructureMS = milliseconds(rawStarted.duration(to: clock.now))
      let supported: [[CGPoint]]
      if structureSupport > 0, let support = workspace.support {
        supported = try supportedStructure(extracted, field: field, support: support,
          scale: supportScale, amount: structureSupport)
      } else { supported = extracted }
      structure = try separatedStructure(supported, field: field,
        minimumLength: options.minimumContourLength, minimumSpacing: materialSpacing)
      workspace.structures.append((key, structure))
      if workspace.structures.count > 2 { workspace.structures.removeFirst() }
      diagnostics.structureCacheHit = false; diagnostics.structureBuilds += 1
    }
    diagnostics.structureMS = milliseconds(started.duration(to: clock.now))
    started = clock.now
    let radius = Int(ceil(1.5 + max(0, options.smoothing) * 1.5))
    let orientation: Orientation
    if let index = workspace.orientations.firstIndex(where: { $0.0 == radius }) {
      let entry = workspace.orientations.remove(at: index)
      workspace.orientations.append(entry); orientation = entry.1
      diagnostics.orientationCacheHit = true
    } else {
      orientation = try orientationField(field, radius: radius)
      workspace.orientations.append((radius, orientation))
      if workspace.orientations.count > 2 { workspace.orientations.removeFirst() }
      diagnostics.orientationCacheHit = false; diagnostics.orientationBuilds += 1
    }
    diagnostics.orientationMS = milliseconds(started.duration(to: clock.now))
    started = clock.now
    let tone = try tonalCurves(field: field, orientation: orientation, structure: structure,
      options: options, minimumSpacing: materialSpacing,
      support: toneSupport > 0 ? workspace.support : nil)
    diagnostics.tracingMS = milliseconds(started.duration(to: clock.now))
    workspace.diagnostics = diagnostics
    return Layers(structure: structure, tone: tone, minimumSpacing: materialSpacing)
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
  }

  /// Suppress nearby parallel copies and texture in evidence-priority order.
  /// Real crossings/junctions remain permissible; the renderer does not claim a
  /// positive clearance between anatomical curves that actually meet.
  private static func separatedStructure(_ curves: [[CGPoint]], field: Evidence,
    minimumLength: Double, minimumSpacing: Double) throws -> [[CGPoint]] {
    var ranked: [(index: Int, score: Double)] = []
    for (index, curve) in curves.enumerated() {
      var totalEvidence = 0.0
      for point in curve { totalEvidence += field.sample(field.magnitude, point) }
      let evidence = totalEvidence / Double(curve.count)
      ranked.append((index: index, score: evidence * sqrt(length(curve))))
    }
    ranked.sort { lhs, rhs in
      lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score > rhs.score
    }
    var occupied = Occupancy(width: field.width, height: field.height)
    var result: [[CGPoint]] = []
    for item in ranked {
      try Task.checkCancellation()
      // Sample the fitted curve at subpixel spacing so that a long simplified
      // segment cannot jump through a previously reserved parallel stroke.
      let curve = resampled(curves[item.index])
      let firstAccepted = result.count
      var run: [CGPoint] = []
      func finish() {
        if run.count > 1, length(run) >= minimumLength {
          result.append(run)
        }
        run = []
      }
      for i in curve.indices {
        let a = curve[max(0, i - 1)], b = curve[min(curve.count - 1, i + 1)]
        if occupied.intersects(curve[i], radius: minimumSpacing, parallelTo: unit(b - a)) { finish() }
        else { run.append(curve[i]) }
      }
      finish()
      // Commit only after checking the complete candidate: its adjacent samples
      // and the two sides of a closed-loop join must not reject one another.
      for accepted in result.dropFirst(firstAccepted) { occupied.insert(accepted, radius: minimumSpacing) }
    }
    return result
  }

  /// The tone knob must never undo a physical material spacing floor. Derive
  /// that floor independently of the already-adapted style spacing.
  static func minimumSpacing(raster: PortraitRaster, options: PortraitVectorOptions) throws -> Double {
    guard let material = options.materialContext else { return 1.75 }
    try material.profile.validate()
    let aspect = raster.sourceCropExtent?.aspectRatio
      ?? Double(raster.width - 1) / Double(raster.height - 1)
    let xSamples = Double(raster.sourceCropExtent == nil ? raster.width - 1 : raster.width)
    let ySamples = Double(raster.sourceCropExtent == nil ? raster.height - 1 : raster.height)
    let pitch = min(material.drawingHeightMM * aspect / xSamples, material.drawingHeightMM / ySamples)
    let result = material.profile.conservativeWidthMM / pitch * 1.5
    guard result.isFinite, result > 0 else { throw PortraitDrawingError.unreadableImage }
    return max(1.75, result)
  }

  fileprivate struct Evidence: Sendable {
    let width: Int
    let height: Int
    let image: [Double]
    let gx: [Double]
    let gy: [Double]
    let magnitude: [Double]

    init(image: [Double], width: Int, height: Int) throws {
      self.image = image; self.width = width; self.height = height
      var gx = image, gy = image, magnitude = image
      for y in 0..<height {
        try Task.checkCancellation()
        let up = max(0, y - 1), down = min(height - 1, y + 1)
        for x in 0..<width {
          let left = max(0, x - 1), right = min(width - 1, x + 1), i = y * width + x
          gx[i] = (image[up * width + right] + 2 * image[y * width + right] + image[down * width + right]
            - image[up * width + left] - 2 * image[y * width + left] - image[down * width + left]) / 8
          gy[i] = (image[down * width + left] + 2 * image[down * width + x] + image[down * width + right]
            - image[up * width + left] - 2 * image[up * width + x] - image[up * width + right]) / 8
          magnitude[i] = hypot(gx[i], gy[i])
        }
      }
      self.gx = gx; self.gy = gy; self.magnitude = magnitude
    }

    func sample(_ values: [Double], _ point: CGPoint) -> Double {
      PortraitFlowRenderer.sample(values, point, width: width, height: height)
    }
  }

  private static func structuralCurves(field: Evidence, options: PortraitVectorOptions) throws -> [[CGPoint]] {
    let width = field.width, height = field.height, count = width * height
    let low = max(0.001, options.sketchThreshold), high = low * 2
    var ridge = [Bool](repeating: false, count: count)
    var retained = ridge
    var locations = [CGPoint](repeating: .zero, count: count)
    var queue: [Int] = []
    // Nonmaximum suppression gives subpixel edge ridges; hysteresis retains weak
    // detail only when connected to stronger measured image evidence.
    for y in 1..<(height - 1) {
      try Task.checkCancellation()
      for x in 1..<(width - 1) {
        let i = y * width + x, value = field.magnitude[i]
        guard value >= low else { continue }
        let normal = CGPoint(x: field.gx[i] / value, y: field.gy[i] / value)
        let point = CGPoint(x: x, y: y)
        let before = field.sample(field.magnitude, point - normal)
        let after = field.sample(field.magnitude, point + normal)
        guard value >= before, value > after else { continue }
        let curvature = before - 2 * value + after
        let offset = curvature < -1e-9 ? min(0.5, max(-0.5, (before - after) / (2 * curvature))) : 0
        locations[i] = point + normal * offset
        ridge[i] = true
        if value >= high { retained[i] = true; queue.append(i) }
      }
    }
    var head = 0
    while head < queue.count {
      if head.isMultiple(of: 256) { try Task.checkCancellation() }
      let i = queue[head]; head += 1
      let x = i % width, y = i / width
      for dy in -1...1 {
        for dx in -1...1 where dx != 0 || dy != 0 {
          let nx = x + dx, ny = y + dy
          guard nx > 0, ny > 0, nx < width - 1, ny < height - 1 else { continue }
          let neighbor = ny * width + nx
          if ridge[neighbor], !retained[neighbor] { retained[neighbor] = true; queue.append(neighbor) }
        }
      }
    }
    // Eight neighbor/visited bits replace one small heap array per image pixel
    // and a hashed edge set. The bit order is the old y/x neighbor order, keeping
    // traversal, junction tie-breaking and generated geometry deterministic.
    let dxs = [-1, 0, 1, -1, 1, -1, 0, 1]
    let dys = [-1, -1, -1, 0, 0, 1, 1, 1]
    let offsets = [-width - 1, -width, -width + 1, -1, 1, width - 1, width, width + 1]
    var links = [UInt8](repeating: 0, count: count)
    var starts: [Int] = [], remaining: [Int] = []
    for i in 0..<count where retained[i] {
      if i.isMultiple(of: 256) { try Task.checkCancellation() }
      let x = i % width, y = i / width
      var mask: UInt8 = 0
      for bit in 0..<8 {
        let dx = dxs[bit], dy = dys[bit], nx = x + dx, ny = y + dy
        guard nx >= 0, ny >= 0, nx < width, ny < height, retained[ny * width + nx] else { continue }
        if dx != 0, dy != 0, retained[y * width + nx] || retained[ny * width + x] { continue }
        mask |= UInt8(1 << bit)
      }
      links[i] = mask
      if mask.nonzeroBitCount == 1 { starts.append(i) }
      else if mask != 0 { remaining.append(i) }
    }
    starts.append(contentsOf: remaining)
    var visited = [UInt8](repeating: 0, count: count)
    var localGeneration = [UInt32](repeating: 0, count: count), generation: UInt32 = 0
    var curves: [[CGPoint]] = []
    for start in starts {
      try Task.checkCancellation()
      for firstBit in 0..<8 where links[start] & UInt8(1 << firstBit) != 0
        && visited[start] & UInt8(1 << firstBit) == 0 {
        let first = start + offsets[firstBit]
        var previous = start, current = first, indices = [start]
        generation += 1; localGeneration[start] = generation
        visited[start] |= UInt8(1 << firstBit)
        visited[first] |= UInt8(1 << (7 - firstBit))
        while true {
          if indices.count.isMultiple(of: 128) { try Task.checkCancellation() }
          indices.append(current)
          guard localGeneration[current] != generation else { break }
          localGeneration[current] = generation
          let direction = unit(locations[current] - locations[previous])
          let available = links[current] & ~visited[current]
          var nextBit: Int?, best = -Double.infinity
          for bit in 0..<8 where available & UInt8(1 << bit) != 0 {
            let candidate = current + offsets[bit]
            let score = dot(direction, unit(locations[candidate] - locations[current]))
            if score > best { best = score; nextBit = bit }
          }
          guard let nextBit else { break }
          let next = current + offsets[nextBit]
          visited[current] |= UInt8(1 << nextBit)
          visited[next] |= UInt8(1 << (7 - nextBit))
          previous = current; current = next
        }
        let raw = indices.map { locations[$0] }
        guard length(raw) >= options.minimumContourLength else { continue }
        // Fair within a subpixel tube around the measured ridge. Endpoints and
        // closed-loop joins are retained. Coherence and tone cannot erase it.
        let curve = try fair(raw, tolerance: min(0.3, max(0, options.simplificationTolerance)))
        if curve.count >= 2, length(curve) > 0 { curves.append(curve) }
      }
    }
    return curves
  }

  private static func orientationField(_ field: Evidence, radius: Int) throws -> Orientation {
    let width = field.width, height = field.height
    // Structure tensors represent an unoriented line field without +/- vector
    // cancellation. Smoothing this field alters flow coherence, not edge evidence.
    let xx = try coherentField(field.gx.map { $0 * $0 }, width: width, height: height, radius: radius)
    let yy = try coherentField(field.gy.map { $0 * $0 }, width: width, height: height, radius: radius)
    let xy = try coherentField(zip(field.gx, field.gy).map { $0.0 * $0.1 }, width: width, height: height, radius: radius)
    return Orientation(cos2: zip(xx, yy).map { $0 - $1 }, sin2: xy.map { 2 * $0 })
  }

  private static func supportLevel(_ field: Evidence, radius: Int) throws -> SupportPyramid.Level {
    let width = field.width, height = field.height, count = width * height
    try Task.checkCancellation()
    // Blur only a separate evidence copy. Averaging squared fine gradients
    // alone would retain noise energy even when that texture cancels at scale.
    let image = try coherentField(field.image, width: width, height: height, radius: radius)
    let coarse = try Evidence(image: image, width: width, height: height)
    let tensorRadius = max(1, radius / 2)
    let xx = try coherentField(coarse.gx.map { $0 * $0 }, width: width, height: height, radius: tensorRadius)
    let yy = try coherentField(coarse.gy.map { $0 * $0 }, width: width, height: height, radius: tensorRadius)
    let xy = try coherentField(zip(coarse.gx, coarse.gy).map { $0.0 * $0.1 },
      width: width, height: height, radius: tensorRadius)
    var confidence = [Float](repeating: 0, count: count)
    var cos2 = confidence, sin2 = confidence
    for i in 0..<count {
      if i.isMultiple(of: 512) { try Task.checkCancellation() }
      let trace = max(0, xx[i] + yy[i])
      let a = xx[i] - yy[i], b = 2 * xy[i], anisotropy = hypot(a, b)
      guard trace > 1e-14, anisotropy > 1e-14 else { continue }
      // Scale-normalized contrast admits broad gentle shading. A perfectly
      // coherent but nearly constant patch must still fail absolute contrast.
      let contrast = Double(radius) * sqrt(trace)
      confidence[i] = Float(ramp(contrast, low: 0.002, high: 0.020)
        * ramp(anisotropy / trace, low: 0.08, high: 0.65))
      cos2[i] = Float(a / anisotropy); sin2[i] = Float(b / anisotropy)
    }
    return .init(confidence: confidence, cos2: cos2, sin2: sin2)
  }

  private static func supportSample(_ support: SupportPyramid, field: Evidence,
    point: CGPoint, scale: Double) -> SupportSample {
    let position = min(2, max(0, scale * 2))
    let lower = Int(position), upper = min(2, lower + 1), fraction = position - Double(lower)
    let sampling = SupportBilinear(point, width: field.width, height: field.height)
    func at(_ level: SupportPyramid.Level) -> SupportSample {
      SupportSample(confidence: sampling.read(level.confidence),
        cos2: sampling.read(level.cos2), sin2: sampling.read(level.sin2))
    }
    let a = at(support.levels[lower]!)
    guard fraction > 0 else { return a }
    let b = at(support.levels[upper]!)
    return SupportSample(confidence: a.confidence * (1 - fraction) + b.confidence * fraction,
      cos2: a.cos2 * (1 - fraction) + b.cos2 * fraction,
      sin2: a.sin2 * (1 - fraction) + b.sin2 * fraction)
  }

  private static func supportConfidence(_ support: SupportPyramid, field: Evidence,
    point: CGPoint, scale: Double) -> Double {
    let position = min(2, max(0, scale * 2))
    let lower = Int(position), upper = min(2, lower + 1), fraction = position - Double(lower)
    let sampling = SupportBilinear(point, width: field.width, height: field.height)
    let a = sampling.read(support.levels[lower]!.confidence)
    guard fraction > 0 else { return a }
    let b = sampling.read(support.levels[upper]!.confidence)
    return a * (1 - fraction) + b * fraction
  }

  private static func supportedStructure(_ curves: [[CGPoint]], field: Evidence,
    support: SupportPyramid, scale: Double, amount: Double) throws -> [[CGPoint]] {
    var result: [[CGPoint]] = []
    for curve in curves {
      try Task.checkCancellation()
      var quality = 0.0, totalLength = 0.0
      // Whole-curve evidence avoids turning every small dip into two short
      // fragments. Arc weighting stops one strong vertex from admitting a long
      // weak texture chain. The original detailed ridge geometry is retained.
      for index in curve.indices {
        if index.isMultiple(of: 128) { try Task.checkCancellation() }
        let point = curve[index]
        let value = supportSample(support, field: field, point: point, scale: scale)
        let gx = field.sample(field.gx, point), gy = field.sample(field.gy, point)
        let squared = gx * gx + gy * gy
        let normalAgreement: Double
        if squared > 1e-14 {
          let cos2 = (gx * gx - gy * gy) / squared, sin2 = 2 * gx * gy / squared
          normalAgreement = max(0, (1 + value.cos2 * cos2 + value.sin2 * sin2) * 0.5)
        } else { normalAgreement = 0 }
        // Strong narrow marks (eyelids, glasses, lips) can survive without
        // coarse persistence. This is measured contrast, not a semantic label.
        let fineFeature = ramp(sqrt(squared), low: 0.045, high: 0.10)
        let score = max(fineFeature, value.confidence * normalAgreement * normalAgreement)
        let previous = curve[max(0, index - 1)], next = curve[min(curve.count - 1, index + 1)]
        let weight = max(1e-9, hypot(next.x - previous.x, next.y - previous.y) * 0.5)
        quality += score * weight; totalLength += weight
      }
      if totalLength > 0, quality / totalLength >= amount * 0.65 { result.append(curve) }
    }
    return result
  }

  private static func ramp(_ value: Double, low: Double, high: Double) -> Double {
    let t = min(1, max(0, (value - low) / (high - low)))
    return t * t * (3 - 2 * t)
  }

  private static func tonalCurves(field: Evidence, orientation: Orientation, structure: [[CGPoint]],
    options: PortraitVectorOptions, minimumSpacing: Double, support: SupportPyramid?) throws -> [[CGPoint]] {
    let width = field.width, height = field.height
    let cos2 = orientation.cos2, sin2 = orientation.sin2
    let bounded = options.bounded
    let supportAmount = bounded.flowSupport ?? 0, supportScale = bounded.flowSupportScale ?? 0
    let irregularity = bounded.flowSeedIrregularity ?? 0
    func evidence(_ point: CGPoint) -> SupportSample? {
      support.map { supportSample($0, field: field, point: point, scale: supportScale) }
    }
    func confidence(_ point: CGPoint) -> Double? {
      support.map { supportConfidence($0, field: field, point: point, scale: supportScale) }
    }
    func direction(_ point: CGPoint, following previous: CGPoint?) -> CGPoint {
      var a = field.sample(cos2, point), b = field.sample(sin2, point)
      if let coarse = evidence(point) {
        let magnitude = hypot(a, b)
        let blend = supportAmount * coarse.confidence
        a = (magnitude > 1e-12 ? a / magnitude : 0) * (1 - blend) + coarse.cos2 * blend
        b = (magnitude > 1e-12 ? b / magnitude : 0) * (1 - blend) + coarse.sin2 * blend
      }
      // Quiet regions have no measured orientation. The deterministic diagonal
      // fallback is a graphic convention, not claimed surface geometry.
      let angle = hypot(a, b) > 1e-8 ? 0.5 * atan2(b, a) + .pi / 2 : -.pi / 4
      var vector = CGPoint(x: cos(angle), y: sin(angle))
      if let previous, dot(vector, previous) < 0 { vector = vector * -1 }
      return vector
    }
    let nominal = max(3, Double(options.hatchSpacing))
    let strength = min(2, max(0.4, options.tonalStrength))
    let strengthScale = sqrt(strength)
    let headingBlend = 0.35 + min(4, max(0, options.smoothing)) * 0.1
    let minimumLength = max(12, options.minimumContourLength * 2)
    let rectilinearity = options.bounded.flowRectilinearity ?? 0
    func spacing(_ point: CGPoint) -> Double {
      let darkness = max(0, 1 - field.sample(field.image, point))
      return max(minimumSpacing, nominal / ((0.25 + 0.75 * sqrt(darkness)) * strengthScale))
    }
    var occupied = Occupancy(width: width, height: height)
    for curve in structure {
      try Task.checkCancellation()
      occupied.insert(curve, radius: max(minimumSpacing, nominal * 0.45))
    }
    let strideSize = max(2, Int(nominal * 0.6))
    func seedPoint(_ index: Int) -> CGPoint {
      let point = CGPoint(x: index % width, y: index / width)
      guard irregularity > 0 else { return point }
      let hash = seedHash(index)
      let dx = (Double(hash & 0xffff) / 65_535 - 0.5) * Double(strideSize) * 0.9 * irregularity
      let dy = (Double((hash >> 16) & 0xffff) / 65_535 - 0.5) * Double(strideSize) * 0.9 * irregularity
      return CGPoint(x: min(Double(width) - 2.01, max(1, point.x + dx)),
        y: min(Double(height) - 2.01, max(1, point.y + dy)))
    }
    var seeds: [Int] = []
    for y in stride(from: 2, to: height - 2, by: strideSize) {
      for x in stride(from: 2, to: width - 2, by: strideSize) where field.image[y * width + x] < 0.92 {
        seeds.append(y * width + x)
      }
    }
    if irregularity > 0 {
      // Preserve darkness priority while removing the row-wise tie pattern in
      // similarly shaded cells. No random state or additional seeds are used.
      seeds.sort {
        let lhs = field.image[$0] + Double(seedHash($0) & 0xffff) / 65_535 * 0.025 * irregularity
        let rhs = field.image[$1] + Double(seedHash($1) & 0xffff) / 65_535 * 0.025 * irregularity
        return lhs == rhs ? $0 < $1 : lhs < rhs
      }
    } else {
      seeds.sort {
        field.image[$0] == field.image[$1] ? $0 < $1 : field.image[$0] < field.image[$1]
      }
    }
    var curves: [[CGPoint]] = []
    // Reuse only cells touched by the previous candidate. Allocating an entire
    // image-sized grid for every failed short trace made DEBUG work quadratic
    // in image area and candidate count despite the bounded path integration.
    var localOccupancy = Occupancy(width: width, height: height)
    let maximumSteps = 4 * (width + height), stepSize = 0.9
    for seed in seeds {
      try Task.checkCancellation()
      let start = seedPoint(seed)
      if irregularity > 0, field.sample(field.image, start) >= 0.92 { continue }
      if let value = confidence(start), value < supportAmount * 0.65 { continue }
      guard !occupied.intersects(start, radius: spacing(start)) else { continue }
      let seedMix = UInt64(seed) &* 2_654_435_761
      let chooseRectilinear = Double(seedMix & 0xffff) / 65_536 < rectilinearity
      if chooseRectilinear {
        if let straight = try PortraitRectilinearFlowTracer.trace(seed: start,
          tangent: direction(start, following: nil), width: width, height: height,
          minimumLength: minimumLength, spacing: spacing,
          luminance: { field.sample(field.image, $0) },
          intersects: { occupied.intersects($0, radius: $1) },
          support: support == nil ? nil : { confidence($0) ?? 0 },
          minimumSupport: supportAmount * 0.28, maximumUnsupportedLength: 2 + supportScale * 4) {
          if support != nil {
            let mean = straight.sampledPath.reduce(0) { $0 + (confidence($1) ?? 0) }
              / Double(straight.sampledPath.count)
            if mean < supportAmount * 0.4 { continue }
          }
          occupied.insert(straight.sampledPath, radii: straight.radii)
          curves.append(straight.endpoints)
        }
        continue
      }
      // Half-pixel visitation catches returning/crossing streamlines while
      // permitting adjacent integration samples. This is per candidate, bounded
      // by maximumSteps, and cannot grow with the number of previous candidates.
      var seen: [Int: Int] = [:]
      localOccupancy.reset()
      func key(_ point: CGPoint) -> Int { Int((point.y * 2).rounded()) * width * 2 + Int((point.x * 2).rounded()) }
      func trace(sign: Double) throws -> [CGPoint] {
        var result: [CGPoint] = [], point = start, heading = direction(start, following: nil) * sign
        var unsupportedLength = 0.0, supportedCount = 0
        for index in 0..<maximumSteps {
          if index.isMultiple(of: 64) { try Task.checkCancellation() }
          let first = direction(point, following: heading)
          let middle = point + first * (stepSize * 0.5)
          let proposed = direction(middle, following: first)
          // A tensor singularity must not create a sudden hairpin. Integrating
          // a bounded turn gives smooth plotter motion; stop at an opposing flow.
          guard dot(proposed, heading) > 0.35 else { break }
          let tangent = unit(proposed * (1 - headingBlend) + heading * headingBlend)
          let next = point + tangent * stepSize
          let nextSpacing = spacing(next)
          guard next.x >= 1, next.y >= 1, next.x < Double(width - 2), next.y < Double(height - 2),
            field.sample(field.image, next) < 0.95,
            !occupied.intersects(next, radius: nextSpacing) else { break }
          let progress = sign * Double(index + 1) * stepSize
          guard !localOccupancy.intersects(next, radius: nextSpacing,
            excludingAdjacentProgress: progress) else { break }
          let cell = key(next)
          if let earlier = seen[cell], index > 3 || earlier < 0 { break }
          if let value = confidence(next) {
            if value >= supportAmount * 0.28 { unsupportedLength = 0; supportedCount = result.count + 1 }
            else { unsupportedLength += stepSize }
            if unsupportedLength > 2 + supportScale * 4 { break }
          }
          seen[cell] = sign > 0 ? index : -index - 1
          localOccupancy.insert(next, radius: nextSpacing, tangent: tangent, progress: progress)
          result.append(next); point = next; heading = tangent
        }
        if support != nil, supportedCount < result.count { result.removeSubrange(supportedCount...) }
        return result
      }
      let backward = try trace(sign: -1)
      let forward = try trace(sign: 1)
      let curve = Array(backward.reversed()) + [start] + forward
      guard length(curve) >= minimumLength else { continue }
      if support != nil {
        let mean = curve.reduce(0) { $0 + (confidence($1) ?? 0) } / Double(curve.count)
        if mean < supportAmount * 0.4 { continue }
      }
      // Retain integration samples. Chord simplification could cut across a
      // reserved feature curve or through the material clearance tube.
      occupied.insert(curve, radii: curve.map(spacing))
      curves.append(curve)
    }
    return curves
  }

  private struct Occupancy {
    struct Entry { let point: CGPoint; let radius: Double; let tangent: CGPoint; let progress: Double? }
    let width: Int
    let height: Int
    let columns: Int
    let rows: Int
    var cells: [[Entry]]
    var touchedCells: [Int] = []
    var maximumRadius = 0.0
    private let cellSize = 4.0

    init(width: Int, height: Int) {
      self.width = width; self.height = height
      columns = (width + 3) / 4; rows = (height + 3) / 4
      cells = .init(repeating: [], count: columns * rows)
    }

    mutating func reset() {
      for index in touchedCells { cells[index].removeAll(keepingCapacity: true) }
      touchedCells.removeAll(keepingCapacity: true)
      maximumRadius = 0
    }

    func intersects(_ point: CGPoint, radius: Double, parallelTo direction: CGPoint? = nil,
      excludingAdjacentProgress progress: Double? = nil) -> Bool {
      // Sampled curves are covered conservatively between their samples as well
      // as at them. The same floor applies to every strength and spacing setting.
      let reach = max(radius, maximumRadius) + 0.6
      let x0 = max(0, Int((point.x - reach) / cellSize)), x1 = min(columns - 1, Int((point.x + reach) / cellSize))
      let y0 = max(0, Int((point.y - reach) / cellSize)), y1 = min(rows - 1, Int((point.y + reach) / cellSize))
      guard x0 <= x1, y0 <= y1 else { return false }
      for y in y0...y1 {
        for x in x0...x1 {
          for entry in cells[y * columns + x] {
            if let direction, abs(dot(direction, entry.tangent)) < 0.8 { continue }
            if let progress, let prior = entry.progress,
              abs(progress - prior) <= max(radius, entry.radius) + 1.8 { continue }
            let distance = max(radius, entry.radius) + 0.6
            let difference = point - entry.point
            if dot(difference, difference) < distance * distance { return true }
          }
        }
      }
      return false
    }

    mutating func insert(_ path: [CGPoint], radius: Double) {
      insert(path, radii: .init(repeating: radius, count: path.count))
    }

    mutating func insert(_ path: [CGPoint], radii: [Double]) {
      guard let first = path.first, let firstRadius = radii.first else { return }
      let firstTangent = path.count > 1 ? unit(path[1] - first) : CGPoint(x: 1, y: 0)
      insert(first, radius: firstRadius, tangent: firstTangent)
      for i in 1..<path.count {
        let a = path[i - 1], b = path[i], steps = max(1, Int(ceil(hypot(b.x - a.x, b.y - a.y))))
        for step in 1...steps {
          let amount = Double(step) / Double(steps)
          insert(a + (b - a) * amount, radius: max(radii[i - 1], radii[i]), tangent: unit(b - a))
        }
      }
    }

    mutating func insert(_ point: CGPoint, radius: Double, tangent: CGPoint, progress: Double? = nil) {
      let x = min(columns - 1, max(0, Int(point.x / cellSize)))
      let y = min(rows - 1, max(0, Int(point.y / cellSize)))
      let index = y * columns + x
      if cells[index].isEmpty { touchedCells.append(index) }
      cells[index].append(.init(point: point, radius: radius, tangent: tangent, progress: progress))
      maximumRadius = max(maximumRadius, radius)
    }
  }

  /// Two separable box passes give a continuous piecewise-linear averaging
  /// kernel in O(pixels), independent of radius. Used for orientation tensors
  /// and separate support-image copies; the original structural image is fixed.
  private static func coherentField(_ values: [Double], width: Int, height: Int,
    radius: Int) throws -> [Double] {
    var current = values
    let divisor = Double(2 * radius + 1)
    // Border addresses depend only on dimensions/radius. Reuse them across
    // every row, column and pass instead of generic clamp/multiply operations
    // at each pixel. The floating-point accumulation order is unchanged.
    let removeColumns = (0..<width).map { max(0, $0 - radius) }
    let addColumns = (0..<width).map { min(width - 1, $0 + radius + 1) }
    let removeRows = (0..<height).map { max(0, $0 - radius) * width }
    let addRows = (0..<height).map { min(height - 1, $0 + radius + 1) * width }
    let initialColumns = (-radius...radius).map { min(width - 1, max(0, $0)) }
    let initialRows = (-radius...radius).map { min(height - 1, max(0, $0)) * width }
    for _ in 0..<2 {
      var horizontal = [Double](repeating: 0, count: values.count)
      var output = horizontal
      try current.withUnsafeBufferPointer { source in
        try horizontal.withUnsafeMutableBufferPointer { target in
          try removeColumns.withUnsafeBufferPointer { remove in
            try addColumns.withUnsafeBufferPointer { add in
              let input = source.baseAddress!, result = target.baseAddress!
              let removed = remove.baseAddress!, added = add.baseAddress!
              for y in 0..<height {
                try Task.checkCancellation()
                let row = y * width
                var total = 0.0
                for column in initialColumns { total += input[row + column] }
                for x in 0..<width {
                  result[row + x] = total / divisor
                  total -= input[row + removed[x]]
                  total += input[row + added[x]]
                }
              }
            }
          }
        }
      }
      try horizontal.withUnsafeBufferPointer { source in
        try output.withUnsafeMutableBufferPointer { target in
          try removeRows.withUnsafeBufferPointer { remove in
            try addRows.withUnsafeBufferPointer { add in
              let input = source.baseAddress!, result = target.baseAddress!
              let removed = remove.baseAddress!, added = add.baseAddress!
              for x in 0..<width {
                try Task.checkCancellation()
                var total = 0.0
                for row in initialRows { total += input[row + x] }
                for y in 0..<height {
                  result[y * width + x] = total / divisor
                  total -= input[removed[y] + x]
                  total += input[added[y] + x]
                }
              }
            }
          }
        }
      }
      current = output
    }
    return current
  }

  private static func resampled(_ path: [CGPoint]) -> [CGPoint] {
    guard let first = path.first else { return [] }
    var result = [first]
    for (a, b) in zip(path, path.dropFirst()) {
      let steps = max(1, Int(ceil(hypot(b.x - a.x, b.y - a.y) / 0.9)))
      for step in 1...steps { result.append(a + (b - a) * (Double(step) / Double(steps))) }
    }
    return result
  }

  /// Four conservative fairing iterations keep every moved point within 0.4 px
  /// of its observed ridge. A small Douglas-Peucker tolerance bounds the further
  /// chord error; large legacy simplification settings cannot flatten a face.
  private static func fair(_ original: [CGPoint], tolerance: Double) throws -> [CGPoint] {
    guard original.count > 2 else { return original }
    let closed = original.first == original.last
    var points = original
    for _ in 0..<4 {
      try Task.checkCancellation()
      var next = points
      for i in 1..<(points.count - 1) {
        let proposal = points[i] * 0.5 + (points[i - 1] + points[i + 1]) * 0.25
        let displacement = proposal - original[i], distance = hypot(displacement.x, displacement.y)
        next[i] = original[i] + displacement * (distance > 0.4 ? 0.4 / distance : 1)
      }
      if closed, points.count > 3 {
        let proposal = points[0] * 0.5 + (points[1] + points[points.count - 2]) * 0.25
        let displacement = proposal - original[0], distance = hypot(displacement.x, displacement.y)
        next[0] = original[0] + displacement * (distance > 0.4 ? 0.4 / distance : 1)
        next[next.count - 1] = next[0]
      }
      points = next
    }
    guard tolerance > 0 else { return points }
    var keep = Set([0, points.count - 1]), pending = [(0, points.count - 1)]
    while let (first, last) = pending.popLast() {
      try Task.checkCancellation()
      guard last - first > 1 else { continue }
      let a = points[first], direction = points[last] - a, squared = dot(direction, direction)
      var farthest = first, maximum = tolerance
      for i in (first + 1)..<last {
        let t = squared > 0 ? min(1, max(0, dot(points[i] - a, direction) / squared)) : 0
        let delta = points[i] - (a + direction * t), distance = hypot(delta.x, delta.y)
        if distance > maximum { maximum = distance; farthest = i }
      }
      if farthest != first {
        keep.insert(farthest); pending.append((first, farthest)); pending.append((farthest, last))
      }
    }
    return keep.sorted().map { points[$0] }
  }

  private static func blur(_ values: [Double], width: Int, height: Int, sigma: Double) throws -> [Double] {
    let radius = Int(ceil(3 * sigma))
    let raw = (-radius...radius).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
    let sum = raw.reduce(0, +), kernel = raw.map { $0 / sum }
    var horizontal = [Double](repeating: 0, count: values.count), result = horizontal
    // Validated dimensions and border clamping make these pointer scopes fully
    // bounded. Avoid per-tap Array ownership/access overhead in normal DEBUG
    // builds; arithmetic order and edge-clamping are unchanged.
    try values.withUnsafeBufferPointer { source in
      try horizontal.withUnsafeMutableBufferPointer { target in
        let input = source.baseAddress!, output = target.baseAddress!
        for y in 0..<height {
          try Task.checkCancellation()
          let row = y * width
          for x in 0..<width {
            let i = row + x
            if radius == 2, x >= 2, x < width - 2 {
              var value = input[i - 2] * kernel[0]
              value += input[i - 1] * kernel[1]
              value += input[i] * kernel[2]
              value += input[i + 1] * kernel[3]
              value += input[i + 2] * kernel[4]
              output[i] = value
            } else {
              var value = 0.0
              for offset in -radius...radius {
                value += input[row + min(width - 1, max(0, x + offset))] * kernel[offset + radius]
              }
              output[i] = value
            }
          }
        }
      }
    }
    try horizontal.withUnsafeBufferPointer { source in
      try result.withUnsafeMutableBufferPointer { target in
        let input = source.baseAddress!, output = target.baseAddress!
        for y in 0..<height {
          try Task.checkCancellation()
          for x in 0..<width {
            let i = y * width + x
            if radius == 2, y >= 2, y < height - 2 {
              var value = input[i - 2 * width] * kernel[0]
              value += input[i - width] * kernel[1]
              value += input[i] * kernel[2]
              value += input[i + width] * kernel[3]
              value += input[i + 2 * width] * kernel[4]
              output[i] = value
            } else {
              var value = 0.0
              for offset in -radius...radius {
                value += input[min(height - 1, max(0, y + offset)) * width + x] * kernel[offset + radius]
              }
              output[i] = value
            }
          }
        }
      }
    }
    return result
  }

  private static func sample(_ values: [Double], _ point: CGPoint, width: Int, height: Int) -> Double {
    let px = min(Double(width - 1), max(0, point.x)), py = min(Double(height - 1), max(0, point.y))
    let x = Int(px), y = Int(py), x1 = min(width - 1, x + 1), y1 = min(height - 1, y + 1)
    let fx = px - Double(x), fy = py - Double(y)
    return (values[y * width + x] * (1 - fx) + values[y * width + x1] * fx) * (1 - fy)
      + (values[y1 * width + x] * (1 - fx) + values[y1 * width + x1] * fx) * fy
  }

  private static func seedHash(_ index: Int) -> UInt64 {
    var value = UInt64(index) &+ 0x9e3779b97f4a7c15
    value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
    value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
    return value ^ (value >> 31)
  }

  private static func length(_ points: [CGPoint]) -> Double {
    zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
  }
  private static func dot(_ a: CGPoint, _ b: CGPoint) -> Double { a.x * b.x + a.y * b.y }
  private static func unit(_ point: CGPoint) -> CGPoint {
    let size = hypot(point.x, point.y)
    return size > 1e-12 ? point * (1 / size) : CGPoint(x: 1, y: 0)
  }
}

private func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
private func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
private func * (lhs: CGPoint, rhs: Double) -> CGPoint { CGPoint(x: lhs.x * rhs, y: lhs.y * rhs) }
