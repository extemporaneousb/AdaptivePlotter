import Foundation
import PlotterModel
import SwiftUI

/// Read-only inputs from the existing Draft and material owners.
struct PortraitPlanePreviewSource {
  var region: DrawableMachineRegion?
  var artworkPlan: ExecutionPlanRevision?
  var material: DrawingMaterialProfileRevision?
  var materialUnavailableReason: String?

  init(region: DrawableMachineRegion? = nil, artworkPlan: ExecutionPlanRevision? = nil,
    material: DrawingMaterialProfileRevision? = nil, materialUnavailableReason: String? = nil) {
    self.region = region; self.artworkPlan = artworkPlan
    self.material = material; self.materialUnavailableReason = materialUnavailableReason
  }

  func resolve(program: DrawingProgram?, nominalWidth: Double) -> PortraitPlanePreview {
    let matched = artworkPlan.flatMap { plan -> ExecutionPlanRevision? in
      guard let program, let region, plan.drawableRegion == region,
        plan.sourceProgramID == program.id, plan.sourceProgramContentHash == program.contentHash
      else { return nil }
      return plan
    }
    let profile = material?.qualification == .unavailable ? nil : material
    let width = profile?.conservativeWidthMM ?? program?.strokes.first?.style.nominalLineWidth ?? nominalWidth
    let reason = region == nil ? "Drawing region unavailable · reference preview"
      : matched == nil ? "Unplaced reference preview · project this drawing for actual placement"
      : matched?.placement.cameraGeometry != nil
        ? "Camera-proportioned drawing · physical dimensions unverified"
        : "Current drawing placement · physical dimensions unverified"
    let evidence = program.flatMap { program in
      try? PortraitDisplayEvidence(mode: matched == nil ? .reference : .planned,
        programContentHash: program.contentHash.description, region: region,
        placement: matched?.placement, planContentHash: matched?.contentHash.description,
        widthSource: profile == nil ? .nominalProgram : .applicableMaterial)
    }
    return PortraitPlanePreview(program: program, region: region, evidence: evidence,
      plannedStrokes: matched?.strokes, inkWidthMM: width,
      inkWidthIsMeasured: profile?.independentlyMeasured == true,
      materialProfile: profile, materialRevision: profile?.key,
      statusText: reason, materialUnavailableReason: materialUnavailableReason,
      savedPresentation: nil)
  }
}

struct PortraitPlaneRenderGeometry {
  let regionRect: CGRect
  var regionOutline: [CGPoint]? = nil
  let paths: [[CGPoint]]
  let lineWidth: Double
  let screenScale: Double
}

/// A presentation of exact planned machine points, or an explicitly normalized
/// reference drawing. It neither plans nor changes a drawing placement.
struct PortraitPlanePreview {
  let program: DrawingProgram?
  let region: DrawableMachineRegion?
  let evidence: PortraitDisplayEvidence?
  let plannedStrokes: [PlannedMachineStroke]?
  let inkWidthMM: Double
  let inkWidthIsMeasured: Bool
  let materialProfile: DrawingMaterialProfileRevision?
  let materialRevision: String?
  let statusText: String
  let materialUnavailableReason: String?
  let savedPresentation: PortraitPresentationContext?

  // Only the factories in this file construct previews. plannedStrokes is the
  // matching immutable plan or its prefix, so plan hash + count identifies it.
  fileprivate struct GeometryKey: Equatable {
    let programHash: Digest?
    let region: DrawableMachineRegion?
    let evidence: PortraitDisplayEvidence?
    let plannedStrokeCount: Int?
    let inkWidthMM: Double
  }

  fileprivate var geometryKey: GeometryKey {
    .init(programHash: program?.contentHash, region: region, evidence: evidence,
      plannedStrokeCount: plannedStrokes?.count, inkWidthMM: inkWidthMM)
  }

