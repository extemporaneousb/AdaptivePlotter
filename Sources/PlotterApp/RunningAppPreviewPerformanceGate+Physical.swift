import AppKit
import CryptoKit
import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI

/// Harness staging only. This token does not authorize an app action: the real
/// native control still submits its current projection to the existing owner.
struct PhysicalPortraitContinuation: Codable, Equatable, Sendable {
  let sessionID: UUID
  let executableSHA256: String
  let stage: String
  let planSHA256: String?
  let nonce: UUID
}

struct PhysicalPortraitReview: Codable, Sendable {
  let continuation: PhysicalPortraitContinuation
  let continuationPath: String
  let factsPath: String
  let reviewInstruction: String
}

struct PhysicalPortraitReport: Encodable, Sendable {
  let schema = "adaptiveplotter.physical-portrait.v1"
  let sessionID: UUID
  let executablePath: String
  let executableSHA256: String
  let processID: Int32
  let photoPath: String
  let photoSHA256: String
  var state = "preparing"
  var stage: String?
  var review: PhysicalPortraitReview?
  var checkpointID: UUID?
  var nativeInputSamples: [WorkbenchNativeInputSample] = []
  var nativeInputCounts: [String: WorkbenchNativeInputCounts] = [:]
  var planHashes: [String] = []
  var recordIDs: [String] = []
  var manualStopCapabilityID: UUID?
  var manualStopSettled = false
  var drawingStopCapabilities: [UUID] = []
  var failures: [String] = []
  let provenance = "Explicit physical scenario using synthesized native input and existing typed owners. Raw frame copies and immutable archive records are exported before another plan. Controller settlement, visual attribution, native input, and human attendance are distinct; human attendance is not established by this harness. No automatic redraw, shutdown, or app termination."

  var verificationFailures: [String] {
    var reasons = failures
    if !manualStopSettled || manualStopCapabilityID == nil { reasons.append("The physical inkless Stop lacks a capability and controller settlement.") }
    if Set(planHashes).count != 2 || planHashes.count != 2 || Set(recordIDs).count != 2 || recordIDs.count != 2 {
      reasons.append("Two distinct, once-only portrait plans and retained records were not established.")
    }
    if drawingStopCapabilities.count != 2 { reasons.append("Both actual Draw owners must expose their Stop capability.") }
    for (id, required) in [("drawing.draw", 2), ("workbench.stop", 1)] {
      let counts = nativeInputCounts[id]
      if counts?.posted != required || counts?.dispatched != required || counts?.handled != required || counts?.acknowledged != required {
        reasons.append("\(id) does not have exactly \(required) correlated native submissions and acknowledgments.")
      }
    }
    if nativeInputSamples.contains(where: {
      let correlation = WorkbenchNativeEventCorrelation(expectedIdentity: $0.postedEventIdentity)
      return $0.eventUptimeSeconds == nil || !correlation.accepts($0.dispatchedEventIdentity) || !correlation.accepts($0.handledEventIdentity)
    }) { reasons.append("A physical scenario control lacks a correlated posted/dispatch/handler event.") }
    return reasons
  }
}

struct PhysicalControllerObservation: Encodable, Sendable {
  let probe: PassiveProbeResult
  let statusExchangeCommandID: UUID
  let status: ControllerStatusReport
}

private struct PhysicalPortraitFacts: Encodable, Sendable {
  let exportedAt: Date
  let retainedMachineSnapshot: MachineSnapshot?
  let queriedControllerObservation: PhysicalControllerObservation?
  let interpreterOperation: String
  let manualJournalPath: String?
  let cameraRole: String
  let cameraError: String?
  let exactFrame: PlotterExactFrameReference?
  let checkpointID: UUID?
  let completeAcceptedLearning: Bool
  let tipRegistration: TipCameraRegistration?
  let region: DrawableMachineRegion?
  let paperCoverage: PaperCoverageObservation?
  let paperCoverageIsCurrent: Bool
  let plan: ExecutionPlanRevision?
  let drawReadiness: String
  let drawRefusal: String?
  let activeRunID: String?
  let drawingStopCapabilityID: UUID?
  let terminalDisposition: String?
  let evidencePersistence: String
  let plannedInklessJog: String?
}

