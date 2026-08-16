import Foundation
import PlotterModel
@testable import PlotterRuntime
import Testing

@Suite("Learning artifact revisions and attempt aggregates")
struct LearningArtifactsTests {
  @Test("successful replacement is atomic and supersedes the old revision")
  func successfulReplacement() throws {
    var graph = LearningDependencyGraph()
    let appearance = revision(kind: .penCapAppearance)
    _ = try graph.commitReplacement(appearance)
    let old = revision(kind: .penInteraction, consumes: [appearance.id])
    let firstCommit = try graph.commitReplacement(old)
    let replacement = revision(kind: .penInteraction, consumes: [appearance.id])
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
    let appearance = revision(kind: .penCapAppearance)
    _ = try graph.commitReplacement(appearance)
    let accepted = revision(kind: .penInteraction, consumes: [appearance.id])
    _ = try graph.commitReplacement(accepted)

    for disposition in [
      ExerciseAttemptDisposition.failed("analysis failed"),
      .cancelled,
      .ambiguous("write accepted but settlement unknown"),
    ] {
      let candidate = LearningArtifactRevision(
        kind: .penInteraction,
        attemptID: ExerciseAttemptID(),
        disposition: disposition,
        consumedRevisionIDs: [appearance.id]
      )
      #expect(throws: LearningDependencyGraphError.unsuccessfulReplacement(disposition)) {
        try graph.commitReplacement(candidate)
      }
      #expect(graph.currentRevision(for: .penInteraction)?.id == accepted.id)
      #expect(graph.revision(id: accepted.id)?.state == .current)
    }
  }

  @Test("Pen Interaction replacement retains independent boundary observations")
  func penReplacementRetainsIndependentBoundary() throws {
    var graph = LearningDependencyGraph()
    let appearance = revision(kind: .penCapAppearance)
    _ = try graph.commitReplacement(appearance)
    let pen = revision(kind: .penInteraction, consumes: [appearance.id])
    let boundary = revision(kind: .boundarySideAggregate(.positiveX))
    _ = try graph.commitReplacement(pen)
    _ = try graph.commitReplacement(boundary)

    let commit = try graph.commitReplacement(
      revision(kind: .penInteraction, consumes: [appearance.id])
    )

    #expect(commit.invalidatedRevisionIDs.isEmpty)
    #expect(graph.currentRevision(for: .boundarySideAggregate(.positiveX))?.id == boundary.id)
  }

  @Test("Stage 4 commits only the exact tip-rooted dependency shapes")
  func stageFourDependencyShapes() throws {
    let stage = try stageFourArtifactGraph(group: AttemptGroupIdentity(rawValue: "trial-a"))

    #expect(stage.linePlan.consumedRevisionIDs == [stage.tip.id])
    #expect(stage.localContext.consumedRevisionIDs == [stage.linePlan.id, stage.tip.id])
    #expect(stage.lineStartArrival.consumedRevisionIDs == [
      stage.linePlan.id, stage.localContext.id,
    ])
    #expect(stage.lineExecution.consumedRevisionIDs == [
      stage.linePlan.id, stage.localContext.id, stage.lineStartArrival.id,
    ])
    #expect(stage.postLineObservation.consumedRevisionIDs == [
      stage.lineExecution.id, stage.localContext.id, stage.tip.id,
    ])
    #expect(stage.comparison.consumedRevisionIDs == [stage.postLineObservation.id])
    for artifact in [
      stage.tip, stage.linePlan, stage.localContext, stage.lineStartArrival,
      stage.lineExecution, stage.postLineObservation, stage.comparison,
    ] {
      #expect(stage.graph.revision(id: artifact.id)?.state == .current)
    }
  }

  @Test("Stage 4 rejects missing and cross-kind dependencies")
  func stageFourRejectsInvalidDependencyShapes() throws {
    var tipStage = try acceptedTipArtifactGraph()
    let group = AttemptGroupIdentity(rawValue: "trial-invalid")
    let plan = revision(kind: .linePlan(group), consumes: [tipStage.tip.id])
    _ = try tipStage.graph.commitReplacement(plan)
    let context = revision(
      kind: .localPreLineContext(group),
      consumes: [plan.id, tipStage.tip.id]
    )
    _ = try tipStage.graph.commitReplacement(context)
    let arrival = revision(
      kind: .lineStartArrival(group),
      consumes: [plan.id, context.id]
    )
    _ = try tipStage.graph.commitReplacement(arrival)
    let execution = revision(
      kind: .lineExecution(group),
      consumes: [plan.id, context.id, arrival.id]
    )
    _ = try tipStage.graph.commitReplacement(execution)

    for candidate in [
      revision(kind: .linePlan(group)),
      revision(kind: .localPreLineContext(group), consumes: [tipStage.tip.id]),
      revision(kind: .lineStartArrival(group), consumes: [plan.id]),
      revision(kind: .lineExecution(group), consumes: [plan.id, arrival.id]),
      revision(
        kind: .postLineObservation(group),
        consumes: [execution.id, context.id]
      ),
    ] {
      #expect(throws: LearningDependencyGraphError.invalidDependencyShape(candidate.kind)) {
        try tipStage.graph.commitReplacement(candidate)
      }
    }
    let invalidComparison = revision(
      kind: .comparison(group),
      consumes: [execution.id]
    )
    #expect(throws: LearningDependencyGraphError.invalidDependencyShape(invalidComparison.kind)) {
      try tipStage.graph.commitReplacement(invalidComparison)
    }
  }

  @Test("replacing the exact tip revision invalidates every Stage 4 consumer")
  func tipReplacementInvalidatesStageFourTransitively() throws {
    var stage = try stageFourArtifactGraph(group: AttemptGroupIdentity(rawValue: "trial-tip"))
    let replacement = revision(
      kind: .tipCameraRegistration,
      consumes: Set([stage.machine.id] + stage.observations.map(\.id))
    )

    let commit = try stage.graph.commitReplacement(replacement)

    #expect(commit.supersededRevisionID == stage.tip.id)
    #expect(commit.invalidatedRevisionIDs == [
      stage.linePlan.id, stage.localContext.id, stage.lineStartArrival.id,
      stage.lineExecution.id, stage.postLineObservation.id, stage.comparison.id,
    ])
    #expect(stage.graph.currentRevision(for: .tipCameraRegistration)?.id == replacement.id)
    #expect(stage.graph.revision(id: stage.tip.id)?.state == .superseded)
    #expect(stage.graph.currentRevision(for: .machineCameraRegistration)?.id == stage.machine.id)
    #expect(stage.observations.allSatisfy {
      stage.graph.currentRevision(for: $0.kind)?.id == $0.id
    })
  }

  @Test("one current side aggregate replacement invalidates center and explicit consumers only")
  func boundarySideReplacementIsDirectional() throws {
    var graph = LearningDependencyGraph()
    let sides = BoundaryDirection.allCases.map {
      revision(kind: .boundarySideAggregate($0))
    }
    for side in sides { _ = try graph.commitReplacement(side) }
    let center = revision(
      kind: .estimatedMachineCenter,
      consumes: Set(sides.map(\.id))
    )
    _ = try graph.commitReplacement(center)
    let arrival = revision(kind: .centerArrival, consumes: [center.id])
    _ = try graph.commitReplacement(arrival)
    let appearance = revision(kind: .penCapAppearance)
    _ = try graph.commitReplacement(appearance)
    let unrelated = revision(kind: .penInteraction, consumes: [appearance.id])
    _ = try graph.commitReplacement(unrelated)

    let commit = try graph.commitReplacement(
      revision(kind: .boundarySideAggregate(.negativeX))
    )

    #expect(commit.invalidatedRevisionIDs == [center.id, arrival.id])
    for direction in [.positiveX, .negativeY, .positiveY] as [BoundaryDirection] {
      let original = sides.first { $0.kind == .boundarySideAggregate(direction) }
      #expect(graph.currentRevision(for: .boundarySideAggregate(direction))?.id == original?.id)
    }
    #expect(graph.currentRevision(for: .penInteraction)?.id == unrelated.id)
  }

  @Test("tip invalidation is idempotent and retains exact provenance")
  func repeatedTipInvalidationIsIdempotent() throws {
    var stage = try stageFourArtifactGraph(group: AttemptGroupIdentity(rawValue: "trial-camera"))
    let revisionCount = stage.graph.revisions.count

    let first = stage.graph.invalidateForCameraChange(rootKinds: [.tipCameraRegistration])
    let second = stage.graph.invalidateForCameraChange(rootKinds: [.tipCameraRegistration])

    #expect(first.rootInvalidatedRevisionIDs == [stage.tip.id])
    #expect(first.transitiveInvalidatedRevisionIDs == [
      stage.linePlan.id, stage.localContext.id, stage.lineStartArrival.id,
      stage.lineExecution.id, stage.postLineObservation.id, stage.comparison.id,
    ])
    #expect(second.rootInvalidatedRevisionIDs.isEmpty)
    #expect(second.transitiveInvalidatedRevisionIDs.isEmpty)
    #expect(stage.graph.revisions.count == revisionCount)
    #expect(stage.graph.revision(id: stage.tip.id)?.attemptID == stage.tip.attemptID)
    #expect(stage.graph.revision(id: stage.postLineObservation.id)?.consumedRevisionIDs.contains(stage.tip.id) == true)
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
    let oneSample = try NumericAttemptAggregate(history: ExerciseAttemptHistory(
      compatibility: compatibility,
      attempts: [first]
    ))
    let twoSamples = try NumericAttemptAggregate(history: ExerciseAttemptHistory(
      compatibility: compatibility,
      attempts: [first, second]
    ))
    let history = try ExerciseAttemptHistory(
      compatibility: compatibility,
      attempts: [first, refused, second, third]
    )

    let aggregate = try NumericAttemptAggregate(history: history)

    #expect(oneSample.validSampleCount == 1)
    #expect(oneSample.uncertainty == .unavailable(validSampleCount: 1))
    #expect(twoSamples.validSampleCount == 2)
    #expect(twoSamples.uncertainty == .sampleStandardDeviation(sqrt(2)))
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

  @Test("whole-aggregate Redo after N=3 supersedes every included sample and restarts at N=1")
  func wholeAggregateRedoAfterThreeSamples() throws {
    let compatibility = numericCompatibility()
    let originals = try [2.0, 4.0, 6.0].enumerated().map { index, value in
      try ExerciseAttempt(
        disposition: .succeeded,
        compatibility: compatibility,
        acceptedSequence: UInt64(index + 1),
        value: value
      )
    }
    var history = try ExerciseAttemptHistory(
      compatibility: compatibility,
      attempts: originals
    )
    let replacement = try ExerciseAttempt(
      disposition: .succeeded,
      compatibility: compatibility,
      acceptedSequence: 4,
      value: 20.0
    )

    let commit = try history.recordWholeIncludedSetReplacement(replacement)
    let aggregate = try NumericAttemptAggregate(history: history)

    #expect(commit.acceptedReplacement)
    #expect(commit.supersededAttemptIDs == originals.map(\.id))
    #expect(history.records.dropLast().allSatisfy {
      $0.inclusionState == .superseded(by: replacement.id)
    })
    #expect(history.records.last?.inclusionState == .included)
    #expect(aggregate.validSampleCount == 1)
    #expect(aggregate.estimate == 20)
    #expect(aggregate.uncertainty == .unavailable(validSampleCount: 1))
    #expect(aggregate.includedAttemptIDs == [replacement.id])
  }

  @Test("failed whole-aggregate Redo retains N=3 byte-for-value inclusion and appends evidence")
  func failedWholeAggregateRedoAfterThreeSamples() throws {
    let compatibility = numericCompatibility()
    let originals = try [2.0, 4.0, 6.0].enumerated().map { index, value in
      try ExerciseAttempt(
        disposition: .succeeded,
        compatibility: compatibility,
        acceptedSequence: UInt64(index + 1),
        value: value
      )
    }
    var history = try ExerciseAttemptHistory(
      compatibility: compatibility,
      attempts: originals
    )
    let beforeRecords = history.records
    let beforeAggregate = try NumericAttemptAggregate(history: history)
    let failed = try ExerciseAttempt(
      disposition: .failed("aggregate construction failed"),
      compatibility: compatibility,
      acceptedSequence: 4,
      value: 99.0
    )

    let commit = try history.recordWholeIncludedSetReplacement(failed)
    let afterAggregate = try NumericAttemptAggregate(history: history)

    #expect(!commit.acceptedReplacement)
    #expect(commit.supersededAttemptIDs.isEmpty)
    #expect(Array(history.records.dropLast()) == beforeRecords)
    #expect(history.records.last?.attempt.value == 99.0)
    #expect(history.records.last?.inclusionState == .excludedUnsuccessful)
    #expect(afterAggregate == beforeAggregate)
    #expect(afterAggregate.validSampleCount == 3)
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
      group: AttemptGroupIdentity(rawValue: "categorical-labels"),
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

private func acceptedTipArtifactGraph() throws -> (
  graph: LearningDependencyGraph,
  machine: LearningArtifactRevision,
  observations: [LearningArtifactRevision],
  tip: LearningArtifactRevision
) {
  var graph = LearningDependencyGraph()
  let appearance = revision(kind: .penCapAppearance)
  _ = try graph.commitReplacement(appearance)
  let sides = BoundaryDirection.allCases.map {
    revision(kind: .boundarySideAggregate($0))
  }
  for side in sides { _ = try graph.commitReplacement(side) }
  let center = revision(
    kind: .estimatedMachineCenter,
    consumes: Set(sides.map(\.id))
  )
  _ = try graph.commitReplacement(center)
  let arrival = revision(kind: .centerArrival, consumes: [center.id])
  _ = try graph.commitReplacement(arrival)
  let machine = revision(
    kind: .machineCameraRegistration,
    consumes: [appearance.id, arrival.id]
  )
  _ = try graph.commitReplacement(machine)
  let observations = (0..<5).map { _ in
    revision(
      kind: .toolContactObservation(ToolContactObservationID()),
      consumes: [machine.id]
    )
  }
  for observation in observations {
    _ = try graph.commitReplacement(observation)
  }
  let tip = revision(
    kind: .tipCameraRegistration,
    consumes: Set([machine.id] + observations.map(\.id))
  )
  _ = try graph.commitReplacement(tip)
  return (graph, machine, observations, tip)
}

private func stageFourArtifactGraph(
  group: AttemptGroupIdentity
) throws -> (
  graph: LearningDependencyGraph,
  machine: LearningArtifactRevision,
  observations: [LearningArtifactRevision],
  tip: LearningArtifactRevision,
  linePlan: LearningArtifactRevision,
  localContext: LearningArtifactRevision,
  lineStartArrival: LearningArtifactRevision,
  lineExecution: LearningArtifactRevision,
  postLineObservation: LearningArtifactRevision,
  comparison: LearningArtifactRevision
) {
  var tipStage = try acceptedTipArtifactGraph()
  let linePlan = revision(kind: .linePlan(group), consumes: [tipStage.tip.id])
  let localContext = revision(
    kind: .localPreLineContext(group),
    consumes: [linePlan.id, tipStage.tip.id]
  )
  let lineStartArrival = revision(
    kind: .lineStartArrival(group),
    consumes: [linePlan.id, localContext.id]
  )
  let lineExecution = revision(
    kind: .lineExecution(group),
    consumes: [linePlan.id, localContext.id, lineStartArrival.id]
  )
  let postLineObservation = revision(
    kind: .postLineObservation(group),
    consumes: [lineExecution.id, localContext.id, tipStage.tip.id]
  )
  let comparison = revision(
    kind: .comparison(group),
    consumes: [postLineObservation.id]
  )
  for artifact in [
    linePlan, localContext, lineStartArrival, lineExecution, postLineObservation, comparison,
  ] {
    _ = try tipStage.graph.commitReplacement(artifact)
  }
  return (
    tipStage.graph, tipStage.machine, tipStage.observations, tipStage.tip,
    linePlan, localContext, lineStartArrival, lineExecution, postLineObservation, comparison
  )
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