  fileprivate init(program: DrawingProgram?, region: DrawableMachineRegion?,
    evidence: PortraitDisplayEvidence?, plannedStrokes: [PlannedMachineStroke]?,
    inkWidthMM: Double, inkWidthIsMeasured: Bool,
    materialProfile: DrawingMaterialProfileRevision?, materialRevision: String?,
    statusText: String, materialUnavailableReason: String?,
    savedPresentation: PortraitPresentationContext?) {
    self.program = program
    self.region = region
    self.evidence = evidence
    self.plannedStrokes = plannedStrokes
    self.inkWidthMM = inkWidthMM
    self.inkWidthIsMeasured = inkWidthIsMeasured
    self.materialProfile = materialProfile
    self.materialRevision = materialRevision
    self.statusText = statusText
    self.materialUnavailableReason = materialUnavailableReason
    self.savedPresentation = savedPresentation
  }

  /// A sealed execution plan is sufficient to draw its exact machine paths.
  /// No current authoring program or second planning pass participates.
  static func planned(_ plan: ExecutionPlanRevision, completedStrokeCount: Int? = nil) -> Self {
    let evidence = try? PortraitDisplayEvidence(mode: .planned,
      programContentHash: plan.sourceProgramContentHash.description,
      region: plan.drawableRegion, placement: plan.placement,
      planContentHash: plan.contentHash.description, widthSource: .nominalProgram)
    return Self(program: nil, region: plan.drawableRegion, evidence: evidence,
      plannedStrokes: completedStrokeCount.map { Array(plan.strokes.prefix(max(0, $0))) } ?? plan.strokes, inkWidthMM: plan.strokes.first?.style.nominalLineWidth ?? 0.4,
      inkWidthIsMeasured: false, materialProfile: nil, materialRevision: nil,
      statusText: "Exact planned drawing · physical dimensions unverified",
      materialUnavailableReason: nil, savedPresentation: nil)
  }

  var actualDrawingHeightMM: Double? {
    guard evidence?.mode == .planned, let program, let placement = evidence?.placement else { return nil }
    return try? placement.controllerEdgeLengths(for: program.fieldExtent).height
  }
  var actualDrawingWidthMM: Double? {
    guard evidence?.mode == .planned, let program, let placement = evidence?.placement else { return nil }
    return try? placement.controllerEdgeLengths(for: program.fieldExtent).width
  }
  var materialReferenceHeight: Double? {
    guard evidence?.mode == .planned, let program, let placement = evidence?.placement else { return nil }
    return program.fieldExtent.height * placement.minimumScale
  }
  private var cameraRegion: [Point2<CameraPixelSpace>]? {
    guard let camera = evidence?.placement?.cameraGeometry?.cameraFromMachine,
      let bounds = evidence?.region?.effectiveBounds else { return nil }
    return try? bounds.corners.map { try camera.applying(to: $0) }
  }
  var aspectRatio: Double {
    if let points = cameraRegion,
      let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
      let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() {
      return (maxX - minX) / (maxY - minY)
    }
    if let bounds = region?.effectiveBounds {
      return (bounds.maxX - bounds.minX) / (bounds.maxY - bounds.minY)
    }
    guard let program else { return 1 }
    return program.fieldExtent.width / program.fieldExtent.height
  }
  var dimensionsText: String {
    guard let bounds = region?.effectiveBounds else {
      return "Drawing region and placed size unavailable."
    }
    let region = String(format: "Region %.1f × %.1f controller mm", bounds.maxX - bounds.minX, bounds.maxY - bounds.minY)
    guard let width = actualDrawingWidthMM, let height = actualDrawingHeightMM else {
      return region + " · drawing size unavailable"
    }
    let label = evidence?.placement?.cameraGeometry == nil ? "Artwork" : "Artwork edges (controller units)"
    return String(format: "\(label) %.1f × %.1f · ", width, height) + region
  }
  var inkDescription: String {
    let source: String
    if let materialProfile {
      let qualification: String
      switch materialProfile.qualification {
      case .nominal: qualification = "nominal estimate"
      case .controllerCoordinateEstimate: qualification = "controller-coordinate estimate"
      case .independentlyMeasured: qualification = "independently measured"
      case .bounded: qualification = "bounded measurement"
      case .unavailable: qualification = "unavailable"
      }
      source = "\(materialProfile.name), revision \(materialProfile.revision) · \(qualification)"
    } else if savedPresentation != nil, evidence?.widthSource == .applicableMaterial {
      source = "Saved material width · \(inkWidthIsMeasured ? "measured" : "estimated")"
    } else { source = "Program nominal width · estimate" }
    let reference = actualDrawingHeightMM == nil ? "Reference line appearance; actual drawing size unavailable. " : ""
    return reference + String(format: "Ink %.2f mm · ", inkWidthMM) + source
      + (materialUnavailableReason.map { ". " + $0 } ?? "")
  }
  var presentationContext: PortraitPresentationContext? {
    if let savedPresentation { return savedPresentation }
    guard let evidence else { return nil }
    return try? PortraitPresentationContext(drawingHeightMM: actualDrawingHeightMM ?? 100,
      inkWidthMM: inkWidthMM, inkWidthIsMeasured: inkWidthIsMeasured,
      materialRevision: materialRevision, objective: .screenAesthetic,
      prompt: "Rate likeness and drawing quality as displayed", displayEvidence: evidence)
  }

