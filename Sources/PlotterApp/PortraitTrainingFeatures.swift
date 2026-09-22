import Foundation

enum PortraitTrainingFeatures {
  static let revision = "portrait-features-fixed-normalization-v1"
  static let semanticParameters: Set<PortraitTrainableParameter> = [.foreheadWidth, .foreheadHeight, .eyeScale, .lateralScale]

  static func bounds(_ parameter: PortraitTrainableParameter) -> ClosedRange<Double> {
    switch parameter {
    case .contourLevels: 1...12
    case .minimumContourLength: 0...40
    case .simplificationTolerance: 0...3
    case .hatchSpacing: 1...16
    case .tonalStrength: 0.4...2
    case .smoothing: 0...4
    case .sketchThreshold: 0.002...0.08
    case .hatchAngleDegrees: -90...90
    case .headScale: 1...1.6
    case .foreheadWidth, .foreheadHeight, .eyeScale, .lateralScale: 0...0.6
    }
  }

  static func value(_ parameter: PortraitTrainableParameter, in options: PortraitVectorOptions) -> Double {
    switch parameter {
    case .contourLevels: Double(options.contourLevels)
    case .minimumContourLength: options.minimumContourLength
    case .simplificationTolerance: options.simplificationTolerance
    case .hatchSpacing: Double(options.hatchSpacing)
    case .tonalStrength: options.tonalStrength
    case .smoothing: options.smoothing
    case .sketchThreshold: options.sketchThreshold
    case .hatchAngleDegrees: options.hatchAngleDegrees
    case .headScale: options.headScale
    case .foreheadWidth: options.semanticHead?.foreheadWidth ?? 0
    case .foreheadHeight: options.semanticHead?.foreheadHeight ?? 0
    case .eyeScale: options.semanticHead?.eyeScale ?? 0
    case .lateralScale: options.semanticHead?.lateralScale ?? 0
    }
  }

  static func setting(_ parameter: PortraitTrainableParameter, value: Double, in options: PortraitVectorOptions) -> PortraitVectorOptions {
    var result = options
    let range = bounds(parameter)
    let v = value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : range.lowerBound
    switch parameter {
    case .contourLevels: result.contourLevels = Int(v.rounded())
    case .minimumContourLength: result.minimumContourLength = v
    case .simplificationTolerance: result.simplificationTolerance = v
    case .hatchSpacing: result.hatchSpacing = Int(v.rounded())
    case .tonalStrength: result.tonalStrength = v
    case .smoothing: result.smoothing = v
    case .sketchThreshold: result.sketchThreshold = v
    case .hatchAngleDegrees: result.hatchAngleDegrees = v
    case .headScale: result.headScale = v
    case .foreheadWidth, .foreheadHeight, .eyeScale, .lateralScale:
      var head = result.semanticHead ?? PortraitSemanticHeadParameters()
      switch parameter {
      case .foreheadWidth: head.foreheadWidth = v
      case .foreheadHeight: head.foreheadHeight = v
      case .eyeScale: head.eyeScale = v
      default: head.lateralScale = v
      }
      result.semanticHead = head
    }
    return result
  }

  static func schema(scope: PortraitTrainingScopeDefinition) throws -> PortraitFeatureSchema {
    try PortraitTrainingValidation.scope(scope)
    var features: [PortraitFeatureSchema.Feature] = []
    for parameter in scope.scope.activeParameters.sorted(by: { $0.rawValue < $1.rawValue }) {
      let range = bounds(parameter), midpoint = (range.lowerBound + range.upperBound) / 2
      let scale = (range.upperBound - range.lowerBound) / 2
      features.append(.init(name: "parameter." + parameter.rawValue, transform: "center-scale-v1", offset: midpoint, scale: scale))
      features.append(.init(name: "quadratic." + parameter.rawValue, transform: "center-scale-square-v1", offset: midpoint, scale: scale))
    }
    for family in PortraitStyle.legacyCases { features.append(.init(name: "family." + family.rawValue, transform: "indicator-v1", offset: 0, scale: 1)) }
    for (name, scale) in [("source.aspect", 4.0), ("source.meanLuminance", 1), ("source.faceKnown", 1),
      ("render.strokeCount", 1000), ("render.pointCount", 20000), ("render.pathLengthPerHeight", 1000),
      ("presentation.height", 500), ("presentation.inkWidth", 5), ("presentation.measured", 1)] {
      features.append(.init(name: name, transform: "positive-saturating-v1", offset: 0, scale: scale))
    }
    return .init(revision: revision, features: features)
  }