extension RunningAppPreviewPerformanceGate {
  static func runPhysicalPortrait(application: PlotterApplicationRuntime,
    configuration: RunningAppPreviewPerformanceConfiguration,
    revealPanel: @escaping @MainActor (WorkbenchPanel) -> Void) async {
    let sessionID = UUID()
    let directory = configuration.reportURL.deletingLastPathComponent()
      .appendingPathComponent("physical-\(sessionID.uuidString)", isDirectory: true)
    let probe = RunningAppNativeInputProbe()
    var report = PhysicalPortraitReport(sessionID: sessionID,
      executablePath: Bundle.main.executableURL?.path ?? "unavailable", executableSHA256: "unavailable",
      processID: ProcessInfo.processInfo.processIdentifier, photoPath: configuration.portraitPhotoURL?.path ?? "unavailable",
      photoSHA256: "unavailable")
    do {
      guard let executable = Bundle.main.executableURL, let photo = configuration.portraitPhotoURL,
        let controller = configuration.physicalControllerIdentifier else {
        throw WorkbenchNativeInputError.unavailable("Physical scenario requires an exact executable, photo, and controller identifier.")
      }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let retainedPhoto = directory.appendingPathComponent("portrait-source.\(photo.pathExtension)")
      let hashes = try await Task.detached {
        let source = try Data(contentsOf: photo)
        try source.write(to: retainedPhoto, options: .atomic)
        return (Self.physicalSHA(try Data(contentsOf: executable)), Self.physicalSHA(source))
      }.value
      report = PhysicalPortraitReport(sessionID: sessionID, executablePath: executable.path,
        executableSHA256: hashes.0, processID: ProcessInfo.processInfo.processIdentifier,
        photoPath: photo.path, photoSHA256: hashes.1)
      try physicalWrite(report, to: configuration.reportURL)
      probe.install()
      defer { probe.uninstall() }
      revealPanel(.guidedLearning); revealPanel(.portraitStudio); revealPanel(.motion); revealPanel(.video)

      guard application.controllerSessionProjection.environment == .live else {
        throw WorkbenchNativeInputError.unavailable("Physical scenario requires the live environment.")
      }
      let devices = application.controllerSessionProjection.serialDevices.filter {
        $0.identifier == controller || $0.bsdPath == controller
      }
      guard devices.count == 1, let device = devices.first else {
        throw WorkbenchNativeInputError.unavailable("The explicitly selected controller is not uniquely available: \(controller).")
      }
      try await submit(PlotterAppUIActionID.controllerDevice(device.identifier), application: application)
      if !application.controllerSessionProjection.sessionEstablished {
        let before = RunningAppNativeInputProbe.controlLabel("workbench.controller.connect")
        report.nativeInputSamples.append(try await probe.click("workbench.controller.connect") {
          RunningAppNativeInputProbe.controlLabel("workbench.controller.connect") != before
        })
      }
      try await awaitWorkload("Controller connection and its existing passive probe did not settle.") {
        application.controllerSessionProjection.sessionEstablished
          && application.machineSnapshot?.lastProbe != nil
      }
      if application.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint == nil {
        let current = projection(application)
        guard let saved = current.semantic.actions.first(where: {
          if case .learningAction(let request) = $0.intent { return request.action == .applySavedLearning }
          return false
        }) else { throw WorkbenchNativeInputError.unavailable("No current Use Saved Learning action is available.") }
        try await submit(saved.id, application: application, projection: current)
      }
      guard application.interactiveLearningIsComplete,
        let checkpoint = application.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint else {
        throw WorkbenchNativeInputError.unavailable("Saved Learning did not restore all accepted milestones.")
      }
      report.checkpointID = checkpoint.checkpointID
      try await selectCamera(.plotter, application: application)
      try await awaitWorkload("No exact live plotter frame is available for physical review.") {
        guard let id = application.cameraSnapshot?.selectedDeviceID else { return false }
        return application.cameraIsLive && application.displayedFrame?.source == .live(id)
          && application.displayedFrame?.plotterExactFrameReferenceIfMaterialized != nil
      }

      let controllerObservation = try await physicalControllerObservation(
        projection: application.controllerSessionProjection, sink: application)
      guard let position = controllerObservation.status.machinePosition?.point,
        let region = application.currentDrawableMachineRegion, region.contains(position) else {
        throw WorkbenchNativeInputError.unavailable("The fresh controller position is not within the accepted drawable region; inspect the retained facts before choosing any physical trial.")
      }
      let positive = position.x <= (region.effectiveBounds.minX + region.effectiveBounds.maxX) / 2
      let endpoint = try Point2<MachineSpace>(x: position.x + (positive ? 2 : -2), y: position.y)
      guard region.contains(endpoint) else {
        throw WorkbenchNativeInputError.unavailable("The accepted region has no 2 mm inward X trial from the fresh controller position.")
      }
      let jog = positive ? PlotterAppUIActionID.manualXPositive : PlotterAppUIActionID.manualXNegative
      let jogDetail = "Pen Up; \(jog.rawValue); 2 mm at 60 mm/min; start (\(position.x), \(position.y)), endpoint (\(endpoint.x), \(endpoint.y))."
      try await physicalReview(application, configuration: configuration, directory: directory,
        report: &report, stage: "inkless-stop", instruction: "Inspect current plotter frame, paper/mechanism and fresh controller facts. Continuation performs only the stated Pen Up bounded jog and native Stop. Human attendance is recorded separately.", jog: jogDetail)
      let refreshed = try await physicalControllerObservation(
        projection: application.controllerSessionProjection, sink: application)
      guard refreshed.status.machinePosition?.point == position else {
        throw WorkbenchNativeInputError.unavailable("Controller position changed while the inkless trial was under review; no jog was submitted.")
      }
      if !application.controllerSessionProjection.motionAuthorized {
        let before = RunningAppNativeInputProbe.controlLabel("workbench.controller.motion")
        report.nativeInputSamples.append(try await probe.click("workbench.controller.motion") {
          RunningAppNativeInputProbe.controlLabel("workbench.controller.motion") != before
        })
      }
      try await awaitWorkload("The existing controller owner did not enable Motion.") { application.controllerSessionProjection.motionAuthorized }
      if application.machineSnapshot?.machine.penState != .up {
        let before = RunningAppNativeInputProbe.panelText()[WorkbenchPanel.motion.rawValue]
        report.nativeInputSamples.append(try await probe.click("motion.penUp") {
          RunningAppNativeInputProbe.panelText()[WorkbenchPanel.motion.rawValue] != before
        })
      }
      try await awaitWorkload("Pen Up did not settle through the existing owner.") {
        application.machineSnapshot?.machine.penState == .up && application.manualMotionEpisodeSnapshot?.activeOperation == nil
      }
      for (id, value) in [("motion.xDistance", "2"), ("motion.feed", "60")] {
        report.nativeInputSamples.append(try await probe.click(id, replacementText: value) {
          RunningAppNativeInputProbe.controlValue(id)?.hasPrefix(value + "|") == true
        })
      }
      report.nativeInputSamples.append(try await probe.click(jog.rawValue) {
        RunningAppNativeInputProbe.controlValue(jog.rawValue)?.contains("enabled=false") == true
      })
      try await awaitWorkload("The native jog callback did not expose an active bounded-motion owner; do not retry.") {
        application.manualMotionEpisodeSnapshot?.activeOperation?.stopCapabilityID != nil
      }
      guard let stop = application.manualMotionEpisodeSnapshot?.activeOperation?.stopCapabilityID else {
        throw WorkbenchNativeInputError.unavailable("The bounded jog exposed no active Stop capability; do not repeat the jog.")
      }
      report.manualStopCapabilityID = stop.rawValue
      let stops = WorkbenchStopPresentation.actions(in: projection(application).semantic)
      guard stops.count == 1, case .manualStop(let projectedStop) = stops[0].intent,
        projectedStop == stop.rawValue else {
        throw WorkbenchNativeInputError.unavailable("Global Stop does not project the exact active manual capability; retain the bounded trial for inspection.")
      }
      let beforeStop = RunningAppNativeInputProbe.controlValue("workbench.stop")
      report.nativeInputSamples.append(try await probe.click("workbench.stop") {
        RunningAppNativeInputProbe.controlValue("workbench.stop") != beforeStop
      })
      try await awaitWorkload("Native Stop was handled, but controller/manual-owner settlement was not established.") {
        let current = await application.refreshControllerSessionSnapshot()
        return application.manualMotionEpisodeSnapshot?.activeOperation == nil
          && current?.currentOperation == .idle && current?.machine.operationInFlight == false
          && current?.machine.controllerState == .idle && Self.physicalStopSettled(current)
      }
      report.manualStopSettled = true
      try await physicalExportFacts(application, directory: directory, name: "inkless-stop-settled", jog: jogDetail)

      try await selectCamera(.portrait, application: application)
      application.portraitStudio.style = .contours
      await application.portraitStudio.importPhoto(retainedPhoto, strokeStyle: application.drawingStrokeStyle)
      await application.portraitStudio.awaitRendering()
      guard let program = application.portraitStudio.program, !program.strokes.isEmpty else {
        throw WorkbenchNativeInputError.unavailable("The imported face produced no drawing: \(application.portraitStudio.summary)")
      }
      report.nativeInputSamples.append(try await probe.click("portrait.showOnPlotter") {
        RunningAppNativeInputProbe.controlValue("portrait.showOnPlotter")?.contains("Preparing") == true
          || RunningAppNativeInputProbe.controlValue("workbench.camera.plotter")?.contains("Selected") == true
      })
      try await awaitWorkload("Show on Plotter Video did not settle with the imported portrait plan.") {
        application.workbenchCameraRole == .plotter && !application.cameraRoleIsTransitioning
          && application.drawingDraftSnapshot.program?.contentHash == program.contentHash
          && application.drawingDraftSnapshot.plan != nil
          && RunningAppNativeInputProbe.controlValue("portrait.showOnPlotter")?.contains("Preparing") == false
      }
      var priorPlan: ExecutionPlanRevision?
      for index in 1...2 {
        if index == 2 {
          guard let first = application.drawingRunSnapshot?.terminal, first.disposition == .succeeded else {
            throw WorkbenchNativeInputError.unavailable("The first portrait is not a successful attributable terminal; the second will not be submitted.")
          }
          try await submit(PlotterAppUIActionID.drawingRun(.beginNewRun(first.runID)), application: application)
        }
        try await submit(PlotterAppUIActionID.drawingDraft(.fitInDrawableRegion), application: application)
        try await submit(PlotterAppUIActionID.drawingDraft(.setUniformScale(application.drawingDraftSnapshot.uniformScale * 0.45)), application: application)
        guard let registration = application.tipCameraRegistration,
          let frame = application.displayedFrame?.plotterExactFrameReferenceIfMaterialized else {
          throw WorkbenchNativeInputError.unavailable("Current exact frame and accepted registration are required for portrait placement.")
        }
        let bounds = region.effectiveBounds
        let center = try Point2<MachineSpace>(x: bounds.minX + (bounds.maxX - bounds.minX) * (index == 1 ? 0.25 : 0.75),
          y: (bounds.minY + bounds.maxY) / 2)
        let placement = PlotterDrawingDraftCameraPlacement(frame: frame,
          point: try registration.cameraFromMachine.applying(to: center))
        let current = application.plotterUIProjection(selectedItemID: .humanGuidedDiscovery(.penInteraction),
          manualDraft: ManualMotionDraft(), includesLearningPath: true, pendingDrawingPlacement: placement)
        try await submit(PlotterAppUIActionID.drawingDraft(.placeAtCameraPoint(placement)), application: application, projection: current)
        guard let plan = application.drawingDraftSnapshot.plan,
          plan.strokes.allSatisfy({ region.contains($0.path) }),
          priorPlan.map({ Self.physicalPlansDoNotOverlap($0, plan) }) ?? true else {
          throw WorkbenchNativeInputError.unavailable("The actual two immutable portrait plans are not distinct, contained, and nonoverlapping.")
        }
        report.planHashes.append(plan.contentHash.description)
        try await physicalReview(application, configuration: configuration, directory: directory,
          report: &report, stage: "portrait-\(index)", instruction: "Inspect exact frame PNG, complete immutable plan, paper coverage, controller readiness, and prior terminal exports. Continuation asserts the current sheet covers this target and clicks Draw once. On uncertain existing ink, leave this stage uncontinued; no redraw is automatic.")
        guard application.drawingDraftSnapshot.plan == plan,
          application.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint?.checkpointID == checkpoint.checkpointID else {
          throw WorkbenchNativeInputError.unavailable("The reviewed portrait plan or accepted Learning changed; no Draw was submitted.")
        }
        try await submit(PlotterAppUIActionID.drawingDraft(.assertPaperCoverage), application: application)
        guard application.drawingDraftSnapshot.plan == plan else {
          throw WorkbenchNativeInputError.unavailable("Paper assertion changed the reviewed plan; no Draw was submitted.")
        }
        try await awaitWorkload("Draw remains unavailable: \(String(describing: application.drawingRunSnapshot?.readiness)).") {
          application.drawingRunSnapshot?.readiness == .ready
        }
        let before = RunningAppNativeInputProbe.controlValue("drawing.draw")
        report.nativeInputSamples.append(try await probe.click("drawing.draw") {
          RunningAppNativeInputProbe.controlValue("drawing.draw") != before
        })
        try await awaitWorkload("The native Draw callback did not expose an active run; inspect its displayed refusal and retained facts, and do not retry.") {
          application.drawingRunSnapshot?.stopCapabilityID != nil || application.drawingRunSnapshot?.terminal != nil
            || application.drawingRunSnapshot?.lastRefusal != nil
        }
        guard let active = application.drawingRunSnapshot, let stop = active.stopCapabilityID,
          active.planIdentity?.planRevisionID == plan.revisionID,
          active.planIdentity?.planContentHash == plan.contentHash else {
          throw WorkbenchNativeInputError.unavailable("Draw did not expose the exact reviewed active plan and its Stop capability; do not retry.")
        }
        report.drawingStopCapabilities.append(stop.rawValue)
        let projectedStops = WorkbenchStopPresentation.actions(in: projection(application).semantic)
        guard projectedStops.count == 1, case .drawingRun(.stop(let projectedStop)) = projectedStops[0].intent,
          projectedStop == stop else {
          throw WorkbenchNativeInputError.unavailable("Global Stop does not project the exact active drawing capability; inspect the retained active run.")
        }
        report.state = "drawing"; report.review = nil
        try physicalWrite(report, to: configuration.reportURL)
        let deadline = ContinuousClock.now.advanced(by: .seconds(configuration.durationSeconds))
        while application.drawingRunSnapshot?.terminal == nil {
          guard ContinuousClock.now < deadline else {
            throw WorkbenchNativeInputError.unavailable("Portrait \(index) exceeded the bounded observation deadline; app and active owner remain available for Stop and review. Do not resend Draw.")
          }
          try await Task.sleep(for: .milliseconds(100))
        }
        guard let completed = application.drawingRunSnapshot, let terminal = completed.terminal else {
          throw WorkbenchNativeInputError.unavailable("The completed run disappeared before its immutable evidence could be retained; no next Draw is submitted.")
        }
        // Copy the first immutable record and both exact pixel buffers before
        // beginNewRun can release that owner's in-memory frame pair.
        try physicalWrite(terminal.record, to: directory.appendingPathComponent("portrait-\(index)-record.json"))
        if let baseline = completed.baselineFrame {
          try await physicalExportFrame(baseline, directory: directory, name: "portrait-\(index)-baseline")
        }
        if let post = completed.postFrame {
          try await physicalExportFrame(post, directory: directory, name: "portrait-\(index)-post")
        }
        try await physicalExportFacts(application, directory: directory, name: "portrait-\(index)-terminal")
        report.recordIDs.append(terminal.record.recordID.rawValue.uuidString)
        try physicalWrite(report, to: configuration.reportURL)
        guard terminal.planIdentity.planRevisionID == plan.revisionID,
          terminal.record.plan.executionPlan == plan, terminal.record.role == .ordinaryDrawing,
          terminal.disposition == .succeeded,
          let baseline = completed.baselineFrame, let post = completed.postFrame,
          case .observed(let observed) = terminal.record.observation,
          observed.frames.source == baseline.source, post.source == baseline.source,
          observed.frames.baseline == ExactFrameProvenance(frame: baseline.frame),
          observed.frames.post == ExactFrameProvenance(frame: post.frame),
          case .persisted(let persisted, _) = completed.evidencePersistence,
          persisted == terminal.record.recordID else {
          throw WorkbenchNativeInputError.unavailable("Portrait \(index) retained \(terminal.disposition), or lacks exact persisted plan/frame evidence. Inspect its record and possible ink; no next Draw is submitted.")
        }
        priorPlan = plan
      }
      report.state = "completed"
      report.review = nil
    } catch {
      report.state = "failed"
      report.failures.append(String(describing: error))
      FileHandle.standardError.write(Data("Physical portrait scenario stopped: \(error). App and evidence retained.\n".utf8))
      try? await physicalExportFacts(application, directory: directory, name: "failure")
    }
    report.nativeInputCounts = probe.counts
    if report.state == "completed", !report.verificationFailures.isEmpty {
      report.failures = report.verificationFailures
      report.state = "failed"
    }
    do { try physicalWrite(report, to: configuration.reportURL) }
    catch { FileHandle.standardError.write(Data("Physical report export failed: \(error). App retained.\n".utf8)) }
    // Neither success nor failure settles a retained owner by killing the app.
    try? Data(report.state.utf8)
      .write(to: configuration.readyMarkerURL.appendingPathExtension("finished"), options: .atomic)
  }

