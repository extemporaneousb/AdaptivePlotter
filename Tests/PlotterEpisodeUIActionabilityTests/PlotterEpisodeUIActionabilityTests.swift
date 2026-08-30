import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterUI
import Testing

@testable import PlotterApp

@Suite("Plotter episode UI actionability")
struct PlotterEpisodeUIActionabilityTests {
  @Test("PlotterUI alone chooses Learning current owner status and reachable actions")
  func plotterUILearningCompilerOwnsActionability() throws {
    let pen = "1.1-pen"
    let boundary = "1.2-boundary"
    let projection = PlotterUILearningActionabilityCompiler().compile(
      PlotterUILearningActionabilityFacts(
        learning: PlotterUILearningFacts(
          isEnabled: true,
          activeOwnerID: nil,
          orderedMilestones: [
            .init(ownerID: pen, isComplete: false),
            .init(ownerID: boundary, isComplete: false),
          ]
        ),
        selectedOwnerID: pen,
        items: [
          .init(
            ownerID: "1-discovery",
            kind: .discoveryStage,
            stageID: "discovery",
            isStage: true,
            isExercise: false,
            isComplete: false,
            isRepeatable: false
          ),
          .init(
            ownerID: pen,
            kind: .penInteraction,
            stageID: "discovery",
            isStage: false,
            isExercise: true,
            isComplete: false,
            isRepeatable: true
          ),
          .init(
            ownerID: boundary,
            kind: .boundary,
            stageID: "discovery",
            isStage: false,
            isExercise: true,
            isComplete: false,
            isRepeatable: true
          ),
        ]
      )
    )

    #expect(projection.learning.currentOwnerID == pen)
    #expect(projection.item(ownerID: "1-discovery")?.status == .current)
    #expect(projection.item(ownerID: pen)?.status == .current)
    #expect(projection.item(ownerID: boundary)?.status == .next)
    let strip = try #require(projection.strip(ownerID: pen))
    #expect(strip.actions.map(\.title) == ["Identify Pen Cap"])
    #expect(projection.strip(ownerID: boundary) == nil)
  }

  @Test("PlotterUI exact Stop capability suppresses competing Learning actions")
  func plotterUILearningStopIsExactAndExclusive() throws {
    let owner = "1.2-boundary"
    let stopID = UUID(uuidString: "00000000-0000-0000-0000-000000000909")!
    let projection = PlotterUILearningActionabilityCompiler().compile(
      PlotterUILearningActionabilityFacts(
        learning: PlotterUILearningFacts(
          isEnabled: true,
          activeOwnerID: owner,
          orderedMilestones: [.init(ownerID: owner, isComplete: false)]
        ),
        selectedOwnerID: owner,
        items: [.init(
          ownerID: owner,
          kind: .boundary,
          stageID: "discovery",
          isStage: false,
          isExercise: true,
          isComplete: false,
          isRepeatable: true
        )],
        activeOwnerID: owner,
        stop: .init(capabilityID: stopID, kind: .boundary(direction: .positiveX))
      )
    )

    let strip = try #require(projection.strip(ownerID: owner))
    #expect(strip.actions.map(\.action) == [.stop(stopID)])
    #expect(strip.actions.map(\.title) == ["Stop Boundary Search"])
    #expect(strip.mustRemainVisible)
    #expect(projection.contextualStop?.capabilityID == stopID)
  }

  @Test("Learning compiler bounds item visits and diagnostics")
  func plotterUILearningVisitsAreBounded() {
    let items = (0..<12).map { index in
      PlotterUILearningItemFacts(
        ownerID: "owner-\(index)",
        kind: .penInteraction,
        stageID: "discovery",
        isStage: false,
        isExercise: true,
        isComplete: false,
        isRepeatable: false
      )
    }
    let compiler = PlotterUILearningActionabilityCompiler(limits: .init(
      maximumItemVisitCount: 3,
      maximumDiagnosticCount: 1
    ))
    let projection = compiler.compile(PlotterUILearningActionabilityFacts(
      learning: PlotterUILearningFacts(
        isEnabled: true,
        activeOwnerID: nil,
        orderedMilestones: items.map {
          .init(ownerID: $0.ownerID, isComplete: $0.isComplete)
        }
      ),
      selectedOwnerID: items[0].ownerID,
      items: items
    ))

    #expect(projection.visitedItemCount == 3)
    #expect(projection.items.count == 3)
    #expect(projection.diagnostics.count == 1)
    #expect(projection.diagnostics.first?.kind == .projectionTruncated)
  }

