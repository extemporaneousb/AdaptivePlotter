import Foundation
import PlotterModel
@testable import PlotterRuntime
import Testing

@Suite("Learning artifact revisions and attempt aggregates")
struct LearningArtifactsTests {
  @Test("successful replacement is atomic and supersedes the old revision")
  func successfulReplacement() throws {
    var graph = LearningDependencyGraph()
    let old = revision(kind: .penInteraction)
    let firstCommit = try graph.commitReplacement(old)
    let replacement = revision(kind: .penInteraction)
    let commit = try graph.commitReplacement(replacement)

    #expect(firstCommit.currentRevision.state == .current)
    #expect(commit.currentRevision.id == replacement.id)
    #expect(commit.supersededRevisionID == old.id)
    #expect(graph.currentRevision(for: .penInteraction)?.id == replacement.id)
    #expect(graph.revision(id: old.id)?.state == .superseded)
  }

  @Test("unsuccessful replacement does not manufacture a current result")
  func unsuccessfulReplacement() throws {
    var graph = LearningDependencyGraph()
    let accepted = revision(kind: .clearPose)
    _ = try graph.commitReplacement(accepted)

    for disposition in [
      ExerciseAttemptDisposition.failed("analysis failed"),
      .cancelled,
      .ambiguous("write accepted but settlement unknown"),
    ] {
      let candidate = LearningArtifactRevision(
        kind: .clearPose,
        attemptID: ExerciseAttemptID(),
        disposition: disposition
      )
      #expect(throws: LearningDependencyGraphError.unsuccessfulReplacement(disposition)) {
        try graph.commitReplacement(candidate)
      }
      #expect(graph.currentRevision(for: .clearPose)?.id == accepted.id)
      #expect(graph.revision(id: accepted.id)?.state == .current)
    }
  }

  @Test("Pen Interaction replacement retains independent boundary observations")
  func penReplacementRetainsIndependentBoundary() throws {
    var graph = LearningDependencyGraph()
    let pen = revision(kind: .penInteraction)
    let boundary = revision(kind: .boundaryObservation(.positiveX))
    _ = try graph.commitReplacement(pen)
    _ = try graph.commitReplacement(boundary)

    let commit = try graph.commitReplacement(revision(kind: .penInteraction))

    #expect(commit.invalidatedRevisionIDs.isEmpty)
    #expect(graph.currentRevision(for: .boundaryObservation(.positiveX))?.id == boundary.id)
  }

  @Test("Clear pose replacement invalidates only drawing artifacts that consumed it")
  func clearPoseReplacementInvalidatesConsumers() throws {
    var graph = LearningDependencyGraph()
    let clear = revision(kind: .clearPose)
    let boundary = revision(kind: .boundaryObservation(.negativeY))
    _ = try graph.commitReplacement(clear)
    _ = try graph.commitReplacement(boundary)
    let baseline = revision(kind: .preTargetClearViewBaseline, consumes: [clear.id])
    _ = try graph.commitReplacement(baseline)
    let target = revision(kind: .visibilityTargetExecution, consumes: [baseline.id])
    _ = try graph.commitReplacement(target)

    let commit = try graph.commitReplacement(revision(kind: .clearPose))

    #expect(commit.invalidatedRevisionIDs == [baseline.id, target.id])
    #expect(graph.currentRevision(for: .boundaryObservation(.negativeY))?.id == boundary.id)
  }

  @Test("target-anchored trial baseline replacement invalidates only its consuming trial chain")
  func targetAnchoredBaselineReplacementInvalidatesTrial() throws {
    var graph = LearningDependencyGraph()
    let groupA = AttemptGroupIdentity(rawValue: "trial-a")
    let groupB = AttemptGroupIdentity(rawValue: "trial-b")
    let baselineA = revision(kind: .targetAnchoredTrialBaseline(groupA))
    let baselineB = revision(kind: .targetAnchoredTrialBaseline(groupB))
    _ = try graph.commitReplacement(baselineA)
    _ = try graph.commitReplacement(baselineB)
    let line = revision(kind: .lineExecution(groupA), consumes: [baselineA.id])
    let post = revision(kind: .postLineFrame(groupA), consumes: [line.id])
    let ink = revision(kind: .inkObservation(groupA), consumes: [baselineA.id, post.id])
    let residual = revision(kind: .residual(groupA), consumes: [ink.id])
    let comparison = revision(kind: .comparison(groupA), consumes: [residual.id])
    for artifact in [line, post, ink, residual, comparison] {
      _ = try graph.commitReplacement(artifact)
    }

    let commit = try graph.commitReplacement(
      revision(kind: .targetAnchoredTrialBaseline(groupA))
    )

    #expect(commit.invalidatedRevisionIDs == [line.id, post.id, ink.id, residual.id, comparison.id])
    #expect(graph.currentRevision(for: .targetAnchoredTrialBaseline(groupB))?.id == baselineB.id)
  }

  @Test("one boundary-side replacement invalidates only its posterior and associations")
  func boundarySideReplacementIsDirectional() throws {
    var graph = LearningDependencyGraph()
    let left = revision(kind: .boundaryObservation(.negativeX))
    let right = revision(kind: .boundaryObservation(.positiveX))
    _ = try graph.commitReplacement(left)
    _ = try graph.commitReplacement(right)
    let leftPosterior = revision(
      kind: .boundaryPosterior(.negativeX),
      consumes: [left.id]
    )
    let leftAssociation = revision(
      kind: .boundaryAssociation(.negativeX),
      consumes: [leftPosterior.id]
    )
    let rightPosterior = revision(
      kind: .boundaryPosterior(.positiveX),
      consumes: [right.id]
    )
    _ = try graph.commitReplacement(leftPosterior)
    _ = try graph.commitReplacement(leftAssociation)
    _ = try graph.commitReplacement(rightPosterior)

    let commit = try graph.commitReplacement(
      revision(kind: .boundaryObservation(.negativeX))
    )

    #expect(commit.invalidatedRevisionIDs == [leftPosterior.id, leftAssociation.id])
    #expect(graph.currentRevision(for: .boundaryObservation(.positiveX))?.id == right.id)
    #expect(graph.currentRevision(for: .boundaryPosterior(.positiveX))?.id == rightPosterior.id)
  }

  @Test("Camera invalidation reports a current root separately when it has no consumers")
  func cameraInvalidationRootOnly() throws {
    var graph = LearningDependencyGraph()
    let observation = revision(kind: .visibilityTargetObservation)
    _ = try graph.commitReplacement(observation)

    let invalidation = graph.invalidateForCameraChange(
      rootKinds: [.visibilityTargetObservation]
    )

    #expect(invalidation.rootInvalidatedRevisionIDs == [observation.id])
    #expect(invalidation.transitiveInvalidatedRevisionIDs.isEmpty)
    #expect(invalidation.allInvalidatedRevisionIDs == [observation.id])
    #expect(graph.currentRevision(for: .visibilityTargetObservation) == nil)
    #expect(graph.revision(id: observation.id)?.state == .invalidated)
  }

  @Test("Camera invalidation follows declared edges while boundary and center remain current")
  func cameraInvalidationIsExplicitAndTransitive() throws {
    var graph = LearningDependencyGraph()
    let negativeX = revision(kind: .boundaryObservation(.negativeX))
    let positiveX = revision(kind: .boundaryObservation(.positiveX))
    let negativeY = revision(kind: .boundaryObservation(.negativeY))
    let positiveY = revision(kind: .boundaryObservation(.positiveY))
    for boundary in [negativeX, positiveX, negativeY, positiveY] {
      _ = try graph.commitReplacement(boundary)
    }
    let center = revision(
      kind: .estimatedMachineCenter,
      consumes: [negativeX.id, positiveX.id, negativeY.id, positiveY.id]
    )
    _ = try graph.commitReplacement(center)
    let targetPose = revision(kind: .targetPoseRegistration)
    _ = try graph.commitReplacement(targetPose)
    let baseline = revision(kind: .preTargetClearViewBaseline, consumes: [targetPose.id])
    _ = try graph.commitReplacement(baseline)
    let target = revision(kind: .visibilityTargetExecution, consumes: [baseline.id])
    _ = try graph.commitReplacement(target)

    let invalidation = graph.invalidateForCameraChange(rootKinds: [.targetPoseRegistration])

    #expect(invalidation.rootInvalidatedRevisionIDs == [targetPose.id])
    #expect(invalidation.transitiveInvalidatedRevisionIDs == [baseline.id, target.id])
    #expect(graph.currentRevision(for: .estimatedMachineCenter)?.id == center.id)
    for boundary in [negativeX, positiveX, negativeY, positiveY] {
      #expect(graph.currentRevision(for: boundary.kind)?.id == boundary.id)
    }
  }

  @Test("Repeated camera invalidation is idempotent and retains revision provenance")
  func repeatedCameraInvalidationIsIdempotent() throws {
    var graph = LearningDependencyGraph()
    let root = revision(kind: .machineCameraRegistration)
    _ = try graph.commitReplacement(root)
    let consumer = revision(kind: .visibilityRegistration, consumes: [root.id])
    _ = try graph.commitReplacement(consumer)
    let revisionCount = graph.revisions.count

    let first = graph.invalidateForCameraChange(rootKinds: [.machineCameraRegistration])
    let second = graph.invalidateForCameraChange(rootKinds: [.machineCameraRegistration])

    #expect(first.rootInvalidatedRevisionIDs == [root.id])
    #expect(first.transitiveInvalidatedRevisionIDs == [consumer.id])
    #expect(second.rootInvalidatedRevisionIDs.isEmpty)
    #expect(second.transitiveInvalidatedRevisionIDs.isEmpty)
    #expect(graph.revisions.count == revisionCount)
    #expect(graph.revision(id: root.id)?.attemptID == root.attemptID)
    #expect(graph.revision(id: root.id)?.disposition == root.disposition)
    #expect(graph.revision(id: consumer.id)?.consumedRevisionIDs == [root.id])
  }

  @Test("staged final replacement supersedes its exact invalidated accepted revision")
  func stagedReplacementSupersedesExactInvalidatedRevision() throws {
    var staged = try stagedRegistrationReplacementGraph()
    let candidate = revision(
      kind: .visibilityRegistration,
      consumes: [staged.newTargetPose.id]
    )

    let commit = try staged.graph.commitReplacement(
      candidate,
      supersedingInvalidatedRevision: staged.oldRegistration.id
    )

    #expect(commit.currentRevision.id == candidate.id)
    #expect(commit.supersededRevisionID == staged.oldRegistration.id)
    #expect(commit.invalidatedRevisionIDs.isEmpty)
    #expect(staged.graph.revision(id: staged.oldRegistration.id)?.state == .superseded)
    #expect(staged.graph.revision(id: staged.oldRegistration.id)?.attemptID == staged.oldRegistration.attemptID)
    #expect(staged.graph.currentRevision(for: .visibilityRegistration)?.id == candidate.id)
    #expect(staged.graph.revision(id: staged.dependent.id)?.state == .invalidated)
    #expect(
      staged.graph.revision(id: staged.dependent.id)?.consumedRevisionIDs
        == staged.dependent.consumedRevisionIDs
    )
  }

  @Test("staged final replacement rejects wrong ID kind and state atomically")
  func stagedReplacementIdentityValidationIsAtomic() throws {
    var staged = try stagedRegistrationReplacementGraph()
    let initialRevisions = Set(staged.graph.revisions)
    let missingID = LearningArtifactRevisionID()
    let candidate = revision(
      kind: .visibilityRegistration,
      consumes: [staged.newTargetPose.id]
    )

    #expect(
      throws: LearningDependencyGraphError.explicitReplacementRevisionUnavailable(missingID)
    ) {
      try staged.graph.commitReplacement(
        candidate,
        supersedingInvalidatedRevision: missingID
      )
    }
    #expect(Set(staged.graph.revisions) == initialRevisions)

    let wrongKindCandidate = revision(
      kind: .visibilityTargetObservation,
      consumes: [staged.newTargetPose.id]
    )
    #expect(
      throws: LearningDependencyGraphError.explicitReplacementKindMismatch(
        revisionID: staged.oldRegistration.id,
        expected: wrongKindCandidate.kind,
        actual: staged.oldRegistration.kind
      )
    ) {
      try staged.graph.commitReplacement(
        wrongKindCandidate,
        supersedingInvalidatedRevision: staged.oldRegistration.id
      )
    }
    #expect(Set(staged.graph.revisions) == initialRevisions)

    let currentKindCandidate = revision(kind: .targetPoseRegistration)
    #expect(
      throws: LearningDependencyGraphError.explicitReplacementStateMismatch(
        revisionID: staged.newTargetPose.id,
        actual: .current
      )
    ) {
      try staged.graph.commitReplacement(
        currentKindCandidate,
        supersedingInvalidatedRevision: staged.newTargetPose.id
      )
    }
    #expect(Set(staged.graph.revisions) == initialRevisions)
  }

  @Test("unsuccessful staged final replacement leaves the accepted draft state unchanged")
  func unsuccessfulStagedReplacementIsAtomic() throws {
    var staged = try stagedRegistrationReplacementGraph()
    let failed = LearningArtifactRevision(
      kind: .visibilityRegistration,
      attemptID: ExerciseAttemptID(),
      disposition: .failed("registration validation failed"),
      consumedRevisionIDs: [staged.newTargetPose.id]
    )
    let initialRevisions = Set(staged.graph.revisions)

    #expect(
      throws: LearningDependencyGraphError.unsuccessfulReplacement(failed.disposition)
    ) {
      try staged.graph.commitReplacement(
        failed,
        supersedingInvalidatedRevision: staged.oldRegistration.id
      )
    }

    #expect(Set(staged.graph.revisions) == initialRevisions)
    #expect(staged.graph.revision(id: staged.oldRegistration.id)?.state == .invalidated)
    #expect(staged.graph.revision(id: failed.id) == nil)
    #expect(staged.graph.revision(id: staged.dependent.id)?.state == .invalidated)
  }

  @Test("numeric aggregates expose N estimator uncertainty and exact included attempts")
  func numericAggregate() throws {
    let compatibility = numericCompatibility()
    let first = try ExerciseAttempt(
      disposition: .succeeded,
      compatibility: compatibility,
      acceptedSequence: 1,
      value: 2.0
    )
    let refused = try ExerciseAttempt<Double>(
      disposition: .refused("controller refusal"),
      compatibility: compatibility,
      acceptedSequence: 2,
      value: nil
    )
    let second = try ExerciseAttempt(
      disposition: .succeeded,
      compatibility: compatibility,
      acceptedSequence: 3,
      value: 4.0
    )
    let third = try ExerciseAttempt(
      disposition: .succeeded,
      compatibility: compatibility,
      acceptedSequence: 4,
      value: 6.0
    )
    let history = try ExerciseAttemptHistory(
      compatibility: compatibility,
      attempts: [first, refused, second, third]
    )

    let aggregate = try NumericAttemptAggregate(history: history)

    #expect(aggregate.validSampleCount == 3)
    #expect(aggregate.estimator == AggregateEstimatorIdentity(name: "arithmetic-mean", revision: "1"))
    #expect(aggregate.estimate == 4)
    #expect(aggregate.uncertainty == .sampleStandardDeviation(2))
    #expect(aggregate.includedAttemptIDs == [first.id, second.id, third.id])
    #expect(history.attempts.map(\.id).contains(refused.id))
  }

  @Test("successful Redo supersedes exactly its replaced included attempt")
  func successfulAttemptReplacement() throws {
    let compatibility = numericCompatibility()
    let original = try ExerciseAttempt(
      disposition: .succeeded,
      compatibility: compatibility,
      acceptedSequence: 1,
      value: 10.0
    )
    let independent = try ExerciseAttempt(
      disposition: .succeeded,
      compatibility: compatibility,
      acceptedSequence: 2,
      value: 30.0
    )
    let replacement = try ExerciseAttempt(
      disposition: .succeeded,
      compatibility: compatibility,
      acceptedSequence: 3,
      value: 20.0
    )
    var history = try ExerciseAttemptHistory(
      compatibility: compatibility,
      attempts: [original, independent]
    )

    let commit = try history.recordReplacement(
      replacement,
      replacing: original.id
    )
    let aggregate = try NumericAttemptAggregate(history: history)

    #expect(commit.acceptedReplacement)
    #expect(commit.replacedAttemptID == original.id)
    #expect(commit.replacementAttemptID == replacement.id)
    #expect(history.attempts.map(\.id) == [original.id, independent.id, replacement.id])
    #expect(history.records.map(\.inclusionState) == [
      .superseded(by: replacement.id),
      .included,
      .included,
    ])
    #expect(aggregate.validSampleCount == 2)
    #expect(aggregate.estimate == 25)
    #expect(aggregate.includedAttemptIDs == [independent.id, replacement.id])
  }

  @Test("unsuccessful Redo remains provenance and leaves the old value included")
  func unsuccessfulAttemptReplacement() throws {
    let compatibility = numericCompatibility()
    let original = try ExerciseAttempt(
      disposition: .succeeded,
      compatibility: compatibility,
      acceptedSequence: 1,
      value: 10.0
    )
    var history = try ExerciseAttemptHistory(
      compatibility: compatibility,
      attempts: [original]
    )
    let dispositions: [ExerciseAttemptDisposition] = [
      .failed("measurement failed"),
      .cancelled,
      .refused("controller refused"),
      .unclear("occluded"),
      .ambiguous("settlement unknown"),
    ]

    for (offset, disposition) in dispositions.enumerated() {
      let replacement = try ExerciseAttempt<Double>(
        disposition: disposition,
        compatibility: compatibility,
        acceptedSequence: UInt64(offset + 2),
        value: nil
      )
      let commit = try history.recordReplacement(
        replacement,
        replacing: original.id
      )
      #expect(!commit.acceptedReplacement)
    }
    let aggregate = try NumericAttemptAggregate(history: history)

    #expect(history.records.first?.inclusionState == .included)
    #expect(history.records.dropFirst().allSatisfy {
      $0.inclusionState == .excludedUnsuccessful
    })
    #expect(history.attempts.count == 6)
    #expect(aggregate.validSampleCount == 1)
    #expect(aggregate.estimate == 10)
    #expect(aggregate.includedAttemptIDs == [original.id])
  }

  @Test("successful Redo can supersede an old sample across compatibility histories")
  func crossCompatibilityAttemptReplacement() throws {
    let oldCompatibility = numericCompatibility()
    let newCompatibility = AttemptCompatibility(
      cameraConfigurationID: CameraConfigurationID(),
      coordinateSpace: oldCompatibility.coordinateSpace,
      units: oldCompatibility.units,
      group: oldCompatibility.group,
      algorithmRevision: oldCompatibility.algorithmRevision
    )
    let replaced = try ExerciseAttempt(
      disposition: .succeeded,
      compatibility: oldCompatibility,
      acceptedSequence: 1,
      value: 10.0
    )
    let independent = try ExerciseAttempt(
      disposition: .succeeded,
      compatibility: oldCompatibility,
      acceptedSequence: 2,
      value: 30.0
    )
    let replacement = try ExerciseAttempt(
      disposition: .succeeded,
      compatibility: newCompatibility,
      acceptedSequence: 3,
      value: 20.0
    )
    var oldHistory = try ExerciseAttemptHistory(
      compatibility: oldCompatibility,
      attempts: [replaced, independent]
    )
    var newHistory = try ExerciseAttemptHistory<Double>(
      compatibility: newCompatibility
    )

    var stagedOldHistory = oldHistory
    var stagedNewHistory = newHistory
    try stagedNewHistory.record(replacement)
    let superseded = try stagedOldHistory.supersedeIncludedAttempt(
      replaced.id,
      by: replacement.id
    )
    oldHistory = stagedOldHistory
    newHistory = stagedNewHistory

    let oldAggregate = try NumericAttemptAggregate(history: oldHistory)
    let newAggregate = try NumericAttemptAggregate(history: newHistory)
    #expect(superseded.inclusionState == .superseded(by: replacement.id))
    #expect(oldHistory.attempts.map(\.id) == [replaced.id, independent.id])
    #expect(oldAggregate.validSampleCount == 1)
    #expect(oldAggregate.includedAttemptIDs == [independent.id])
    #expect(newAggregate.validSampleCount == 1)
    #expect(newAggregate.includedAttemptIDs == [replacement.id])
  }

  @Test("unsuccessful incompatible Redo leaves the old sample included")
  func unsuccessfulCrossCompatibilityReplacement() throws {
    let oldCompatibility = numericCompatibility()
    let newCompatibility = AttemptCompatibility(
      cameraConfigurationID: CameraConfigurationID(),
      coordinateSpace: oldCompatibility.coordinateSpace,
      units: oldCompatibility.units,
      group: oldCompatibility.group,
      algorithmRevision: oldCompatibility.algorithmRevision
    )
    let accepted = try ExerciseAttempt(
      disposition: .succeeded,
      compatibility: oldCompatibility,
      acceptedSequence: 1,
      value: 10.0
    )
    let failed = try ExerciseAttempt<Double>(
      disposition: .failed("replacement measurement failed"),
      compatibility: newCompatibility,
      acceptedSequence: 2,
      value: nil
    )
    let oldHistory = try ExerciseAttemptHistory(
      compatibility: oldCompatibility,
      attempts: [accepted]
    )
    var newHistory = try ExerciseAttemptHistory<Double>(
      compatibility: newCompatibility
    )

    try newHistory.record(failed)

    #expect(oldHistory.records.first?.inclusionState == .included)
    #expect(newHistory.records.first?.inclusionState == .excludedUnsuccessful)
    #expect(try NumericAttemptAggregate(history: oldHistory).includedAttemptIDs == [accepted.id])
    #expect(throws: NumericAggregateError.noSuccessfulValues) {
      try NumericAttemptAggregate(history: newHistory)
    }
  }

  @Test("two geometric attempts expose typed centroid and component uncertainty")
  func twoPointAggregate() throws {
    let compatibility = pointCompatibility()
    let first = try ExerciseAttempt(
      disposition: .succeeded,
      compatibility: compatibility,
      acceptedSequence: 1,
      value: Point2<CameraPixelSpace>(x: 1, y: 2)
    )
    let second = try ExerciseAttempt(
      disposition: .succeeded,
      compatibility: compatibility,
      acceptedSequence: 2,
      value: Point2<CameraPixelSpace>(x: 3, y: 6)
    )
    let history = try ExerciseAttemptHistory(
      compatibility: compatibility,
      attempts: [first, second]
    )

    let aggregate = try PointAttemptAggregate(history: history)
    let expectedUncertainty = try Vector2<CameraPixelSpace>(
      dx: sqrt(2),
      dy: sqrt(8)
    )

    #expect(aggregate.validSampleCount == 2)
    #expect(aggregate.estimator == AggregateEstimatorIdentity(
      name: "component-arithmetic-mean",
      revision: "1"
    ))
    #expect(aggregate.centroid == (try Point2<CameraPixelSpace>(x: 2, y: 4)))
    #expect(aggregate.uncertainty == .componentSampleStandardDeviation(expectedUncertainty))
    #expect(aggregate.includedAttemptIDs == [first.id, second.id])
  }

  @Test("N-point aggregate excludes unsuccessful provenance")
  func nPointAggregateExcludesUnsuccessfulAttempts() throws {
    let compatibility = pointCompatibility()
    let successful = try [0.0, 3.0, 6.0].enumerated().map { offset, value in
      try ExerciseAttempt(
        disposition: .succeeded,
        compatibility: compatibility,
        acceptedSequence: UInt64(offset + 1),
        value: Point2<CameraPixelSpace>(x: value, y: value)
      )
    }
    let unsuccessful = try [
      ExerciseAttemptDisposition.refused("camera unavailable"),
      .unclear("tool occluded"),
      .cancelled,
      .ambiguous("frame provenance unknown"),
      .failed("analysis failed"),
    ].enumerated().map { offset, disposition in
      try ExerciseAttempt<Point2<CameraPixelSpace>>(
        disposition: disposition,
        compatibility: compatibility,
        acceptedSequence: UInt64(offset + 4),
        value: nil
      )
    }
    let history = try ExerciseAttemptHistory(
      compatibility: compatibility,
      attempts: successful + unsuccessful
    )

    let aggregate = try PointAttemptAggregate(history: history)

    #expect(aggregate.validSampleCount == 3)
    #expect(aggregate.centroid == (try Point2<CameraPixelSpace>(x: 3, y: 3)))
    #expect(aggregate.uncertainty == .componentSampleStandardDeviation(
      try Vector2<CameraPixelSpace>(dx: 3, dy: 3)
    ))
    #expect(aggregate.includedAttemptIDs == successful.map(\.id))
    #expect(history.attempts.count == 8)
  }

  @Test("geometric histories enforce compatibility and geometric coordinate identity")
  func pointAggregateCompatibility() throws {
    let compatibility = pointCompatibility()
    var history = try ExerciseAttemptHistory<Point2<CameraPixelSpace>>(
      compatibility: compatibility
    )
    let incompatible = AttemptCompatibility(
      cameraConfigurationID: CameraConfigurationID(),
      coordinateSpace: compatibility.coordinateSpace,
      units: compatibility.units,
      group: compatibility.group,
      algorithmRevision: compatibility.algorithmRevision
    )
    let attempt = try ExerciseAttempt(
      disposition: .succeeded,
      compatibility: incompatible,
      acceptedSequence: 1,
      value: Point2<CameraPixelSpace>(x: 4, y: 5)
    )

    #expect(throws: ExerciseAttemptError.incompatibleAttempt(
      expected: compatibility,
      actual: incompatible
    )) {
      try history.record(attempt)
    }

    let nonGeometric = AttemptCompatibility(
      cameraConfigurationID: compatibility.cameraConfigurationID,
      coordinateSpace: .categorical,
      units: .categorical,
      group: compatibility.group,
      algorithmRevision: compatibility.algorithmRevision
    )
    let nonGeometricHistory = try ExerciseAttemptHistory(
      compatibility: nonGeometric,
      attempts: [
        try ExerciseAttempt(
          disposition: .succeeded,
          compatibility: nonGeometric,
          acceptedSequence: 1,
          value: Point2<CameraPixelSpace>(x: 4, y: 5)
        )
      ]
    )
    #expect(throws: PointAttemptAggregateError.nonGeometricCoordinateSpace(.categorical)) {
      try PointAttemptAggregate(history: nonGeometricHistory)
    }
  }

  @Test("categorical aggregate retains typed counts and excludes unclear outcomes")
  func categoricalAggregate() throws {
    enum Label: Hashable, Sendable { case clear, partial }
    let compatibility = AttemptCompatibility(
      cameraConfigurationID: CameraConfigurationID(),
      coordinateSpace: .categorical,
      units: .categorical,
      group: AttemptGroupIdentity(rawValue: "clear-pose"),
      algorithmRevision: "label-v2"
    )
    let attempts = [
      try ExerciseAttempt(disposition: .succeeded, compatibility: compatibility, acceptedSequence: 1, value: Label.clear),
      try ExerciseAttempt(disposition: .succeeded, compatibility: compatibility, acceptedSequence: 2, value: Label.partial),
      try ExerciseAttempt(disposition: .succeeded, compatibility: compatibility, acceptedSequence: 3, value: Label.clear),
      try ExerciseAttempt<Label>(disposition: .unclear("occluded"), compatibility: compatibility, acceptedSequence: 4, value: nil),
    ]
    let history = try ExerciseAttemptHistory(compatibility: compatibility, attempts: attempts)

    let aggregate = try CategoricalAttemptAggregate(history: history)

    #expect(aggregate.validSampleCount == 3)
    #expect(aggregate.counts[.clear] == 2)
    #expect(aggregate.counts[.partial] == 1)
    #expect(aggregate.proportions[.clear] == 2.0 / 3.0)
    #expect(aggregate.includedAttemptIDs == Array(attempts.prefix(3)).map(\.id))
  }

  @Test("current-state aggregate selects latest accepted observation rather than averaging")
  func latestStateAggregate() throws {
    enum Pose: Hashable, Sendable { case up, down }
    let compatibility = AttemptCompatibility(
      cameraConfigurationID: nil,
      coordinateSpace: .currentState,
      units: .state,
      group: AttemptGroupIdentity(rawValue: "pen-pose"),
      algorithmRevision: "human-label-v1"
    )
    let up = try ExerciseAttempt(disposition: .succeeded, compatibility: compatibility, acceptedSequence: 4, value: Pose.up)
    let cancelled = try ExerciseAttempt<Pose>(disposition: .cancelled, compatibility: compatibility, acceptedSequence: 5, value: nil)
    let down = try ExerciseAttempt(disposition: .succeeded, compatibility: compatibility, acceptedSequence: 6, value: Pose.down)
    let history = try ExerciseAttemptHistory(compatibility: compatibility, attempts: [up, cancelled, down])

    let aggregate = try LatestStateAggregate(history: history)

    #expect(aggregate.validSampleCount == 2)
    #expect(aggregate.value == .down)
    #expect(aggregate.latestAttemptID == down.id)
    #expect(aggregate.includedAttemptIDs == [up.id, down.id])
  }

  @Test("incompatible attempt identities cannot be silently pooled")
  func incompatibleAttemptsRefusePooling() throws {
    let expected = numericCompatibility()
    var history = try ExerciseAttemptHistory<Double>(compatibility: expected)
    let incompatibleDimensions = [
      AttemptCompatibility(cameraConfigurationID: CameraConfigurationID(), coordinateSpace: expected.coordinateSpace, units: expected.units, group: expected.group, algorithmRevision: expected.algorithmRevision),
      AttemptCompatibility(cameraConfigurationID: expected.cameraConfigurationID, coordinateSpace: .field, units: expected.units, group: expected.group, algorithmRevision: expected.algorithmRevision),
      AttemptCompatibility(cameraConfigurationID: expected.cameraConfigurationID, coordinateSpace: expected.coordinateSpace, units: .pixels, group: expected.group, algorithmRevision: expected.algorithmRevision),
      AttemptCompatibility(cameraConfigurationID: expected.cameraConfigurationID, coordinateSpace: expected.coordinateSpace, units: expected.units, group: AttemptGroupIdentity(rawValue: "other-direction"), algorithmRevision: expected.algorithmRevision),
      AttemptCompatibility(cameraConfigurationID: expected.cameraConfigurationID, coordinateSpace: expected.coordinateSpace, units: expected.units, group: expected.group, algorithmRevision: "numeric-v2"),
    ]

    for actual in incompatibleDimensions {
      let attempt = try ExerciseAttempt(
        disposition: .succeeded,
        compatibility: actual,
        acceptedSequence: 1,
        value: 1.0
      )
      #expect(throws: ExerciseAttemptError.incompatibleAttempt(expected: expected, actual: actual)) {
        try history.record(attempt)
      }
    }
    #expect(history.attempts.isEmpty)
  }
}