  private static func physicalReview(_ application: PlotterApplicationRuntime,
    configuration: RunningAppPreviewPerformanceConfiguration, directory: URL,
    report: inout PhysicalPortraitReport, stage: String, instruction: String, jog: String? = nil) async throws {
    try await physicalExportFacts(application, directory: directory, name: stage, jog: jog,
      requiresFreshControllerStatus: true)
    let token = PhysicalPortraitContinuation(sessionID: report.sessionID, executableSHA256: report.executableSHA256,
      stage: stage, planSHA256: application.drawingDraftSnapshot.plan?.contentHash.description, nonce: UUID())
    let continuationURL = directory.appendingPathComponent("\(stage)-continue.json")
    let review = PhysicalPortraitReview(continuation: token, continuationPath: continuationURL.path,
      factsPath: directory.appendingPathComponent("\(stage)-facts.json").path, reviewInstruction: instruction)
    report.state = "awaiting-review"; report.stage = stage; report.review = review
    try physicalWrite(report, to: configuration.reportURL)
    try physicalWrite(review, to: configuration.readyMarkerURL)
    let deadline = ContinuousClock.now.advanced(by: .seconds(configuration.durationSeconds))
    while ContinuousClock.now < deadline {
      if FileManager.default.fileExists(atPath: continuationURL.path) {
        let received = try JSONDecoder().decode(PhysicalPortraitContinuation.self, from: Data(contentsOf: continuationURL))
        guard received == token else {
          throw WorkbenchNativeInputError.unavailable("Continuation does not identify this exact session, executable, stage, and plan; no motion was submitted.")
        }
        report.review = nil
        return
      }
      try await Task.sleep(for: .milliseconds(250))
    }
    throw WorkbenchNativeInputError.unavailable("Review stage \(stage) timed out without its exact continuation. App and artifacts retained; no stage action was submitted.")
  }

