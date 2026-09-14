import Foundation
import PlotterRuntime

enum AxisMetricLearningTransitionError: Error {
  case persistenceUnavailable
  case staleProposal
  case incompleteReset(String)
  case evidenceRejected(String)
}

/// Recovery uses the existing immutable drawing archive and canonical Learning
/// persistence port. It never contacts a controller or replays settings writes.
enum AxisMetricLearningTransition {
  static func replacingGeometry(in identity: LearningPathSemanticIdentity,
    with geometry: MachineGeometryIdentity) -> LearningPathSemanticIdentity {
    LearningPathSemanticIdentity(machineGeometry: geometry,
      toolAssembly: identity.toolAssembly, penContactProfile: identity.penContactProfile,
      paperInstance: identity.paperInstance, paperContactPlane: identity.paperContactPlane,
      cameraMountRevision: identity.cameraMountRevision,
      cameraReframingRevision: identity.cameraReframingRevision)
  }

  static func reconcile(archive: DrawingRunEvidenceStoreLoadResult,
    identity: LearningPathSemanticIdentity, persistence: any PlotterApplicationStatePersistencePort
  ) throws -> LearningPathSemanticIdentity {
    let evidence: DrawingRunEvidenceArchive
    switch archive {
    case .absent: return identity
    case .rejected(let reason): throw AxisMetricLearningTransitionError.evidenceRejected(String(describing: reason))
    case .loaded(let value): evidence = value
    }
    guard let attempt = evidence.axisCalibrationAttempts.last else { return identity }
    let proposal = attempt.proposal
    guard identity.machineGeometry == proposal.oldMachineGeometry
      || identity.machineGeometry == proposal.proposedMachineGeometry else { return identity }
    let target = replacingGeometry(in: identity, with: proposal.proposedMachineGeometry)
    let stored = persistence.loadAcceptedLearningPathCheckpoint()
    let prefixAlreadyPublished: Bool
    if case .loaded(let checkpoint) = stored {
      prefixAlreadyPublished = checkpoint.semanticIdentity.machineGeometry == proposal.proposedMachineGeometry
    } else { prefixAlreadyPublished = false }
    if !prefixAlreadyPublished, identity.machineGeometry == proposal.oldMachineGeometry,
      let terminal = evidence.axisCalibrationTerminals.first(where: { $0.proposalID == proposal.proposalID }),
      terminal.outcome.attemptedCommands.isEmpty,
      terminal.outcome.status == .refused || terminal.outcome.status == .cancelled {
      // A proven refusal before writes and before identity publication retains
      // the former Learning package. An interrupted reservation is different.
      return identity
    }
    let needsPrefix: Bool
    switch stored {
    case .loaded(let checkpoint): needsPrefix = checkpoint.semanticIdentity.machineGeometry == proposal.oldMachineGeometry
    case .absent: needsPrefix = identity.machineGeometry == proposal.oldMachineGeometry
    case .rejected(let reason): throw AxisMetricLearningTransitionError.evidenceRejected(reason)
    }
    if needsPrefix {
      guard let source = evidence.axisMetricMeasurements.first(where: { $0.measurementID == proposal.measurementID })?.sourceCheckpoint else {
        throw AxisMetricLearningTransitionError.staleProposal
      }
      let compatiblePen = replacingGeometry(in: source.semanticIdentity,
        with: proposal.proposedMachineGeometry) == target
      let prefix = try AcceptedLearningPathCheckpoint(semanticIdentity: target,
        penInteraction: compatiblePen ? source.penInteraction : nil)
      try persistence.saveAcceptedLearningPathCheckpoint(prefix)
    }
    if identity.machineGeometry != target.machineGeometry {
      try persistence.persistMachineGeometryIdentity(target.machineGeometry)
    }
    return target
  }
}
