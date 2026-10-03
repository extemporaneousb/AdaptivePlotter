import CoreGraphics
import Foundation
import ImageIO
import PlotterModel
import UniformTypeIdentifiers

/// Feedback belongs to an exact attempt. Inspecting an attempt never supplies a vote.
enum PortraitAttemptFeedback: String, Codable, CaseIterable, Sendable {
  case unknown, promising, rejected
}

struct PortraitAttemptFeedbackRevision: Codable, Hashable, Sendable {
  let id: UUID
  let value: PortraitAttemptFeedback
  let createdAt: Date
}

struct PortraitAttemptRecord: Codable, Equatable, Sendable {
  let thumbnailPNG: Data
  let proposalIdentity: String
  let changeCue: String
  var burdenSummary: String? = nil
  var parameterPreference: PortraitParameterPreference.Model? = nil
  var feedbackRevisions: [PortraitAttemptFeedbackRevision] = []
  var feedback: PortraitAttemptFeedback { feedbackRevisions.last?.value ?? .unknown }

  static func prepare(candidate: PortraitCandidate, pen: StrokeStyle) throws -> Self {
    .init(thumbnailPNG: try PortraitAttemptThumbnail.render(candidate.program),
      proposalIdentity: try proposalIdentity(sourceSHA256: candidate.sourceSHA256,
        sourcePixelExtent: candidate.sourcePixelExtent, pose: candidate.renderPose,
        recipe: candidate.recipe, pen: pen), changeCue: changeCue(for: candidate),
      burdenSummary: PortraitStrokeBurden(program: candidate.program).summary)
  }

  /// Seed, title, recipe ID and ancestry describe how a proposal was found. They
  /// cannot make a rejected source/recipe configuration new again.
  static func proposalIdentity(sourceSHA256: String, sourcePixelExtent: PortraitSourceCropExtent?,
    pose: PortraitPose?, recipe: PortraitStyleRecipe, pen: StrokeStyle) throws -> String {
    struct Identity: Encodable {
      let revision = "portrait-attempt-recipe-v2"
      let rendererRevision = "portrait-v3-v4|" + PortraitFlowRenderer.revision + "|portrait-regions-v1"
      let sourcePreparationRevision = PortraitSourcePreparation.revision
      let landmarksRevision = PortraitFaceLandmarkAnalyzer.requestRevision
      let sourceSHA256: String
      let sourcePixelExtent: PortraitSourceCropExtent?
      let pose: PortraitPose?
      let style: PortraitStyle
      let analysis: PortraitAnalysisOptions
      let vectors: PortraitVectorOptions
      let pen: StrokeStyle
    }
    return PortraitCandidateCoding.digest(try PortraitCandidateCoding.encoder().encode(
      Identity(sourceSHA256: sourceSHA256, sourcePixelExtent: sourcePixelExtent, pose: pose,
        style: recipe.style, analysis: recipe.analysisOptions,
        vectors: PortraitExplorationPolicy.canonicalOptions(recipe.vectorOptions, style: recipe.style), pen: pen)))
  }

  private static func changeCue(for candidate: PortraitCandidate) -> String {
    guard let parent = candidate.lineage.parentRecipe else { return candidate.recipe.title }
    var changes: [String] = []
    if parent.analysisOptions != candidate.recipe.analysisOptions { changes.append("Framing") }
    if parent.style != candidate.recipe.style { changes.append(candidate.recipe.style.rawValue) }
    let prior = parent.vectorOptions, next = candidate.recipe.vectorOptions
    if prior.regionalAdjustments != next.regionalAdjustments, let last = next.regionalAdjustments?.last { changes.append(last.scope.rawValue) }
    if prior.regionalTreatment != next.regionalTreatment { changes.append("Regions") }
    if prior.semanticHead != next.semanticHead || prior.eyeExaggeration != next.eyeExaggeration { changes.append("Exaggeration") }
    if prior.flowRectilinearity != next.flowRectilinearity { changes.append("Line form") }
    if prior.tonalStrength != next.tonalStrength { changes.append("Tone") }
    if prior.smoothing != next.smoothing { changes.append("Coherence") }
    if changes.isEmpty, prior != next { changes.append("Detail") }
    return changes.isEmpty ? "Same treatment" : changes.prefix(2).joined(separator: " · ")
  }
}

struct PortraitSavedStyle: Identifiable, Codable, Sendable {
  let id: UUID
  let name: String
  let recipe: PortraitStyleRecipe
  let createdAt: Date
}

/// Generated once off the main actor, then retained with the geometry. History
/// navigation decodes these small images and never invokes the portrait renderer.
enum PortraitAttemptThumbnail {
  static func render(_ program: DrawingProgram) throws -> Data {
    let side = 192
    guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
      throw PortraitCandidateError.invalidPresentation
    }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    let scale = Double(side - 12) / max(program.fieldExtent.width, program.fieldExtent.height)
    let originX = (Double(side) - program.fieldExtent.width * scale) / 2
    let originY = (Double(side) - program.fieldExtent.height * scale) / 2
    context.setStrokeColor(CGColor(gray: 0.08, alpha: 1))
    context.setLineCap(.round)
    context.setLineJoin(.round)
    for stroke in program.strokes {
      guard let first = stroke.path.points.first else { continue }
      context.beginPath()
      context.setLineWidth(max(0.65, stroke.style.nominalLineWidth * scale))
      context.move(to: CGPoint(x: originX + first.x * scale, y: originY + first.y * scale))
      for point in stroke.path.points.dropFirst() {
        context.addLine(to: CGPoint(x: originX + point.x * scale, y: originY + point.y * scale))
      }
      context.strokePath()
    }
    guard let image = context.makeImage() else { throw PortraitCandidateError.invalidPresentation }
    let bytes = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else {
      throw PortraitCandidateError.invalidPresentation
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw PortraitCandidateError.invalidPresentation }
    return bytes as Data
  }
}