  private static func physicalExportFacts(_ application: PlotterApplicationRuntime, directory: URL,
    name: String, jog: String? = nil, requiresFreshControllerStatus: Bool = false) async throws {
    let observation = requiresFreshControllerStatus
      ? try await physicalControllerObservation(projection: application.controllerSessionProjection, sink: application) : nil
    // This copy is retained context. Only the separately exported query result
    // dates a controller observation; export time never dates an MPos sample.
    let machine = application.machineSnapshot
    let frame = application.displayedFrame
    let run = application.drawingRunSnapshot
    let draw = projection(application).semantic.actions.first { $0.id == PlotterAppUIActionID.drawingRun(.start) }
    let facts = PhysicalPortraitFacts(exportedAt: Date(), retainedMachineSnapshot: machine?.machine,
      queriedControllerObservation: observation,
      interpreterOperation: String(describing: machine?.currentOperation),
      manualJournalPath: application.manualMotionEpisodeSnapshot?.journal.fileURL.path,
      cameraRole: application.workbenchCameraRole.rawValue, cameraError: application.cameraRoleError ?? application.cameraError,
      exactFrame: frame?.plotterExactFrameReferenceIfMaterialized,
      checkpointID: application.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint?.checkpointID,
      completeAcceptedLearning: application.interactiveLearningIsComplete, tipRegistration: application.tipCameraRegistration,
      region: application.currentDrawableMachineRegion, paperCoverage: application.drawingDraftSnapshot.paperCoverageObservation,
      paperCoverageIsCurrent: application.paperCoverageIsCurrent, plan: application.drawingDraftSnapshot.plan,
      drawReadiness: String(describing: run?.readiness), drawRefusal: draw?.unavailableReason,
      activeRunID: run?.activeRunID?.rawValue.uuidString, drawingStopCapabilityID: run?.stopCapabilityID?.rawValue,
      terminalDisposition: run?.terminal.map { String(describing: $0.disposition) },
      evidencePersistence: String(describing: run?.evidencePersistence), plannedInklessJog: jog)
    try physicalWrite(facts, to: directory.appendingPathComponent("\(name)-facts.json"))
    if let frame { try await physicalExportFrame(frame, directory: directory, name: name + "-review") }
  }

