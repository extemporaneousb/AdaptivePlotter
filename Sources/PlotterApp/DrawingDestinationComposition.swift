import Foundation
import DrawingLibrary
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import SwiftUI
import PlotterModel

@MainActor enum DrawingDestinationComposition {
  static func make(_ application: PlotterApplicationRuntime,
    returnDirectory: URL = DrawingDestinationFiles.defaultRoot.appendingPathComponent("results")) -> DrawingDestinationService {
    let library = application.portraitStudio.sketches.library
    return DrawingDestinationService(library: library,
      returnDirectory: returnDirectory,
      prepare: { [weak application] ref, engine, isStillCurrent in
        guard let application else { return nil }
        let drawing = try await library.drawing(ref)
        guard isStillCurrent(), await application.projectDrawing(drawing, isStillCurrent: isStillCurrent) == nil else { return nil }
        if application.canShowUnplacedDrawing(ref) { return .referencePreview(ref) }
        return try application.preparedDestinationDrawing(ref, engine: engine).map { .planned($0) }
      }, current: { [weak application] facts in
        try application?.preparedDestinationDrawing(facts.drawing, engine: facts.destination)?.facts
      }, control: DrawingRunDestinationControl(runtime: application.drawingRunRuntime),
      resultSource: application.drawingEvidencePort)
  }
}
enum DrawingDestinationPreview: Sendable {
  case prepared(DrawingPreparedTicket)
  case unplaced(DrawingRef)