private func revision(
  kind: LearningArtifactKind,
  consumes: Set<LearningArtifactRevisionID> = []
) -> LearningArtifactRevision {
  LearningArtifactRevision(
    kind: kind,
    attemptID: ExerciseAttemptID(),
    disposition: .succeeded,
    consumedRevisionIDs: consumes
  )
}

private func stagedRegistrationReplacementGraph() throws -> (
  graph: LearningDependencyGraph,
  newTargetPose: LearningArtifactRevision,
  oldRegistration: LearningArtifactRevision,
  dependent: LearningArtifactRevision
) {
  var graph = LearningDependencyGraph()
  let oldTargetPose = revision(kind: .targetPoseRegistration)
  _ = try graph.commitReplacement(oldTargetPose)
  let oldRegistration = revision(
    kind: .visibilityRegistration,
    consumes: [oldTargetPose.id]
  )
  _ = try graph.commitReplacement(oldRegistration)
  let dependent = revision(
    kind: .targetAnchoredTrialBaseline(AttemptGroupIdentity(rawValue: "draft-trial")),
    consumes: [oldRegistration.id]
  )
  _ = try graph.commitReplacement(dependent)
  let newTargetPose = revision(kind: .targetPoseRegistration)
  let rootCommit = try graph.commitReplacement(newTargetPose)
  #expect(rootCommit.invalidatedRevisionIDs == [oldRegistration.id, dependent.id])
  #expect(graph.revision(id: oldRegistration.id)?.state == .invalidated)
  #expect(graph.revision(id: dependent.id)?.state == .invalidated)
  return (graph, newTargetPose, oldRegistration, dependent)
}

private func numericCompatibility() -> AttemptCompatibility {
  AttemptCompatibility(
    cameraConfigurationID: CameraConfigurationID(
      UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
    ),
    coordinateSpace: .machine,
    units: .millimeters,
    group: AttemptGroupIdentity(rawValue: "positive-x"),
    algorithmRevision: "numeric-v1"
  )
}

private func pointCompatibility() -> AttemptCompatibility {
  AttemptCompatibility(
    cameraConfigurationID: CameraConfigurationID(
      UUID(uuidString: "00000000-0000-0000-0000-000000000222")!
    ),
    coordinateSpace: .cameraPixels,
    units: .pixels,
    group: AttemptGroupIdentity(rawValue: "anchor-mark-trial-a"),
    algorithmRevision: "anchor-centroid-v1"
  )
}