  @Test("compiler deterministically preserves immutable semantic actions")
  func deterministicImmutableCompile() {
    let input = PlotterUICompilerInput(
      revision: PlotterUIRevision(rawValue: 7),
      runtimeRevisions: [
        PlotterUIRuntimeRevision(owner: "Drawing", token: "4"),
        PlotterUIRuntimeRevision(owner: "Learning", token: "11"),
      ],
      candidates: [
        PlotterUIActionCandidate(
          id: PlotterUIActionID(rawValue: "learning.enable"),
          title: "Enable Learning",
          intent: .learning(.setEnabled(true))
        ),
        PlotterUIActionCandidate(
          id: PlotterUIActionID(rawValue: "drawing.open"),
          title: "Open Drawing Studio",
          intent: .drawingDraft(.open)
        ),
      ],
      incidentPackage: .unavailable(reason: "No complete exact source is bound.")
    )

    let first = PlotterUICompiler().compile(input)
    let second = PlotterUICompiler().compile(input)

    #expect(first.revision == second.revision)
    #expect(first.runtimeRevisions == second.runtimeRevisions)
    #expect(first.actions == second.actions)
    #expect(first.incidentPackage == second.incidentPackage)
    #expect(first.diagnostics.map(\.kind) == second.diagnostics.map(\.kind))
    #expect(first.diagnostics.map(\.summary) == second.diagnostics.map(\.summary))
  }