  var reference: DrawingRef {
    switch self {
    case .prepared(let ticket): ticket.facts.drawing
    case .unplaced(let ref): ref
    }
  }
}
enum DrawingDestinationPreparationOutcome: Sendable {
  case preview(DrawingDestinationPreview)
  case refused(DrawingDestinationRefusal, detail: String)
}
extension PlotterApplicationRuntime {
  /// String presentation is kept at the existing UI error edge; callers which
  /// reveal a preview retain the exact typed ticket through their final await.
  func prepareDestinationDrawing(_ drawing: Drawing, isStillCurrent: @escaping @MainActor () -> Bool = { true }) async -> String? {
    switch await prepareDestinationDrawingOutcome(drawing, isStillCurrent: isStillCurrent) {
    case .preview: return nil
    case .refused(_, let detail): return detail
    }
  }
  func prepareDestinationDrawingOutcome(_ drawing: Drawing,
    isStillCurrent: @escaping @MainActor () -> Bool = { true }) async -> DrawingDestinationPreparationOutcome {
    let selection = portraitStudio.selectionEpoch
    let collectionSelection = portraitStudio.sketches.selectionEpoch
    let revision = drawingDraftSnapshot.projection.draftRevision
    let context = DrawingPreparationContext(mayBegin: { [weak self] in
      guard let self else { return false }
      return self.portraitStudio.selectionEpoch == selection
        && self.portraitStudio.sketches.selectionEpoch == collectionSelection
        && self.drawingDraftSnapshot.projection.draftRevision == revision
    }, isStillCurrent: isStillCurrent)
    do {
      let retained = try await portraitStudio.sketches.retain(drawing, reason: "prepare-destination")
      guard isStillCurrent(), let ref = retained.reference else {
        return .refused(.preparationUnavailable, detail: "Drawing handoff was cancelled.")
      }
      switch try await drawingDestination.handle(.prepare(ref), context: context) {
      case .prepared(let ticket):
        guard isStillCurrent(), preparedDrawingIsCurrent(ticket) else {
          return .refused(.stalePreview, detail: "Drawing preparation has changed. Review the current preview.")
        }
        return .preview(.prepared(ticket))
      case .referencePreview(let ref):
        guard isStillCurrent(), canShowUnplacedDrawing(ref) else {
          return .refused(.stalePreview, detail: "Drawing selection changed.")
        }
        return .preview(.unplaced(ref))
      case .refused(let reason):
        return .refused(reason, detail: "The drawing could not be prepared. Review the destination preview and readiness.")
      default: return .refused(.preparationUnavailable, detail: "Drawing preparation is unavailable.")
      }
    } catch { return .refused(.preparationUnavailable, detail: error.localizedDescription) }
  }
  func canShowUnplacedDrawing(_ ref: DrawingRef) -> Bool {
    let draft = drawingDraftSnapshot
    guard drawingDestinationRecoveryAdmissionIsOpen, let artwork = portraitStudio.projectedDrawing,
      artwork.reference == ref, draft.authoredProgram == artwork.program, draft.plan == nil,
      !draft.projection.externalFacts.runInProgress else { return false }
    return draft.planningRefusal?.reason == .registrationUnavailable || draft.planningRefusal?.reason == .drawableRegionUnavailable
  }
  func destinationPreviewIsCurrent(_ preview: DrawingDestinationPreview) -> Bool {
    switch preview {
    case .prepared(let ticket): preparedDrawingIsCurrent(ticket)
    case .unplaced(let ref): canShowUnplacedDrawing(ref)
    }
  }
  func preparedDrawingIsCurrent(_ ticket: DrawingPreparedTicket) -> Bool {
    guard drawingDestinationRecoveryAdmissionIsOpen else { return false }
    return (try? preparedDestinationDrawing(ticket.facts.drawing, engine: ticket.facts.destination)?.facts) == ticket.facts
  }
  fileprivate func preparedDestinationDrawing(_ ref: DrawingRef, engine: UUID) throws -> DrawingPreparation? {
    let snapshot = drawingDraftSnapshot
    guard portraitStudio.projectedDrawing?.reference == ref, let plan = snapshot.plan,
      let authored = snapshot.authoredProgram, portraitStudio.projectedDrawing?.program == authored,
      snapshot.artworkPlan?.sourceProgramContentHash == authored.contentHash else { return nil }
    let facts = snapshot.projection.externalFacts
    let encoder = DrawingArtifactCoding.encoder()
    func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: encoder.encode(value), options: .fragmentsAllowed) }
    let applicability: [String: Any] = ["environment": try object(facts.environment),
      "tool": try object(facts.toolAssemblyRevision), "paper": try object(facts.paper),
      "registration": try object(facts.registrationRevisionID), "opticalConfiguration": try object(facts.opticalConfiguration),
      "material": facts.materialContextHash?.description ?? "unavailable", "runInProgress": facts.runInProgress,
      "terminalRequiresNewPlan": facts.terminalRequiresNewPlan, "archiveAvailable": facts.drawingArchiveIsAvailable]
    let options = DrawingDestinationOptions(drawBorder: snapshot.drawBorder,
      sheetPlacementIsCurrent: snapshot.sheetPlacementIsCurrent, paperCoverageIsCurrent: snapshot.paperCoverageIsCurrent,
      readiness: String(describing: drawingRunSnapshot?.readiness),
      applicability: .hash(try JSONSerialization.data(withJSONObject: applicability, options: [.sortedKeys, .withoutEscapingSlashes])),
      environment: facts.environment == .live ? .live : .simulation)
    return try .init(drawing: ref, destination: engine, draftRevision: snapshot.projection.draftRevision.rawValue,
      plan: plan, options: options)
  }
}

/// Lifetime of the actual embedded caller, separate from draft-owner revisions.
struct DrawingDestinationHandoffLifetime: Equatable {
  let route: DrawingLibraryRoute
  let studioIsPresented: Bool
  let reviewerIsPresented: Bool
}
@MainActor enum DrawingDestinationHandoff {
  static func perform(_ drawing: Drawing, application: PlotterApplicationRuntime,
    lifetime: @escaping @MainActor () -> DrawingDestinationHandoffLifetime,
    showDestination: @escaping @MainActor (DrawingDestinationPreview) -> Void) async -> String? {
    let initial = lifetime()
    let current = { @MainActor in lifetime() == initial }
    let outcome = await application.prepareDestinationDrawingOutcome(drawing, isStillCurrent: current)
    guard current() else { return "Drawing handoff was cancelled." }
    switch outcome {
    case .preview(let preview):
      guard application.destinationPreviewIsCurrent(preview) else { return "Drawing preparation has changed. Review the current preview." }
      showDestination(preview)
      return nil
    case .refused(_, let detail): return detail
    }
  }
}

