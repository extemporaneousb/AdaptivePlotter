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

  var actualDrawingHeightMM: Double? {
    guard evidence?.mode == .planned, let program, let placement = evidence?.placement else { return nil }
    return program.fieldExtent.height * placement.uniformScale
  }
  var actualDrawingWidthMM: Double? {
    guard evidence?.mode == .planned, let program, let placement = evidence?.placement else { return nil }
    return program.fieldExtent.width * placement.uniformScale
  }
  var aspectRatio: Double {
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
    return String(format: "Artwork %.1f × %.1f · ", width, height) + region
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
    guard let program, size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
    let ratio = aspectRatio
    let width = min(size.width, size.height * ratio), height = width / ratio
    let rect = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    if evidence?.mode == .planned, let bounds = evidence?.region?.effectiveBounds,
      let placement = evidence?.placement {
      let scale = width / (bounds.maxX - bounds.minX)
      let paths = plannedStrokes?.map { $0.path.points }
        ?? (try? program.strokes.map { try placement.applying(to: $0.path).points })
      guard let paths else { return nil }
      return .init(regionRect: rect, paths: paths.map { points in points.map { point in
        CGPoint(x: rect.minX + (point.x - bounds.minX) * scale,
          y: rect.maxY - (point.y - bounds.minY) * scale)
      } }, lineWidth: inkWidthMM * scale, screenScale: scale)
    }
    // Reference fit has no claimed machine placement or actual millimeter size.
    let scale = min(width / program.fieldExtent.width, height / program.fieldExtent.height) * 0.9
    let origin = CGPoint(x: rect.midX - program.fieldExtent.width * scale / 2,
      y: rect.midY + program.fieldExtent.height * scale / 2)
    return .init(regionRect: rect, paths: program.strokes.map { stroke in stroke.path.points.map {
      CGPoint(x: origin.x + $0.x * scale, y: origin.y - $0.y * scale)
    } }, lineWidth: inkWidthMM * program.fieldExtent.height / 100 * scale, screenScale: scale)
  }
}

struct PortraitPlaneProgramPreview: View {
  let preview: PortraitPlanePreview
  var body: some View {
    Canvas { context, size in
      guard let geometry = preview.geometry(in: size) else { return }
      context.clip(to: Path(geometry.regionRect))
      for points in geometry.paths {
        var path = Path()
        for (index, point) in points.enumerated() {
          if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        context.stroke(path, with: .color(.black),
          style: SwiftUI.StrokeStyle(lineWidth: geometry.lineWidth, lineCap: .round, lineJoin: .round))
      }
      context.stroke(Path(geometry.regionRect), with: .color(.gray.opacity(0.5)), lineWidth: 1)
    }
    .background(.white)
    .accessibilityLabel("Portrait drawing plane preview")
    .accessibilityIdentifier("portrait.planePreview")
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