  static func historical(program: DrawingProgram, presentation: PortraitPresentationContext) -> Self {
    let evidence = presentation.displayEvidence.flatMap { value -> PortraitDisplayEvidence? in
      guard value.programContentHash == program.contentHash.description,
        (try? value.validate()) != nil else { return nil }
      return value
    }
    return Self(program: evidence == nil ? nil : program, region: evidence?.region,
      evidence: evidence, plannedStrokes: nil,
      inkWidthMM: presentation.inkWidthMM, inkWidthIsMeasured: presentation.inkWidthIsMeasured,
      materialProfile: nil, materialRevision: presentation.materialRevision,
      statusText: evidence == nil ? "Saved preview context unavailable"
        : evidence?.mode == .planned ? "Saved drawing placement" : "Saved reference preview",
      materialUnavailableReason: nil, savedPresentation: presentation)
  }

  func geometry(in size: CGSize) -> PortraitPlaneRenderGeometry? {
    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
    let ratio = aspectRatio
    let width = min(size.width, size.height * ratio), height = width / ratio
    let rect = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    if evidence?.mode == .planned, let bounds = evidence?.region?.effectiveBounds,
      let placement = evidence?.placement {
      let scale = width / (bounds.maxX - bounds.minX)
      let paths = plannedStrokes?.map { $0.path.points }
        ?? program.flatMap { program in
          try? program.strokes.map { try placement.applying(to: $0.path).points }
        }
      guard let paths else { return nil }
      if let camera = placement.cameraGeometry, let corners = cameraRegion,
        let minX = corners.map(\.x).min(), let maxX = corners.map(\.x).max(),
        let minY = corners.map(\.y).min() {
        let pixelScale = width / (maxX - minX)
        func screen(_ point: Point2<CameraPixelSpace>) -> CGPoint {
          CGPoint(x: rect.minX + (point.x - minX) * pixelScale,
            y: rect.minY + (point.y - minY) * pixelScale)
        }
        guard let projected = try? paths.map({ points in
          try points.map { screen(try camera.cameraFromMachine.applying(to: $0)) }
        }) else { return nil }
        // Material width is a conservative controller-coordinate envelope. It
        // does not establish a physical circular pen footprint in camera space.
        return .init(regionRect: rect, regionOutline: corners.map(screen), paths: projected,
          lineWidth: inkWidthMM * camera.maximumPixelsPerControllerUnit * pixelScale,
          screenScale: pixelScale)
      }
      return .init(regionRect: rect, paths: paths.map { points in points.map { point in
        CGPoint(x: rect.minX + (point.x - bounds.minX) * scale,
          y: rect.maxY - (point.y - bounds.minY) * scale)
      } }, lineWidth: inkWidthMM * scale, screenScale: scale)
    }
    // Reference fit has no claimed machine placement or actual millimeter size.
    guard let program else { return nil }
    let scale = min(width / program.fieldExtent.width, height / program.fieldExtent.height) * 0.9
    let origin = CGPoint(x: rect.midX - program.fieldExtent.width * scale / 2,
      y: rect.midY + program.fieldExtent.height * scale / 2)
    return .init(regionRect: rect, paths: program.strokes.map { stroke in stroke.path.points.map {
      CGPoint(x: origin.x + $0.x * scale, y: origin.y - $0.y * scale)
    } }, lineWidth: inkWidthMM * program.fieldExtent.height / 100 * scale, screenScale: scale)
  }
}