/// Borrowed bindings belonging to the existing window. This value owns neither
/// selection nor preferences; all destination reveals share this exact action.
typealias DrawingDestinationReveal = @MainActor (DrawingDestinationPreview) -> Bool
@MainActor struct DrawingDestinationWindowPresentation {
  let route: Binding<DrawingLibraryRoute>
  let layout: Binding<WorkbenchLayoutState>
  let reviewer: Binding<Bool>
  func showDestination(reference: DrawingRef? = nil) {
    reviewer.wrappedValue = false
    var next = route.wrappedValue
    if let reference { next.showDrawing(reference) }
    next.workspace = .plotter
    route.wrappedValue = next
    layout.wrappedValue.setPresented(.portraitStudio, false)
    layout.wrappedValue.setPresented(.drawing, true)
  }
  func reveal(_ preview: DrawingDestinationPreview, application: PlotterApplicationRuntime) -> Bool {
    guard application.destinationPreviewIsCurrent(preview) else { return false }
    showDestination(reference: preview.reference)
    return true
  }
  func revealAction(application: PlotterApplicationRuntime) -> DrawingDestinationReveal {
    { [weak application] ticket in
      guard let application else { return false }
      return self.reveal(ticket, application: application)
    }
  }
  func restoreSavedWorkspace(openPhoto: @MainActor (PhotoRef) async -> String?,
    photoResult: @MainActor (String?) -> Void) async {
    let restored = route.wrappedValue
    reviewer.wrappedValue = restored.workspace == .library
    if restored.workspace == .drawingStudio { layout.wrappedValue.setPresented(.portraitStudio, true) }
    if restored.workspace == .drawingStudio, let reference = restored.photo {
      let failure = await openPhoto(reference)
      guard route.wrappedValue.workspace == restored.workspace, route.wrappedValue.photo == reference else { return }
      photoResult(failure)
    }
  }
}

import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterRuntime
import PlotterUI

/// Immutable native capability captured by the actual public sink. Mutable
/// pending/cancel/dispatch state lives only in PlotterDrawingRunRuntime.
@MainActor struct NativeDrawingIssuancePreparation: PlotterDrawingRunIssuancePreparation {
  weak var application: PlotterApplicationRuntime?
  let runtime: PlotterDrawingRunRuntime
  let original: PlotterDrawingRunSubmission
  let draft: PlotterDrawingDraftSnapshot
  let facts: PlotterDrawingDraftExternalFacts
  let drawing: Drawing?
  let selectionEpoch: UInt64
  let collectionSelectionEpoch: UInt64
  nonisolated let requestStamp: ExchangeDigest