  static func validateCandidate(_ candidate: PortraitCandidate, scope: PortraitTrainingScopeDefinition) throws {
    try candidate.validateIntegrity()
    guard scope.scope.allowedFamilies.contains(candidate.recipe.style) else {
      throw PortraitTrainingError.incompatible("Candidate family differs from the named scope.")
    }
    let options = candidate.recipe.vectorOptions
    for parameter in PortraitTrainableParameter.allCases {
      let actual = value(parameter, in: options)
      guard actual.isFinite, bounds(parameter).contains(actual) else { throw PortraitTrainingError.invalid("Candidate parameter outside renderer bounds.") }
      if !scope.scope.activeParameters.contains(parameter) {
        let expected = scope.scope.frozenParameters.first { $0.parameter == parameter }?.value
          ?? value(parameter, in: scope.referenceRecipe.vectorOptions)
        guard abs(actual - expected) < 1e-10 else { throw PortraitTrainingError.incompatible("Frozen parameter changed: " + parameter.rawValue) }
      }
    }
    if scope.mode == .semanticBigHead {
      guard let face = candidate.raster.faceAnalysis, face.status == .detected,
        let manifest = candidate.warpManifest, [.applied, .limited, .identity].contains(manifest.status),
        manifest.basis != nil, manifest.analysisSHA256 != nil else {
        throw PortraitTrainingError.incompatible("Semantic Big Head requires supported exact face analysis and warp evidence.")
      }
      try face.validate()
    } else {
      guard options.semanticHead == scope.referenceRecipe.vectorOptions.semanticHead else {
        throw PortraitTrainingError.incompatible("Ordinary style training must freeze semantic head geometry.")
      }
    }
  }

  static func values(candidate: PortraitCandidate, scope: PortraitTrainingScopeDefinition,
    schema: PortraitFeatureSchema, presentation: PortraitTrainingPresentation) throws -> [Double] {
    guard schema == (try self.schema(scope: scope)) else { throw PortraitTrainingError.incompatible("Feature schema changed.") }
    try validateCandidate(candidate, scope: scope)
    guard presentation.drawingHeightMM.isFinite, presentation.drawingHeightMM > 0,
      presentation.inkWidthMM.isFinite, presentation.inkWidthMM > 0,
      candidate.raster.width > 0, candidate.raster.height > 0,
      candidate.raster.width <= 10000, candidate.raster.height <= 10000,
      candidate.raster.luminance.count == candidate.raster.width * candidate.raster.height, candidate.raster.luminance.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
      throw PortraitTrainingError.invalid("Source or presentation is nonfinite or unavailable.")
    }
    var values: [Double] = []
    for parameter in scope.scope.activeParameters.sorted(by: { $0.rawValue < $1.rawValue }) {
      let range = bounds(parameter)
      let x = (value(parameter, in: candidate.recipe.vectorOptions) - (range.lowerBound + range.upperBound) / 2) / ((range.upperBound - range.lowerBound) / 2)
      values += [x, x*x]
    }
    values += PortraitStyle.legacyCases.map { $0 == candidate.recipe.style ? 1 : 0 }
    let program = candidate.program
    var length = 0.0, pointCount = 0
    for stroke in program.strokes {
      let points = stroke.path.points
      pointCount += points.count
      for pair in zip(points, points.dropFirst()) { length += hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y) }
    }
    let mean = candidate.raster.luminance.reduce(0, +) / Double(candidate.raster.luminance.count)
    let raw: [Double] = [candidate.raster.sourceCropExtent?.aspectRatio ?? Double(candidate.raster.width) / Double(max(1, candidate.raster.height)),
      mean, candidate.raster.faceAnalysis?.status == .detected ? 1 : 0,
      Double(program.strokes.count), Double(pointCount), length / program.fieldExtent.height,
      presentation.drawingHeightMM, presentation.inkWidthMM, presentation.inkWidthIsMeasured ? 1 : 0]
    let scales: [Double] = [4.0, 1, 1, 1000, 20000, 1000, 500, 5, 1]
    for (x, scale) in zip(raw, scales) { values.append(x / (scale + x)) }
    guard values.count == schema.features.count, values.allSatisfy(\.isFinite) else { throw PortraitTrainingError.nonFinite }
    return values
  }
}
