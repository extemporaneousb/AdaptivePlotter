import EpisodeCore
import Foundation

public struct PlotterEpisodeReducer: EpisodeReducing {
  public init() {}

  public func reduce(
    state: PlotterEpisodeState,
    event: PlotterEpisodeEvent
  ) -> EpisodeReduction<PlotterEpisodeState, PlotterEffect> {
    guard event.episodeID == state.episodeID, event.preStateRevision == state.revision else {
      return EpisodeReduction(state: state)
    }

    var phase = state.phase
    var activeDrawingModelRevisionID = state.activeDrawingModelRevisionID
    let selectedPoint = state.selectedPoint
    var exactPointSelection = state.exactPointSelection
    var learningIsEnabled = state.learningIsEnabled
    var activeRequestID = state.activeRequestID
    var activeIntent = state.activeIntent
    var pendingEffectID = state.pendingEffectID
    var activeEffectProgress = state.activeEffectProgress
    var lastTerminalEffect = state.lastTerminalEffect
    var observationIDs = state.observationIDs
    var measurementIDs = state.measurementIDs
    var acceptedEvidenceIDs = state.acceptedEvidenceIDs
    var outcome = state.outcome
    var assessment = state.assessment
    var lastRefusal = state.lastRefusal
    var effects: [PlotterEffect] = []

    switch event.payload {
    case let .intentAccepted(accepted):
      activeRequestID = accepted.requestID
      lastRefusal = nil
      if let effect = accepted.effect(episodeID: state.episodeID) {
        activeIntent = accepted.intent
        pendingEffectID = effect.context.effectID
        activeEffectProgress = nil
        effects = [effect]
      } else {
        activeRequestID = nil
        activeIntent = nil
        pendingEffectID = nil
        activeEffectProgress = nil
      }
      switch accepted.intent {
      case .session:
        phase = .preparing
      case .observation:
        phase = .preparing
      case let .pointSelection(.stage(request)):
        exactPointSelection = PlotterExactPointSelectionState(
          request: request,
          selectedPoints: [],
          phase: .collecting
        )
      case let .pointSelection(.select(submission)):
        if exactPointSelection.request?.id == submission.selectionID {
          let points = exactPointSelection.selectedPoints + [submission.point]
          let accepted = points.count == exactPointSelection.request?.requiredPointCount
          exactPointSelection = PlotterExactPointSelectionState(
            request: exactPointSelection.request,
            selectedPoints: points,
            phase: accepted ? .accepted : .collecting
          )
        }
      case let .pointSelection(.undo(selectionID)):
        if exactPointSelection.request?.id == selectionID,
          !exactPointSelection.selectedPoints.isEmpty
        {
          exactPointSelection = PlotterExactPointSelectionState(
            request: exactPointSelection.request,
            selectedPoints: Array(exactPointSelection.selectedPoints.dropLast()),
            phase: .collecting
          )
        }
      case let .pointSelection(.clear(selectionID)):
        if exactPointSelection.request?.id == selectionID {
          exactPointSelection = PlotterExactPointSelectionState(
            request: exactPointSelection.request,
            selectedPoints: [],
            phase: .collecting
          )
        }
      case let .pointSelection(.cancel(selectionID)):
        if exactPointSelection.request?.id == selectionID {
          exactPointSelection = .idle
        }
      case let .pointSelection(.setContinuation(selectionID, isActive)):
        if exactPointSelection.request?.id == selectionID {
          exactPointSelection = PlotterExactPointSelectionState(
            request: exactPointSelection.request,
            selectedPoints: exactPointSelection.selectedPoints,
            phase: isActive ? .continuing : .accepted,
            continuationIsActive: isActive
          )
        }
      case .manualMotion:
        phase = .executing
      case .drawing(.execute):
        phase = .executing
      case .drawing(.captureResult):
        phase = .preparing
      case .learning(.captureSample), .learning(.acceptModel):
        phase = .preparing
      case let .learning(.setEnabled(isEnabled)):
        learningIsEnabled = isEnabled
        if !isEnabled { exactPointSelection = .idle }
      case .evidence(.accept):
        break
      case .evidence(.assess):
        phase = .assessing
      }

    case let .intentRefused(refusal):
      lastRefusal = refusal
      activeRequestID = nil
      activeIntent = nil
      pendingEffectID = nil
      activeEffectProgress = nil

    case let .effectProgressed(progress):
      if progress.episodeID == state.episodeID,
         progress.requestID == activeRequestID,
         progress.intent == activeIntent,
         progress.effectID == pendingEffectID {
        activeEffectProgress = progress
      }

    case let .effectResult(result):
      activeRequestID = nil
      activeIntent = nil
      pendingEffectID = nil
      activeEffectProgress = nil
      lastTerminalEffect = PlotterEffectTerminalRecord(
        settledAt: event.recordedAt,
        result: result
      )
      switch result {
      case let .completed(_, output):
        switch output {
        case .sessionPrepared:
          phase = .ready
        case .sessionClosed:
          phase = .terminal
        case .frameCaptured:
          phase = .awaitingEvidence
        case .motionSettled:
          phase = .ready
        case .penSettled:
          phase = .ready
        case .drawingExecuted:
          phase = .awaitingEvidence
        case let .modelActivated(revisionID):
          activeDrawingModelRevisionID = revisionID
          phase = .ready
        }
      case .refused, .cancelled, .cancelledAfterSettlement, .timedOut,
        .evidenceUnavailable, .failed:
        phase = .ready
      case .ambiguous:
        phase = .awaitingEvidence
      }

    case let .observationRecorded(observation):
      appendUnique(observation.context.id, to: &observationIDs)

    case let .measurementRecorded(measurement):
      appendUnique(measurement.context.id, to: &measurementIDs)

    case let .evidenceDecided(decision):
      switch decision {
      case let .accepted(evidence):
        appendUnique(evidence.id, to: &acceptedEvidenceIDs)
        phase = .ready
      case .refused:
        break
      }

    case let .outcomeRecorded(recordedOutcome):
      outcome = recordedOutcome
      phase = .assessing

    case let .assessmentRecorded(recordedAssessment):
      assessment = recordedAssessment
      phase = .terminal
    }

    let reduced = PlotterEpisodeState(
      episodeID: state.episodeID,
      revision: event.postStateRevision,
      canonicalDigest: event.postStateDigest,
      phase: phase,
      permittedIntentFamilies: state.permittedIntentFamilies,
      currentPlanRevisionID: state.currentPlanRevisionID,
      activeDrawingModelRevisionID: activeDrawingModelRevisionID,
      selectedPoint: selectedPoint,
      exactPointSelection: exactPointSelection,
      learningIsEnabled: learningIsEnabled,
      activeRequestID: activeRequestID,
      activeIntent: activeIntent,
      pendingEffectID: pendingEffectID,
      activeEffectProgress: activeEffectProgress,
      lastTerminalEffect: lastTerminalEffect,
      observationIDs: observationIDs,
      measurementIDs: measurementIDs,
      acceptedEvidenceIDs: acceptedEvidenceIDs,
      outcome: outcome,
      assessment: assessment,
      lastRefusal: lastRefusal,
      lastCommittedAt: event.recordedAt
    )
    return EpisodeReduction(state: reduced, effects: effects)
  }
}

private func appendUnique<Value: Equatable>(_ value: Value, to values: inout [Value]) {
  if !values.contains(value) {
    values.append(value)
  }
}
