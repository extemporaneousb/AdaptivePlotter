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
        return try application.preparedDestinationDrawing(ref, engine: engine)
      }, current: { [weak application] facts in
        try application?.preparedDestinationDrawing(facts.drawing, engine: facts.destination)?.facts
      })
  }
}
enum DrawingDestinationPreparationOutcome: Sendable {
  case prepared(DrawingPreparedTicket)
  case refused(DrawingDestinationRefusal, detail: String)
}
extension PlotterApplicationRuntime {
  /// String presentation is kept at the existing UI error edge; callers which
  /// reveal a preview retain the exact typed ticket through their final await.
  func prepareDestinationDrawing(_ drawing: Drawing, isStillCurrent: @escaping @MainActor () -> Bool = { true }) async -> String? {
    switch await prepareDestinationDrawingOutcome(drawing, isStillCurrent: isStillCurrent) {
    case .prepared: return nil
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
        return .prepared(ticket)
      case .refused(let reason):
        return .refused(reason, detail: "The drawing could not be prepared. Review the destination preview and readiness.")
      default: return .refused(.preparationUnavailable, detail: "Drawing preparation is unavailable.")
      }
    } catch { return .refused(.preparationUnavailable, detail: error.localizedDescription) }
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
      applicability: .hash(try JSONSerialization.data(withJSONObject: applicability, options: [.sortedKeys, .withoutEscapingSlashes])))
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
    showDestination: @escaping @MainActor (DrawingPreparedTicket) -> Void) async -> String? {
    let initial = lifetime()
    let current = { @MainActor in lifetime() == initial }
    let outcome = await application.prepareDestinationDrawingOutcome(drawing, isStillCurrent: current)
    guard current() else { return "Drawing handoff was cancelled." }
    switch outcome {
    case .prepared(let ticket):
      guard application.preparedDrawingIsCurrent(ticket) else { return "Drawing preparation has changed. Review the current preview." }
      showDestination(ticket)
      return nil
    case .refused(_, let detail): return detail
    }
  }
}

/// Borrowed bindings belonging to the existing window. This value owns neither
/// selection nor preferences; all destination reveals share this exact action.
typealias DrawingDestinationReveal = @MainActor (DrawingPreparedTicket) -> Bool
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
  func reveal(_ ticket: DrawingPreparedTicket, application: PlotterApplicationRuntime) -> Bool {
    guard application.preparedDrawingIsCurrent(ticket) else { return false }
    showDestination(reference: ticket.facts.drawing)
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