  static func physicalControllerObservation(projection: PlotterControllerSessionProjection,
    sink: any PlotterControllerSessionIntentSink) async throws -> PhysicalControllerObservation {
    let result = await sink.submitControllerSessionRequest(projection.request(.requestPassiveProbe))
    guard case .completed(.liveSession(_, let probe?, nil)) = result,
      probe.blockers.isEmpty,
      let exchange = probe.exchanges.last(where: { $0.query == .status && $0.completed && $0.blocker == nil }),
      let status = exchange.latestStatusReport, status.machinePosition != nil else {
      throw WorkbenchNativeInputError.unavailable("The existing controller query owner did not return a completed status/MPos observation: \(String(describing: result)). Cached position is not fresh measurement evidence.")
    }
    return PhysicalControllerObservation(probe: probe, statusExchangeCommandID: exchange.commandID, status: status)
  }

  private nonisolated static func physicalExportFrame(_ frame: DisplayedFrame, directory: URL, name: String) async throws {
    try await Task.detached(priority: .utility) {
      // A bounded export of existing immutable bytes, awaited before proceeding.
      try physicalWrite(frame, to: directory.appendingPathComponent(name + "-frame.json"))
      try frame.frame.bytes.data.write(to: directory.appendingPathComponent(name + ".pixels"), options: .atomic)
      guard let image = FrameImageFactory.image(from: frame.frame) else { throw PortraitDrawingError.unreadableImage }
      try PortraitImageAnalyzer.encodedImage(image).write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
    }.value
  }