  init(application: PlotterApplicationRuntime, runtime: PlotterDrawingRunRuntime,
    original: PlotterDrawingRunSubmission, requestStamp: ExchangeDigest) {
    self.application = application; self.runtime = runtime; self.original = original; self.requestStamp = requestStamp
    draft = application.drawingDraftSnapshot; facts = application.drawingDraftExternalFacts
    selectionEpoch = application.portraitStudio.selectionEpoch
    collectionSelectionEpoch = application.portraitStudio.sketches.selectionEpoch
    if let selected = application.portraitStudio.projectedDrawing, selected.program == draft.authoredProgram {
      // A retained unsupported Drawing must never be replaced by a builtin
      // source-free receipt merely because it has renderable geometry.
      drawing = selected
    } else if let execution = draft.program, let existing = application.authoredDrawing(for: execution) { drawing = existing }
    else if let authored = draft.authoredProgram { drawing = try? application.sourceFreeDrawing(authored) }
    else { drawing = nil }
  }
  nonisolated static func stamp(_ request: PlotterUIRequest) -> ExchangeDigest {
    let parts = [request.id.rawValue.uuidString, String(request.uiRevision.rawValue), request.actionID.rawValue, "drawingRun.start"]
      + request.runtimeRevisions.sorted { $0.owner < $1.owner }.flatMap { [$0.owner, $0.token] }
    return .hash(Data(parts.map { "\($0.utf8.count):" + $0 }.joined().utf8))
  }
  func matchesCurrent() -> Bool {
    guard let application, application.drawingDestinationRecoveryAdmissionIsOpen,
      application.drawingFrameEditRunUnavailableReason == nil,
      application.portraitStudio.selectionEpoch == selectionEpoch,
      application.portraitStudio.sketches.selectionEpoch == collectionSelectionEpoch,
      application.drawingDraftSnapshot.authoredProgram == draft.authoredProgram,
      application.drawingDraftSnapshot.program == draft.program,
      application.drawingDraftSnapshot.plan == draft.plan,
      application.drawingDraftSnapshot.placementID == draft.placementID,
      application.drawingDraftSnapshot.drawBorder == draft.drawBorder else { return false }
    let a = facts.revisions, b = application.drawingDraftExternalFacts.revisions
    // Own pending/active publication changes runInProgress and Draft revision.
    // Every actual source/placement/material/paper/calibration pin remains exact.
    return a.environment == b.environment && a.placementGuide == b.placementGuide
      && a.interactiveLearningIsComplete == b.interactiveLearningIsComplete
      && a.registrationRevisionID == b.registrationRevisionID && a.opticalConfiguration == b.opticalConfiguration
      && a.drawableRegion == b.drawableRegion && a.drawingBorderBounds == b.drawingBorderBounds
      && a.toolAssemblyRevision == b.toolAssemblyRevision && a.paper == b.paper
      && a.materialContextHash == b.materialContextHash
      && a.drawingArchiveIsAvailable == b.drawingArchiveIsAvailable
      && facts.cameraSource == application.drawingDraftExternalFacts.cameraSource
      && facts.cameraConfigurationID == application.drawingDraftExternalFacts.cameraConfigurationID
  }
  func currentFacts() async -> PlotterDrawingRunExternalFacts {
    guard let application, matchesCurrent() else { return unavailableFacts() }
    let current = await application.currentDrawingRunFacts(for: original.projection.environment)
    guard matchesCurrent(), let plan = current.plan, plan.plan == draft.plan,
      let identity = original.projection.planIdentity else { return unavailableFacts() }
    let frozen = PlotterDrawingRunPlan(draftRevision: identity.draftRevision, program: plan.program,
      placementID: plan.placementID, plan: plan.plan, evidenceRole: plan.evidenceRole, paperCoverage: plan.paperCoverage,
      registration: plan.registration, candidate: plan.candidate, materialProfile: plan.materialProfile,
      materialApplicability: plan.materialApplicability, paperStock: plan.paperStock)
    return .init(environment: current.environment, interactiveLearningIsComplete: current.interactiveLearningIsComplete,
      plan: frozen, paperCoverageIsCurrent: current.paperCoverageIsCurrent, displayedFrame: current.displayedFrame,
      interpreter: current.interpreter, penActuationProfile: current.penActuationProfile,
      physicalPositionUnavailableReason: current.physicalPositionUnavailableReason, acceptedMovementBounds: current.acceptedMovementBounds)
  }
  private func unavailableFacts() -> PlotterDrawingRunExternalFacts {
    .init(environment: original.projection.environment, interactiveLearningIsComplete: false, plan: nil,
      paperCoverageIsCurrent: false, displayedFrame: nil, interpreter: nil, penActuationProfile: .initialDefaults)
  }
  func prepareAndSubmit(pendingID: UUID, submission: PlotterDrawingRunSubmission) async throws -> DrawingDestinationReply {
    guard let drawing else { throw DrawingDestinationRefusal.preparationUnavailable }
    guard drawing.capabilities.supported.contains(.plot) else { throw DrawingDestinationRefusal.unsupportedDrawing }
    guard submission == original, matchesCurrent(), let application,
      let plan = draft.plan, let identity = original.projection.planIdentity else { throw DrawingDestinationRefusal.stalePreview }
    let retained = try await application.portraitStudio.sketches.retain(drawing, reason: "plot")
    guard matchesCurrent(), let ref = retained.reference else { throw DrawingDestinationRefusal.stalePreview }
    let identityPair = try await application.drawingDestination.nativeIdentity()
    guard matchesCurrent() else { throw DrawingDestinationRefusal.stalePreview }
    // Options are frozen at the original click. Busy/readiness publication is
    // not encoded as a new external requirement or parsed from presentation.
    let encoder = DrawingArtifactCoding.encoder()
    let provenance = try encoder.encode(NativeApplicability(environment: facts.revisions.environment,
      tool: facts.revisions.toolAssemblyRevision, paper: facts.revisions.paper,
      registration: facts.revisions.registrationRevisionID, material: facts.revisions.materialContextHash?.description))
    let options = DrawingDestinationOptions(drawBorder: draft.drawBorder,
      sheetPlacementIsCurrent: draft.sheetPlacementIsCurrent, paperCoverageIsCurrent: draft.paperCoverageIsCurrent,
      readiness: "native-request", applicability: .hash(provenance),
      environment: facts.revisions.environment == .live ? .live : .simulation)
    let preparation = try DrawingPreparation(drawing: ref, destination: identityPair.engine,
      draftRevision: identity.draftRevision.rawValue, plan: plan, options: options)
    let context = DrawingPreparationContext(isStillCurrent: { matchesCurrent() }, nativePreparation: preparation)
    guard case .prepared(let ticket) = try await application.drawingDestination.handle(.prepare(ref), context: context) else {
      throw DrawingDestinationRefusal.preparationUnavailable
    }
    guard matchesCurrent() else { throw DrawingDestinationRefusal.stalePreview }
    let adapter = NativeDrawingAdmission(preparation: self, pendingID: pendingID, drawing: retained)
    return try await application.drawingDestination.handle(.submit(.init(namespace: identityPair.namespace,
      request: original.requestID.rawValue), ticket), admission: adapter)
  }
  private struct NativeApplicability: Encodable {
    let environment: PlotterEnvironment
    let tool: ToolAssemblyRevision
    let paper: PaperRevisionContext
    let registration: LearningArtifactRevisionID?
    let material: String?
  }
}
@MainActor private struct NativeDrawingAdmission: DrawingDestinationIssuanceAdmission {
  let preparation: NativeDrawingIssuancePreparation
  let pendingID: UUID
  let drawing: Drawing
  func isCurrent(_ ticket: DrawingPreparedTicket) async -> Bool {
    preparation.matchesCurrent() && drawing.reference == ticket.facts.drawing
      && preparation.draft.plan?.revisionID == ticket.facts.planID
      && preparation.draft.plan?.contentHash.description == ticket.facts.planHash.description
  }
  func admit(_ binding: DrawingJobIssuance, publication: any DrawingJobPublication) async throws {
    guard let program = preparation.draft.program, let candidate = drawing.executionReference(for: program) else {
      throw DrawingDestinationRefusal.preparationUnavailable
    }
    try await preparation.runtime.continuePreparedIssuance(pendingID: pendingID, binding: binding,
      candidate: candidate, publication: publication)
  }
}
private struct DrawingRunDestinationControl: DrawingDestinationJobControl {
  let runtime: PlotterDrawingRunRuntime
  func cancel(_ binding: DrawingJobIssuance) async -> DrawingJobCancellation { await runtime.cancelIssuance(binding) }
  func lookup(_ binding: DrawingJobIssuance) async -> DrawingRawIssuanceLookup { await runtime.lookupIssuance(binding) }
  func publishedSettlement(_ binding: DrawingJobIssuance, run: UUID) async { await runtime.acknowledgeJobSettlement(binding, run: run) }
}