  @Test("bounded projection keeps every rendered action actionable or remedied")
  func boundedActionabilityAndStopInvariant() {
    let stopID = UUID()
    let projection = PlotterUICompiler(limits: .init(maximumActionCount: 4)).compile(
      PlotterUICompilerInput(
        revision: PlotterUIRevision(rawValue: 3),
        runtimeRevisions: [PlotterUIRuntimeRevision(owner: "Manual", token: "9")],
        candidates: [
          PlotterUIActionCandidate(
            id: PlotterUIActionID(rawValue: "manual.stop"),
            title: "Stop Manual Jog",
            intent: .manualStop(capabilityID: stopID)
          ),
          PlotterUIActionCandidate(
            id: PlotterUIActionID(rawValue: "manual.wait"),
            title: "Start another jog",
            intent: .manualMotion(.jog(Self.jogRequest)),
            requirements: [PlotterUIRequirement(
              id: "manual.wait",
              isSatisfied: false,
              owner: "PlotterManualMotionRuntime",
              remedy: "Wait for exact Stop settlement."
            )]
          ),
          PlotterUIActionCandidate(
            id: PlotterUIActionID(rawValue: "drawing.start"),
            title: "Run Drawing",
            intent: .drawingRun(.start),
            requirements: [PlotterUIRequirement(
              id: "drawing.start",
              isSatisfied: false,
              owner: "PlotterDrawingRunRuntime",
              remedy: "Review a current exact plan first."
            )]
          ),
        ]
      )
    )

    #expect(projection.actions.count == 3)
    #expect(projection.actions.allSatisfy { $0.isAvailable || $0.unavailableReason?.isEmpty == false })
    #expect(projection.actions.contains { action in
      action.intent == .manualStop(capabilityID: stopID) && action.isAvailable
    })
    #expect(projection.request(for: PlotterUIActionID(rawValue: "manual.wait")) == nil)
  }

  @Test("candidate visits and invalid duplicate diagnostics remain bounded")
  func excessiveCandidateAndDiagnosticBounds() {
    let duplicateID = PlotterUIActionID(rawValue: "same")
    var candidates = [PlotterUIActionCandidate(
      id: duplicateID,
      title: "First",
      intent: .learning(.setEnabled(true))
    )]
    candidates.append(contentsOf: (0..<40).map { index in
      PlotterUIActionCandidate(
        id: index.isMultiple(of: 2) ? duplicateID : PlotterUIActionID(rawValue: "   "),
        title: String(repeating: "invalid", count: 20),
        intent: .learning(.setEnabled(false))
      )
    })
    let limits = PlotterUICompiler.Limits(
      maximumActionCount: 2,
      maximumCandidateVisitCount: 8,
      maximumDiagnosticCount: 3,
      maximumTextLength: 32
    )
    let projection = PlotterUICompiler(limits: limits).compile(PlotterUICompilerInput(
      revision: PlotterUIRevision(rawValue: 1),
      runtimeRevisions: [],
      candidates: candidates
    ))

    #expect(projection.visitedCandidateCount == limits.maximumCandidateVisitCount)
    #expect(projection.actions.map(\.id) == [duplicateID])
    #expect(projection.diagnostics.count == limits.maximumDiagnosticCount)
    #expect(projection.diagnostics.contains { $0.kind == .duplicateAction })
    #expect(projection.diagnostics.contains { $0.kind == .invalidAction })
    #expect(projection.diagnostics.contains { $0.kind == .projectionTruncated })
    #expect(projection.diagnostics.allSatisfy { $0.summary.count <= limits.maximumTextLength })
  }

  @Test("request carries the exact UI and runtime revisions that rendered its action")
  func exactRevisionBoundRequest() throws {
    let actionID = PlotterUIActionID(rawValue: "learning.disable")
    let runtimeRevisions = [PlotterUIRuntimeRevision(owner: "Learning", token: "21")]
    let projection = PlotterUICompiler().compile(PlotterUICompilerInput(
      revision: PlotterUIRevision(rawValue: 15),
      runtimeRevisions: runtimeRevisions,
      candidates: [PlotterUIActionCandidate(
        id: actionID,
        title: "Disable Learning",
        intent: .learning(.setEnabled(false))
      )]
    ))

    let request = try #require(projection.request(for: actionID))
    #expect(request.uiRevision == projection.revision)
    #expect(request.runtimeRevisions == projection.runtimeRevisions)
    #expect(request.actionID == actionID)
    #expect(request.intent == .learning(.setEnabled(false)))
  }

  @MainActor
  @Test("production workspace accepts the exact action reached by its current projection")
  func productionWorkspaceAcceptsReachedAction() async throws {
    let fixture = makeProductionWorkspace()
    let projected = fixture.projection()
    let request = try #require(projected.semantic.request(for: PlotterAppUIActionID.learningMode))
    let before = projected.learningIsEnabled

    let disposition = await fixture.workspace.submitPlotterUIRequest(request)

    #expect(disposition == .accepted(requestID: request.id))
    #expect(fixture.projection().learningIsEnabled == !before)
    await fixture.workspace.shutdown()
  }

  @MainActor
  @Test("production workspace refuses forged and stale requests before lower dispatch")
  func productionWorkspaceRefusalMatrix() async throws {
    let fixture = makeProductionWorkspace()
    let projected = fixture.projection()
    let initialLearning = projected.learningIsEnabled
    let initialManualRevision = runtimeRevision(
      owner: "PlotterManualMotionRuntime",
      in: projected.semantic
    )
    let target = !initialLearning

    let unknown = PlotterUIRequest(
      id: PlotterUIRequestID(rawValue: UUID()),
      uiRevision: projected.semantic.revision,
      runtimeRevisions: projected.semantic.runtimeRevisions,
      actionID: PlotterUIActionID(rawValue: "manual.arbitrary-action"),
      intent: .learning(.setEnabled(target))
    )
    #expect(refusalReason(await fixture.workspace.submitPlotterUIRequest(unknown)) == .unknownAction)

    let mismatched = PlotterUIRequest(
      id: PlotterUIRequestID(rawValue: UUID()),
      uiRevision: projected.semantic.revision,
      runtimeRevisions: projected.semantic.runtimeRevisions,
      actionID: PlotterAppUIActionID.drawingOpen,
      intent: .learning(.setEnabled(target))
    )
    #expect(
      refusalReason(await fixture.workspace.submitPlotterUIRequest(mismatched)) == .mismatchedIntent
    )

    let unavailableAction = try #require(
      projected.semantic.action(id: PlotterAppUIActionID.manualXPositive)
    )
    #expect(!unavailableAction.isAvailable)
    let unavailable = PlotterUIRequest(
      id: PlotterUIRequestID(rawValue: UUID()),
      uiRevision: projected.semantic.revision,
      runtimeRevisions: projected.semantic.runtimeRevisions,
      actionID: unavailableAction.id,
      intent: unavailableAction.intent
    )
    #expect(
      refusalReason(await fixture.workspace.submitPlotterUIRequest(unavailable)) == .unavailableAction
    )

    let staleUI = PlotterUIRequest(
      id: PlotterUIRequestID(rawValue: UUID()),
      uiRevision: PlotterUIRevision(rawValue: projected.semantic.revision.rawValue &+ 1),
      runtimeRevisions: projected.semantic.runtimeRevisions,
      actionID: PlotterAppUIActionID.learningMode,
      intent: .learning(.setEnabled(target))
    )
    #expect(refusalReason(await fixture.workspace.submitPlotterUIRequest(staleUI)) == .staleUIRevision)

    let staleRuntime = PlotterUIRequest(
      id: PlotterUIRequestID(rawValue: UUID()),
      uiRevision: projected.semantic.revision,
      runtimeRevisions: [],
      actionID: PlotterAppUIActionID.learningMode,
      intent: .learning(.setEnabled(target))
    )
    #expect(
      refusalReason(await fixture.workspace.submitPlotterUIRequest(staleRuntime))
        == .staleRuntimeRevision
    )

    let after = fixture.projection()
    #expect(after.learningIsEnabled == initialLearning)
    #expect(
      runtimeRevision(owner: "PlotterManualMotionRuntime", in: after.semantic)
        == initialManualRevision
    )
    await fixture.workspace.shutdown()
  }

  @MainActor
  @Test("an accepted replacement makes its predecessor request stale")
  func acceptedReplacementStalesPredecessor() async throws {
    let fixture = makeProductionWorkspace()
    let projected = fixture.projection()
    let predecessor = try #require(
      projected.semantic.request(for: PlotterAppUIActionID.learningMode)
    )
    let replacement = try #require(
      projected.semantic.request(for: PlotterAppUIActionID.learningMode)
    )

    #expect(
      await fixture.workspace.submitPlotterUIRequest(replacement)
        == .accepted(requestID: replacement.id)
    )
    let settledLearning = fixture.projection().learningIsEnabled
    let stale = await fixture.workspace.submitPlotterUIRequest(predecessor)

    #expect(refusalReason(stale) == .staleUIRevision)
    #expect(fixture.projection().learningIsEnabled == settledLearning)
    await fixture.workspace.shutdown()
  }

  @MainActor
  @Test("window-local manual point and placement revisions stale prior requests")
  func localInputRevisionsStalePriorRequests() async throws {
    let fixture = makeProductionWorkspace()
    let original = fixture.projection()
    let request = try #require(original.semantic.request(for: PlotterAppUIActionID.learningMode))
    let initialLearning = original.learningIsEnabled

    var draft = ManualMotionDraft()
    draft.xDistanceMM = "7"
    let draftProjection = fixture.projection(manualDraft: draft)
    #expect(draftProjection.semantic.revision != original.semantic.revision)
    #expect(
      refusalReason(await fixture.workspace.submitPlotterUIRequest(request)) == .staleUIRevision
    )

    let beforePoint = fixture.projection()
    let pointRequest = try #require(
      beforePoint.semantic.request(for: PlotterAppUIActionID.learningMode)
    )
    let point = pointSelectionSubmission()
    let pointProjection = fixture.projection(pendingPointSelection: point)
    #expect(pointProjection.semantic.revision != beforePoint.semantic.revision)
    #expect(
      refusalReason(await fixture.workspace.submitPlotterUIRequest(pointRequest))
        == .staleUIRevision
    )

    let beforePlacement = fixture.projection()
    let placementRequest = try #require(
      beforePlacement.semantic.request(for: PlotterAppUIActionID.learningMode)
    )
    let placement = PlotterDrawingDraftCameraPlacement(
      frame: exactFrameReference(),
      point: try Point2<CameraPixelSpace>(x: 4, y: 4)
    )
    let placementProjection = fixture.projection(pendingDrawingPlacement: placement)
    #expect(placementProjection.semantic.revision != beforePlacement.semantic.revision)
    #expect(
      refusalReason(await fixture.workspace.submitPlotterUIRequest(placementRequest))
        == .staleUIRevision
    )
    #expect(fixture.projection().learningIsEnabled == initialLearning)
    await fixture.workspace.shutdown()
  }

  @MainActor
  @Test("rendered semantic controls are reached and requests derive only from the projection")
  func renderedControlsAreProjectionBound() async throws {
    let fixture = makeProductionWorkspace()
    let pendingPoint = pointSelectionSubmission()
    let projected = fixture.projection(pendingPointSelection: pendingPoint)
    let semantic = projected.semantic

    let fixedIDs = [
      PlotterAppUIActionID.learningMode,
      PlotterAppUIActionID.manualXNegative,
      PlotterAppUIActionID.manualXPositive,
      PlotterAppUIActionID.manualYNegative,
      PlotterAppUIActionID.manualYPositive,
      PlotterAppUIActionID.manualPenUp,
      PlotterAppUIActionID.manualPenDown,
      PlotterAppUIActionID.drawingOpen,
      PlotterAppUIActionID.pointSelection(pendingPoint),
      PlotterAppUIActionID.incidentPackage,
    ]
    for id in fixedIDs {
      let action = try #require(semantic.action(id: id), "Missing rendered action \(id.rawValue)")
      #expect((semantic.request(for: id) != nil) == action.isAvailable)
    }

    for control in projected.drawingStudio.controls {
      let id = PlotterAppUIActionID.drawingRun(control.intent)
      let action = try #require(semantic.action(id: id))
      #expect((semantic.request(for: id) != nil) == action.isAvailable)
    }
    for control in projected.actionSurface.completedComparisonReview.controls {
      let intent: PlotterUIRetainedComparisonIntent =
        control.intent == .reviewComparison ? .reviewExactFrame : .resumeLivePreview
      let id = PlotterAppUIActionID.retainedComparison(intent)
      #expect(try #require(semantic.request(for: id)).intent == .retainedComparisonReview(intent))
    }
    if let strip = projected.learningPath?.selectedAction.actionStrip {
      for action in strip.actions {
        let id = PlotterAppUIActionID.retainedLearning(action.kind, owner: strip.ownerID)
        let semanticAction = try #require(semantic.action(id: id))
        #expect((semantic.request(for: id) != nil) == semanticAction.isAvailable)
      }
    } else {
      Issue.record("Expected a rendered Learning action strip")
    }
    let resetPlans = [
      projected.learningPath?.resetSurface.selectedPlan,
      projected.learningPath?.menu.resetAllPlan,
    ].compactMap { $0 }
    #expect(!resetPlans.isEmpty)
    for plan in resetPlans {
      let id = PlotterAppUIActionID.learningReset(plan)
      let action = try #require(semantic.action(id: id))
      #expect((semantic.request(for: id) != nil) == action.isAvailable)
    }

    await fixture.workspace.shutdown()
  }

  @MainActor
  @Test("Learning current owner and visible controls come from compiler reachability")
  func learningOwnerComesFromReachability() async throws {
    let fixture = makeProductionWorkspace()
    let projected = fixture.projection()
    let current = projected.currentLearningPathItemID
    let ownerID = "\(current.number)-\(current.title)"

    #expect(projected.semantic.learning?.currentOwnerID == ownerID)
    let strip = try #require(projected.learningPath?.selectedAction.actionStrip)
    #expect(strip.ownerID == current)
    for action in strip.actions {
      #expect(
        projected.semantic.action(
          id: PlotterAppUIActionID.retainedLearning(action.kind, owner: current)
        ) != nil
      )
    }
    let otherOwners = LearningPathItemID.learningExerciseOrder.filter { $0 != current }
    for owner in otherOwners {
      let otherStrip = fixture.workspace.learningPathProjection(
        selectedItemID: owner
      ).selectedAction.actionStrip
      for action in otherStrip?.actions ?? [] {
        #expect(
          projected.semantic.action(
            id: PlotterAppUIActionID.retainedLearning(action.kind, owner: owner)
          ) == nil
        )
      }
    }
    await fixture.workspace.shutdown()
  }

  @MainActor
  @Test("window-local reducers change only their immutable UI revision")
  func localStateIsSemanticEffectFree() async {
    let fixture = makeProductionWorkspace()
    let before = fixture.projection()
    var layout = WorkbenchLayoutState()
    layout = layout.toggling(.motion)
    var selection = LearningPathSelectionState(
      current: .humanGuidedDiscovery(.penInteraction)
    )
    selection.select(.observedDrawingTrial(.chooseDrawingBorderPlan))
    var draft = ManualMotionDraft()
    draft.xDistanceMM = "not submitted"
    let locallyRecompiled = fixture.projection(manualDraft: draft)

    #expect(layout.panes.motionIsPresented == false)
    #expect(selection.isReviewingAnotherItem)
    #expect(draft.xDistanceMM == "not submitted")
    #expect(locallyRecompiled.semantic.revision != before.semantic.revision)
    #expect(locallyRecompiled.semantic.runtimeRevisions == before.semantic.runtimeRevisions)
    #expect(locallyRecompiled.learningIsEnabled == before.learningIsEnabled)
    await fixture.workspace.shutdown()
  }

  @MainActor
  @Test("App incident action publishes bounded availability then typed no-source refusal")
  func appIncidentNoSourceLifecycle() async throws {
    let fixture = makeProductionWorkspace()
    let initial = fixture.projection()
    let request = try #require(
      initial.semantic.request(for: PlotterAppUIActionID.incidentPackage)
    )

    let disposition = await fixture.workspace.submitPlotterUIRequest(request)
    #expect(disposition == .accepted(requestID: request.id))
    let terminal = fixture.projection()
    guard case .refused(let reason, let remedy) = terminal.incidentPackage else {
      Issue.record("Expected the App projection to publish a typed no-source refusal")
      await fixture.workspace.shutdown()
      return
    }
    #expect(reason == "No complete incident-package source provider is configured.")
    #expect(remedy == "Provide one complete, identity-bound incident source before retrying.")

    let directAdmission = await fixture.incidentService.startUnavailable(
      PlotterIncidentPackageUINoSourceRequest()
    )
    guard case .accepted(let updates) = directAdmission else {
      Issue.record("Expected truthful no-source lifecycle admission")
      await fixture.workspace.shutdown()
      return
    }
    var observed: [PlotterIncidentPackageUINoSourceRequestUpdate] = []
    for await update in updates { observed.append(update) }
    #expect(observed.count == PlotterIncidentPackageUIService.maximumBufferedNoSourceUpdateCount)
    #expect(observed.count == 2)
    guard case .checkingAvailability? = observed.first else {
      Issue.record("Expected bounded availability progress before refusal")
      await fixture.workspace.shutdown()
      return
    }
    guard case .terminal(let refusal)? = observed.last else {
      Issue.record("Expected typed terminal no-source refusal")
      await fixture.workspace.shutdown()
      return
    }
    #expect(refusal.reason == .noCompleteSourceProvider)
    #expect(refusal.remedy == .provideCompleteSource)
    #expect(await fixture.incidentProvider.loadCount == 0)
    await fixture.workspace.shutdown()
  }

  @Test("completed incident metadata never upgrades software output to physical evidence")
  func completedIncidentMetadataRemainsNonphysical() {
    let metadata = PlotterUIIncidentPackageMetadata(
      formatVersion: 1,
      encoding: "canonical-json-v1",
      exactByteCount: 20,
      payloadSHA256: String(repeating: "0", count: 64),
      integrityScope: "canonical-envelope-only",
      physicalEvidenceClaimed: false
    )
    let projection = PlotterUICompiler().compile(PlotterUICompilerInput(
      revision: PlotterUIRevision(rawValue: 1),
      runtimeRevisions: [],
      candidates: [],
      incidentPackage: .completed(metadata)
    ))
    guard case .completed(let compiled) = projection.incidentPackage else {
      Issue.record("Expected completed metadata to remain values-only")
      return
    }
    #expect(!compiled.physicalEvidenceClaimed)
  }

  @Test("UI and runtime revisions remain independent dimensions")
  func independentRevisionDimensions() {
    let compiler = PlotterUICompiler()
    let action = PlotterUIActionCandidate(
      id: PlotterUIActionID(rawValue: "drawing.open"),
      title: "Open Drawing Studio",
      intent: .drawingDraft(.open)
    )
    let first = compiler.compile(PlotterUICompilerInput(
      revision: PlotterUIRevision(rawValue: 1),
      runtimeRevisions: [PlotterUIRuntimeRevision(owner: "Drawing", token: "12")],
      candidates: [action]
    ))
    let UIOnly = compiler.compile(PlotterUICompilerInput(
      revision: PlotterUIRevision(rawValue: 2),
      runtimeRevisions: first.runtimeRevisions,
      candidates: [action]
    ))
    let runtimeOnly = compiler.compile(PlotterUICompilerInput(
      revision: first.revision,
      runtimeRevisions: [PlotterUIRuntimeRevision(owner: "Drawing", token: "13")],
      candidates: [action]
    ))

    #expect(UIOnly.revision != first.revision)
    #expect(UIOnly.runtimeRevisions == first.runtimeRevisions)
    #expect(runtimeOnly.revision == first.revision)
    #expect(runtimeOnly.runtimeRevisions != first.runtimeRevisions)
  }

  private static var jogRequest: PlotterJogRequest {
    try! PlotterJogRequest(
      direction: .positiveX,
      distanceMM: 1,
      feedMMPerMinute: 100,
      routing: .relativeTravel
    )
  }
}

