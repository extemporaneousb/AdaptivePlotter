import Foundation
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Learning Path presentation")
struct LearningPathPresentationTests {
  @Test("operator journey has the exact four implemented stages")
  func exactImplementedStageJourney() {
    #expect(LearningPathStage.allCases.map(\.number) == ["1", "2", "3", "4"])
    #expect(
      LearningPathStage.allCases.map(\.title) == [
        "Connect",
        "Enable Motion",
        "Human-Guided Discovery",
        "Observed Drawing Trials",
      ])
  }

  @Test("one tree owns order, parentage, depth, and descendants")
  func curriculumTreeIsTheOnlyHierarchy() {
    let tree = LearningPathTree.curriculum
    #expect(
      tree.flattenedItems.map { "\($0.number) \($0.title)" } == [
        "1 Connect",
        "2 Enable Motion",
        "3 Human-Guided Discovery",
        "3.1 Pen Interaction",
        "3.2 Set X, Y Boundaries",
        "3.3 Calibrate Camera and Visible Cap",
        "3.4 Calibrate Pen Contact from Sparse Marks",
        "4 Observed Drawing Trials",
        "4.1 Choose Isolated Line Plan",
        "4.2 Capture Local Pre-Line Baseline",
        "4.3 Move to Line Start",
        "4.4 Draw Isolated Line",
        "4.5 Reveal and Observe New Ink",
        "4.6 Compare Intended and Observed Geometry",
      ])
    let branch = LearningPathItemID.stage(.humanGuidedDiscovery)
    let leaf = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    #expect(tree.parent(of: leaf) == branch)
    #expect(tree.depth(of: branch) == 0)
    #expect(tree.depth(of: leaf) == 1)
    #expect(tree.children(of: branch).count == 4)
    #expect(tree.descendantLeaves(of: branch) == HumanGuidedDiscoveryStep.allCases.map {
      .humanGuidedDiscovery($0)
    })
    #expect(tree.isActionableLeaf(leaf))
    #expect(!tree.isActionableLeaf(branch))
  }

  @Test("selection and Return to Current mutate presentation state only")
  func inertSelection() {
    var selection = LearningPathSelectionState(current: .humanGuidedDiscovery(.penInteraction))
    selection.select(.stage(.observedDrawingTrials))
    #expect(selection.selected == .stage(.observedDrawingTrials))
    #expect(selection.current == .humanGuidedDiscovery(.penInteraction))
    #expect(selection.isReviewingAnotherItem)

    selection.returnToCurrent()
    #expect(selection.selected == .humanGuidedDiscovery(.penInteraction))
    #expect(!selection.isReviewingAnotherItem)
  }

  @Test("runtime progression follows only when the operator is not reviewing")
  func selectionFollowsCurrentWithoutOverridingReview() {
    var selection = LearningPathSelectionState(current: .stage(.connect))
    selection.updateCurrent(.stage(.enableMotion))
    #expect(selection.selected == .stage(.enableMotion))
    selection.select(.stage(.connect))
    selection.updateCurrent(.humanGuidedDiscovery(.penInteraction))
    #expect(selection.current == .humanGuidedDiscovery(.penInteraction))
    #expect(selection.selected == .stage(.connect))
  }

  @Test("critical cues carry explicit visible and accessible values")
  func typedCues() {
    #expect(PresentationCue.up.visibleText == "UP")
    #expect(PresentationCue.down.visibleText == "DOWN")
    #expect(PresentationCue.yes.visibleText == "YES")
    #expect(PresentationCue.no.visibleText == "NO")
    #expect(PresentationCue.stop.visibleText == "STOP")
    #expect(PresentationCue.direction(.negativeX).visibleText == "X−")
    #expect(PresentationCue.direction(.negativeX).accessibilityValue
      == "Move in the negative X direction")
  }

  @Test("compact exercise contains only item, script, question, actions, and invalidation")
  func compactExerciseContract() {
    let item = LearningPathItemPresentation(
      id: .humanGuidedDiscovery(.penInteraction),
      status: .current
    )
    let invalidation = LearningInvalidationPresentation(
      selectedPlan: nil,
      invalidateAllPlan: nil,
      unavailableReason: nil
    )
    let presentation = OperatorActionPresentation(
      item: item,
      script: [
        ExerciseScriptLinePresentation(
          speaker: .plotter,
          fragments: [.text("Move the pen down.")]
        ),
        ExerciseScriptLinePresentation(
          speaker: .you,
          fragments: [.text("Confirm the physical pose.")]
        ),
      ],
      question: ExerciseQuestionPresentation(prompt: [.text("Is the pen down?")]),
      actionStrip: ExerciseActionStripPresentation(
        ownerID: item.id,
        actions: [ExerciseActionDescriptor(kind: .choice(.yes), title: "YES")]
      ),
      invalidation: invalidation
    )

    #expect(presentation.heading == "3.1 - Pen Interaction")
    #expect(presentation.script.map(\.speaker) == [.plotter, .you])
    #expect(presentation.question?.prompt.accessibilityText == "Is the pen down?")
    #expect(presentation.actionStrip?.actions.map(\.kind) == [.choice(.yes)])
  }

  @Test("Boundary termination controls retain one capability and distinct shortcuts")
  func boundaryTerminationIdentity() {
    let capability = ContextualStopCapabilityID(
      rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    )
    let kinds: [ExerciseActionKind] = [
      .stopAndAcceptBoundary(capability),
      .stop(capability),
      .cancel(capability),
    ]
    #expect(Set(kinds).count == 3)
    #expect(kinds.map(\.effect) == [.commit, .interrupt, .interrupt])
    #expect(kinds.map(\.keyboardShortcut) == [nil, .escape, nil])
  }

  @Test("leaf and branch invalidation plans are tree-shaped and versioned")
  func invalidationPlanShape() {
    let leaf = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let branch = LearningPathItemID.stage(.humanGuidedDiscovery)
    let leafPlan = makePlan(scope: .leaf(root: leaf), affected: [leaf])
    let descendants = LearningPathTree.curriculum.descendantLeaves(of: branch)
    let branchPlan = makePlan(scope: .subtree(root: branch), affected: descendants)

    #expect(leafPlan.contractVersion == .v1)
    #expect(leafPlan.scope.root == leaf)
    #expect(leafPlan.title == "Invalidate This Step")
    #expect(leafPlan.message == "Delete collected data for 1 learning step.")
    #expect(branchPlan.scope.root == branch)
    #expect(branchPlan.affectedItemIDs == descendants)
    #expect(branchPlan.title == "Invalidate This Branch")
    #expect(branchPlan.message.contains("4 learning steps"))
  }

  @Test("direction choices edit values while repeat admission commits")
  func valueInputControls() {
    let selection = ExerciseActionDescriptor(
      kind: .selectDirection(.boundary, .negativeX),
      title: "X−"
    )
    let repeatAction = ExerciseActionDescriptor(
      kind: .recordAnotherAttempt,
      title: "Record Another Attempt"
    )
    #expect(selection.effect == .editValue)
    #expect(repeatAction.effect == .commit)
    #expect(selection.buttonRole == .editValue)
    #expect(repeatAction.buttonRole == .commit)
  }

  private func makePlan(
    scope: LearningInvalidationScope,
    affected: [LearningPathItemID]
  ) -> LearningInvalidationPlan {
    LearningInvalidationPlan(
      scope: scope,
      source: .live,
      affectedItemIDs: affected,
      expectedCurrentRevisionIDs: [],
      expectedGraphRevision: 2,
      expectedAcceptedAttemptSequence: 4,
      expectedAuthorityManifestRevision: nil,
      removesDurableMachineRegistration: false,
      removesDurableTipRegistration: false,
      physicalInkMayRemain: false
    )
  }
}