/// Screen-space drawing commands shared by cached and uncached presentation.
/// Separate paths preserve the original per-stroke compositing and rounded caps.
struct PortraitPlaneDrawing {
  let outline: Path
  let paths: [Path]
  let lineWidth: Double
  let pointCount: Int

  init?(preview: PortraitPlanePreview, size: CGSize) {
    guard let geometry = preview.geometry(in: size) else { return nil }
    outline = geometry.regionOutline.map { points in
      Path { path in
        if let first = points.first { path.move(to: first) }
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
      }
    } ?? Path(geometry.regionRect)
    paths = geometry.paths.map { points in
      Path { path in
        if let first = points.first { path.move(to: first) }
        for point in points.dropFirst() { path.addLine(to: point) }
      }
    }
    lineWidth = geometry.lineWidth
    pointCount = geometry.paths.reduce(0) { $0 + $1.count }
  }

  func draw(in context: inout GraphicsContext) {
    context.clip(to: outline)
    let style = SwiftUI.StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
    for path in paths { context.stroke(path, with: .color(.black), style: style) }
    context.stroke(outline, with: .color(.gray.opacity(0.5)), lineWidth: 1)
  }
}

/// One viewport-sized entry per mounted preview. Mutable cache state is confined
/// to the view's main actor; Canvas receives only immutable drawing commands.
@MainActor
final class PortraitPlanePreviewCache: ObservableObject {
  static let maximumPoints = 200_000
  static let maximumStrokes = 10_000
  private var key: PortraitPlanePreview.GeometryKey?
  private var size: CGSize?
  private var drawing: PortraitPlaneDrawing?
  private(set) var buildCount = 0
  private(set) var hitCount = 0
  var retainedPointCount: Int { drawing?.pointCount ?? 0 }

  func resolve(_ preview: PortraitPlanePreview, size: CGSize) -> PortraitPlaneDrawing? {
    let next = preview.geometryKey
    if key == next, self.size == size {
      hitCount += 1
      return drawing
    }
    buildCount += 1
    let result = PortraitPlaneDrawing(preview: preview, size: size)
    // Oversized drawings still paint in full, but never become retained buffers.
    if let result, result.pointCount <= Self.maximumPoints,
      result.paths.count <= Self.maximumStrokes {
      key = next
      self.size = size
      drawing = result
    } else {
      key = nil
      self.size = nil
      drawing = nil
    }
    return result
  }
}

struct PortraitPlaneProgramPreview: View {
  let preview: PortraitPlanePreview
  @StateObject private var cache: PortraitPlanePreviewCache

  init(preview: PortraitPlanePreview, cache: PortraitPlanePreviewCache? = nil) {
    self.preview = preview
    _cache = StateObject(wrappedValue: cache ?? PortraitPlanePreviewCache())
  }

  var body: some View {
    PortraitPlaneCachedCanvas(preview: preview, cache: cache).equatable()
      .background(.white)
      .accessibilityLabel("Portrait drawing plane preview")
      .accessibilityIdentifier("portrait.planePreview")
  }
}

/// Status-only parent updates do not invalidate the Canvas display list. Viewport
/// changes still reach GeometryReader, where the path cache checks the new size.
private struct PortraitPlaneCachedCanvas: View, Equatable {
  let preview: PortraitPlanePreview
  let cache: PortraitPlanePreviewCache

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.cache === rhs.cache && lhs.preview.geometryKey == rhs.preview.geometryKey
  }

  var body: some View {
    GeometryReader { geometry in
      let drawing = cache.resolve(preview, size: geometry.size)
      Canvas { context, _ in drawing?.draw(in: &context) }
    }
  }
}

extension PlotterApplicationRuntime {
  var portraitPlanePreviewSource: PortraitPlanePreviewSource {
    let record = drawingMaterials.activeRecord
    let applicable = record.map {
      $0.profile.qualification == .nominal ||
        ($0.profile.qualification != .unavailable && $0.applicability != nil
          && $0.applicability == currentMaterialApplicability)
    } ?? false
    return PortraitPlanePreviewSource(region: drawingDraftSnapshot.projection.externalFacts.drawableRegion,
      artworkPlan: drawingDraftSnapshot.artworkPlan, material: applicable ? record?.profile : nil,
      materialUnavailableReason: record != nil && !applicable ? "Active material is not applicable to the current setup." : nil)
  }
}