@MainActor
private struct UIWorkspaceFixture {
  let workspace: OperatorWorkspace
  let incidentService: PlotterIncidentPackageUIService
  let incidentProvider: UnavailableIncidentSourceProbe

  func projection(
    manualDraft: ManualMotionDraft = ManualMotionDraft(),
    pendingDrawingPlacement: PlotterDrawingDraftCameraPlacement? = nil,
    pendingPointSelection: PlotterPointSelectionSubmission? = nil
  ) -> PlotterAppUIProjection {
    workspace.plotterUIProjection(
      selectedItemID: .humanGuidedDiscovery(.penInteraction),
      manualDraft: manualDraft,
      includesLearningPath: true,
      pendingDrawingPlacement: pendingDrawingPlacement,
      pendingPointSelection: pendingPointSelection
    )
  }
}

@MainActor
private func makeProductionWorkspace() -> UIWorkspaceFixture {
  let incidentProvider = UnavailableIncidentSourceProbe()
  let incidentService = PlotterIncidentPackageUIService(sourceProvider: incidentProvider)
  let cameraActions = CameraComposition.makeIsolatedActionsForTesting()
  let manualMotionComposition = PlotterManualMotionComposition.production
  let penInteractionRuntime = PlotterPenInteractionComposition.makeRuntime(
    machineActions: MachineSessionComposition.actions,
    simulatedAdapter: manualMotionComposition.causalSimulatorEffectAdapter
  )
  let workspace = OperatorWorkspace(
    cameraActions: cameraActions,
    manualMotionComposition: manualMotionComposition,
    penInteractionRuntime: penInteractionRuntime,
    drawingDraftRuntime: PlotterDrawingDraftRuntime(),
    drawingRunComposition: PlotterDrawingRunComposition.make(
      machineActions: MachineSessionComposition.actions,
      cameraActions: cameraActions
    ),
    incidentPackageUIService: incidentService,
    serialDevices: [],
    serialDeviceDiscovery: { [] },
    loadSelectedSerialIdentifier: { nil },
    persistSelectedSerialIdentifier: { _ in },
    loadPenCapAppearanceSelection: { nil },
    persistPenCapAppearanceSelection: { _ in },
    loadOverlayPreference: { nil },
    persistOverlayPreference: { _ in }
  )
  return UIWorkspaceFixture(
    workspace: workspace,
    incidentService: incidentService,
    incidentProvider: incidentProvider
  )
}