  nonisolated static func physicalPlansDoNotOverlap(_ first: ExecutionPlanRevision, _ second: ExecutionPlanRevision) -> Bool {
    guard first.contentHash != second.contentHash, first.revisionID != second.revisionID else { return false }
    let a = first.strokes.flatMap { $0.path.points }, b = second.strokes.flatMap { $0.path.points }
    guard let aMin = a.map(\.x).min(), let aMax = a.map(\.x).max(),
      let bMin = b.map(\.x).min(), let bMax = b.map(\.x).max() else { return false }
    let margin = max(first.strokes.map { $0.style.nominalLineWidth }.max() ?? 0, second.strokes.map { $0.style.nominalLineWidth }.max() ?? 0)
    return aMax + margin < bMin || bMax + margin < aMin
  }

  private nonisolated static func physicalStopSettled(_ snapshot: RunInterpreterSnapshot?) -> Bool {
    guard let snapshot, let position = snapshot.machine.position,
      case .completed(let stoppedPosition) = snapshot.lastJogCancelOutcome else { return false }
    return MachinePositionAcceptancePolicy.accepts(stoppedPosition, target: position)
  }

  private nonisolated static func physicalSHA(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private nonisolated static func physicalWrite<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(value).write(to: url, options: .atomic)
  }
}