private actor UnavailableIncidentSourceProbe: PlotterIncidentPackageUISourceProvider {
  private(set) var loadCount = 0

  func loadExactSource(
    for _: PlotterIncidentPackageUIRequest
  ) async -> PlotterIncidentPackageUISourceLoadOutcome {
    loadCount += 1
    return .unavailable(.noCompleteSourceProvider)
  }
}

private func refusalReason(
  _ disposition: PlotterUIRequestDisposition
) -> PlotterUIRequestRefusalReason? {
  guard case .refused(let refusal) = disposition else { return nil }
  return refusal.reason
}

private func runtimeRevision(
  owner: String,
  in projection: PlotterUIProjection
) -> PlotterUIRuntimeRevision? {
  projection.runtimeRevisions.first { $0.owner == owner }
}

private func exactFrameReference() -> PlotterExactFrameReference {
  PlotterExactFrameReference(
    frameID: "ui-actionability-frame",
    frameSHA256: String(repeating: "1", count: 64),
    source: .simulated,
    cameraConfigurationID: CameraConfigurationID(),
    captureNanoseconds: 1,
    sequence: 1,
    width: 9,
    height: 9,
    rowBytes: 9,
    pixelFormat: .gray8
  )
}

private func pointSelectionSubmission() -> PlotterPointSelectionSubmission {
  PlotterPointSelectionSubmission(
    selectionID: PlotterPointSelectionID(),
    frame: exactFrameReference(),
    point: try! Point2<CameraPixelSpace>(x: 4, y: 4),
    presentationTransformRevision: PlotterPresentationTransformRevision()
  )
}
