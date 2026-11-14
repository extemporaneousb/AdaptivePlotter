import AppKit
import SwiftUI
import PlotterModel
import PlotterRuntime
import PortraitArtists
import PortraitCore
import PortraitLibrary

/// The single authoring journey: explore a source, prune, rank, fit, and repeat.
package struct FlowAuthoringView: View {
  @Bindable package var model: FlowAuthoringModel
  @Bindable package var camera: PortraitStudioModel
  package var selectCamera: () async -> String? = { nil }
  package var handoffTitle = "Export Drawing"
  package var handoff: ((Drawing) async -> String?)? = nil
  package var embedded = false
  package var photoSelected: (PhotoRef?) -> Void = { _ in }
  @State private var showingCamera = false
  @Environment(\.drawingPresentationPolicy) private var presentationPolicy
  @State private var message: String?
  @State private var roundHistory: [UUID] = []
  @State private var restoringHistory = false

  package init(model: FlowAuthoringModel, camera: PortraitStudioModel,
    selectCamera: @escaping () async -> String? = { nil }, handoffTitle: String = "Export Drawing",
    handoff: ((Drawing) async -> String?)? = nil, embedded: Bool = false, photoSelected: @escaping (PhotoRef?) -> Void = { _ in }) {
    self.model = model; self.camera = camera; self.selectCamera = selectCamera
    self.handoffTitle = handoffTitle; self.handoff = handoff
    self.photoSelected = photoSelected; self.embedded = embedded
  }

  package var body: some View {
    VStack(spacing: 0) {
      if !embedded { acquisitionBar.padding(12) }
      if model.document?.purpose == .validationFixture {
        Text("VALIDATION PORTFOLIO — test-created judgments, not your artistic preferences")
          .font(.caption.weight(.semibold)).foregroundStyle(.orange).padding(.bottom, 6)
      }
      Divider()
      HSplitView {
        portfolioSidebar.frame(minWidth: 230, idealWidth: 270, maxWidth: 340)
        VStack(alignment: .leading, spacing: 12) {
          stageBar
          FlowAuthoringTrainingFeedback(model: model)
          switch model.stage {
          case .explore: exploration
          case .prune: pruning
          case .rank: rankings
          case .fit: fitting
          }
        }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      Divider()
      HStack {
        if model.isBusy { ProgressView().controlSize(.small) }
        Text(model.autosaveStatus).font(.caption).foregroundStyle(model.error == nil ? .secondary : .primary)
          .textSelection(.enabled).lineLimit(2)
        Spacer()
        if model.needsRecovery { Button("Recover autosave") { Task { await model.recoverAutosave() } }.disabled(model.isBusy) }
        if model.isBusy { Button("Cancel") { model.cancel() }.keyboardShortcut(.escape, modifiers: presentationPolicy.modalUnavailableReason == nil ? [] : [.command]) }
        Text(model.directory.lastPathComponent).font(.caption).foregroundStyle(.secondary).help(model.directory.path)
      }.padding(8)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("flowAuthoring.workspace")
    .task { await model.open() }
    .onChange(of: model.currentPhotoRef) { _, _ in roundHistory = [] }
    .onChange(of: model.round?.id) { old, new in
      if restoringHistory { restoringHistory = false }
      else if let old, let new, old != new { roundHistory.append(old) }
    }
    .onChange(of: presentationPolicy.modalUnavailableReason) { _, reason in
      if reason != nil { showingCamera = false; FlowAuthoringFiles.cancelPanel() }
    }
    .sheet(isPresented: $showingCamera) {
      FlowAuthoringCameraPanel(model: model, camera: camera, strokeStyle: model.strokeStyle, selectCamera: selectCamera, photoSelected: { photoSelected($0) })
    }
    .overlay(alignment: .bottom) {
      if let message { HStack { Text(message); Button("Dismiss") { self.message = nil } }.padding().background(.regularMaterial) }
    }
    .background {
      PortraitScreenIllumination(isActive: camera.screenIlluminationActive) {
        Task { await camera.cancelRendering() }
      }
    }
  }

  private var acquisitionBar: some View {
    HStack(spacing: 10) {
      Text("Drawing").font(.title2.weight(.semibold))

      Button("Capture Photo", systemImage: "camera") { if permitModal() { showingCamera = true } }
        .accessibilityIdentifier("flowAuthoring.openCamera")
      Spacer()

      Button(handoffTitle, systemImage: "square.and.arrow.up") {
        Task {
          do {
            if let handoff { message = await handoff(try await model.retainedDrawing()) }
            else if permitModal(), let url = await FlowAuthoringFiles.exportDrawing() { try await model.exportDrawing(to: url) }
          } catch { message = error.localizedDescription }
        }
      }.disabled(model.candidate == nil || model.program?.strokes.count == model.removedIndices.count)
        .accessibilityIdentifier("flowAuthoring.exportDrawing")
    }.disabled(model.isBusy || model.needsRecovery).controlSize(.regular)
  }

  private var portfolioSidebar: some View { FlowAuthoringSidebar(model: model, photoSelected: { photoSelected($0) }) }

  private var stageBar: some View {
    HStack {
      Picker("Curation stage", selection: $model.stage) {
        ForEach(FlowAuthoringModel.Stage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.segmented).frame(maxWidth: 480)
      Spacer()
    }.disabled(model.isBusy || model.needsRecovery)
  }

  private func permitModal() -> Bool {
    if let reason = presentationPolicy.modalUnavailableReason { message = reason; return false }
    return true
  }

  private var exploration: some View {
    VStack(alignment: .leading, spacing: 12) {
      explorationControls
      explorationAnchor
      if let round = model.round, !round.failures.isEmpty {
        Text("\(round.failures.count) proposal(s) unavailable: " + round.failures.map(\.message).joined(separator: "; "))
          .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
      }
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
          ForEach(visibleExplorationCandidates) { candidate in
            FlowExplorationCandidateCard(model: model, candidate: candidate)
          }
        }.padding(2)
      }
      if model.roundCandidates.isEmpty && !model.isBusy {
        ContentUnavailableView("Build your portfolio", systemImage: "pencil.and.outline",
          description: Text("Import or capture a photo, then start broad exploration. Every drawing and choice is saved automatically."))
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var explorationControls: some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(alignment: .leading, spacing: 8) {
        Text(model.selectedSource.map(model.photoName) ?? "Choose a photo to begin").font(.title3.weight(.semibold))
        HStack {
          Text(model.currentBranch).font(.callout).foregroundStyle(.secondary)
          if !model.branchAncestors.isEmpty {
            Menu("Parent drawings") {
              ForEach(model.branchAncestors) { parent in
                Button(model.drawingName(parent)) { Task { await model.browseCandidate(parent.id) } }
              }
            }
          }
        }
        PortraitAdaptiveRow {
          Button("Back") {
            guard let id = roundHistory.popLast() else { return }
            restoringHistory = true
            Task { await model.selectRound(id) }
          }.disabled(roundHistory.isEmpty)
            .accessibilityIdentifier("flowAuthoring.back")
            .help("Restore an earlier set without generating drawings or recording preference.")
          Stepper("\(model.count) drawings", value: $model.count, in: 3...9).fixedSize()
          Button("Broad sample") { roundHistory = []; restoringHistory = true; Task { await model.generate(refining: false) } }
            .disabled(model.selectedSource == nil)
            .accessibilityIdentifier("flowAuthoring.broad")
          Button("Choose and refine") { if let id = model.candidate?.id { Task { await model.exploreCandidate(id) } } }
            .disabled(selectedRefinementDisabled)
            .help(selectedRefinementHelp)
            .accessibilityIdentifier("flowAuthoring.refine")
        }
        HStack {
          Button("Edit drawing") { model.beginPruning() }
            .disabled(selectedEditingDisabled)
            .help(selectedEditingHelp)
          Button("Compare this set") { if let round = model.round { Task { await model.presentRanking(scope: .round(round.id), count: 2) } } }.disabled(model.roundCandidates.count < 2 || model.isBusy || model.needsRecovery)
        }
      }
    }.disabled(!model.canNavigateExploration)
  }

  @ViewBuilder private var explorationAnchor: some View {
    if let parentID = model.pendingBroadAnchorID ?? model.pendingExplorationParentID ?? model.round?.parentCandidateID,
      let parent = model.document?.candidates.first(where: { $0.id == parentID }) {
      HStack {
        FlowExplorationAnchor(model: model, candidate: parent, frozenPreview: model.pendingBroadAnchorPreview).frame(width: 120, height: 120)
        VStack(alignment: .leading) {
          Text(model.pendingBroadAnchorID != nil ? "Starting drawing · Broad sample" : "Chosen direction · " + model.drawingName(parent)).font(.headline)
          if model.pendingBroadAnchorID != nil { Text("Preparing broad variations…").foregroundStyle(.secondary); ProgressView().controlSize(.small) }
          else if model.pendingExplorationParentID != nil { Text("Preparing closer variations…").foregroundStyle(.secondary); ProgressView().controlSize(.small) }
          else { Text("Click a drawing below to choose the next direction.").foregroundStyle(.secondary) }
        }
      }
    }
  }

  private var selectedRefinementDisabled: Bool {
    guard let candidate = model.candidate else { return true }
    return !model.canRefineCandidate(candidate)
  }
  private var selectedRefinementHelp: String {
    guard let candidate = model.candidate else { return "Choose this direction and create closer variations." }
    return model.candidateRefinementUnavailableReason(candidate) ?? "Choose this direction and create closer variations."
  }
  private var selectedEditingDisabled: Bool {
    guard let candidate = model.candidate else { return true }
    return model.isBusy || model.needsRecovery || model.candidateUnavailableReason(candidate) != nil
  }
  private var selectedEditingHelp: String {
    guard let candidate = model.candidate else { return "Remove or restore whole lines in this drawing." }
    return model.candidateUnavailableReason(candidate) ?? "Remove or restore whole lines in this drawing."
  }

  private var visibleExplorationCandidates: [FlowPortfolioCandidate] {
    if let id = model.pendingBroadAnchorID,
      let anchor = model.document?.candidates.first(where: { $0.id == id }), model.round?.id == anchor.roundID { return [] }
    if let id = model.pendingExplorationParentID, model.round?.parentCandidateID != id { return [] }
    return model.roundCandidates
  }

  private var pruning: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let program = model.program {
        Text((model.candidate.map(model.drawingName) ?? "Drawing") + " · " + model.currentBranch)
          .font(.callout).foregroundStyle(.secondary).lineLimit(1)
        HStack {
          Picker("Tool", selection: $model.tool) { ForEach(PortraitLineEditModel.Tool.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            .pickerStyle(.segmented).frame(width: 320)
          Button("Delete Selected") { Task { await model.edit(.remove, ids: model.selection) } }.disabled(model.selection.isEmpty)
          Button("Undo") { Task { await model.edit(.undo) } }.disabled(model.prune?.undoOperationIDs.isEmpty != false)
          Button("Redo") { Task { await model.edit(.redo) } }.disabled(model.prune?.redoOperationIDs.isEmpty != false)
        }.disabled(!model.canEdit)
        if let reason = model.editingUnavailableReason {
          HStack {
            Text(reason).font(.callout).foregroundStyle(.secondary)
            if model.showsOriginal || model.showsPhoto { Button("Return to editing") { model.returnToEditing() } }
          }
        }
        HStack {
          Toggle("Original", isOn: $model.showsOriginal).toggleStyle(.button)
          Toggle("Photo", isOn: $model.showsPhoto).toggleStyle(.button)
          Slider(value: $model.zoom, in: 1...4).frame(width: 100)
          Button("Fit") { model.zoom = 1 }
          Text("\(program.strokes.count - model.removedIndices.count) kept · \(model.removedIndices.count) removed").font(.caption)
          Spacer()
          Button("Finish pruning") { Task { await model.edit(.completeTarget) } }
            .disabled(model.isBusy || model.needsRecovery || model.prune?.action == .completeTarget)
            .help("Declare the current kept/removed mask as the intended training target. All edits are already autosaved.")
            .accessibilityIdentifier("flowAuthoring.finishPruning")
        }
        if model.prune?.action == .completeTarget {
          HStack {
            Text("Complete target saved.").font(.caption).foregroundStyle(.secondary)
            Button("Revisions") { if let candidate = model.candidate { Task { await model.presentRanking(scope: .candidate(candidate.id), count: 2) } } }
            Button("Train artist") { model.stage = .fit }
          }
        }
        GeometryReader { proxy in
          if model.showsPhoto { FlowAuthoringImage(data: model.sourceData, identity: model.selectedSource?.image.sha256 ?? "no-source").frame(maxWidth: .infinity, maxHeight: .infinity) }
          else {
            ScrollView([.horizontal, .vertical]) {
              FlowAuthoringCanvas(model: model, program: program)
                .frame(width: max(100, proxy.size.width * model.zoom), height: max(100, proxy.size.height * model.zoom))
            }
          }
        }
      } else {
        ContentUnavailableView("Choose a drawing", systemImage: "cursorarrow", description: Text(model.candidateLoadError ?? "Choose a result from an exploration round to remove or restore whole lines."))
        if model.candidateLoadError != nil { Button("Retry drawing load") { Task { await model.retryCandidateLoad() } }.disabled(model.isBusy || model.needsRecovery) }
      }
    }
  }

  private var rankings: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Rank by artistic preference").font(.title3.weight(.semibold))
      Text("Compare two drawings with one click, or set ranks below. Equal ranks are ties; unranked drawings supply no preference.").foregroundStyle(.secondary)
      PortraitAdaptiveRow {
        Text("Compare pair:").font(.caption).foregroundStyle(.secondary)
        Button("This set") { if let round = model.round { Task { await model.presentRanking(scope: .round(round.id), count: 2) } } }.disabled(model.round == nil)
        Button("Revisions") { if let candidate = model.candidate { Task { await model.presentRanking(scope: .candidate(candidate.id), count: 2) } } }.disabled(model.candidate == nil)
        Button("This photo") { if let source = model.selectedSource { Task { await model.presentRanking(scope: .source(source.id), count: 2) } } }.disabled(model.selectedSource == nil)
        Button("Across photos") { Task { await model.presentRanking(scope: .portfolio, count: 2) } }
        Button("Next pair") { if let presentation = model.presentation { Task { await model.presentRanking(scope: presentation.scope, count: 2) } } }.disabled(model.presentation == nil)
      }.disabled(model.isBusy || model.needsRecovery)
      PortraitAdaptiveRow {
        Menu("Rank a full set") {
          Button("All drawings in this set") { Task { await model.rankCurrentSet() } }.disabled(model.round == nil)
          Button("Random drawings from this photo") { if let source = model.selectedSource { Task { await model.presentRanking(scope: .source(source.id)) } } }.disabled(model.selectedSource == nil)
          Button("Random drawings from portfolio") { Task { await model.presentRanking(scope: .portfolio) } }
        }
        if !(model.document?.presentations.isEmpty ?? true) {
          Menu("Previous comparisons") {
            ForEach((model.document?.presentations ?? []).reversed()) { presentation in
              Button(presentation.createdAt.formatted(date: .abbreviated, time: .shortened) + " · \(presentation.items.count) drawings") {
                Task { await model.selectPresentation(presentation.id) }
              }
            }
          }
        }
        if model.presentation?.items.count == 2 {
          Button("Equal preference") { Task { await model.compare(preferred: nil) } }
        }
        Button("Neither / none worth keeping") { Task { await model.declineRanking(neither: true) } }.disabled(model.presentation == nil)
        Button("Skip") { Task { await model.declineRanking(neither: false) } }.disabled(model.presentation == nil)
      }.disabled(model.isBusy || model.needsRecovery)
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
          ForEach(model.presentation?.items ?? []) { item in
            VStack(spacing: 8) {
              FlowAuthoringImage(data: model.rankingPreviews[item.id], identity: model.rankingPreviewIdentity(item)).frame(height: 240)
              if model.presentation?.items.count == 2 {
                Button("Prefer this drawing") { Task { await model.compare(preferred: item.id) } }
                  .buttonStyle(.borderedProminent).disabled(model.isBusy || model.needsRecovery)
              }
              Picker("Rank", selection: Binding(get: { model.ranks[item.id] ?? 0 }, set: { rank in Task { await model.rank(item: item.id, position: rank) } })) {
                Text("Unranked").tag(0)
                ForEach(1...max(1, model.presentation?.items.count ?? 1), id: \.self) { Text("\($0)").tag($0) }
              }.disabled(model.isBusy || model.needsRecovery)
              Text(item.revisionID == nil ? "Generated drawing" : "Pruned revision · \(item.removedIndices.count) removed")
                .font(.caption).foregroundStyle(.secondary)
            }.padding(10).background(.background, in: RoundedRectangle(cornerRadius: 8))
          }
        }
      }
    }
  }

  private var fitting: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 12) {
        Text("Train your Flow Edge artist").font(.title3.weight(.semibold))
        Text("Fit a parameter preference model and a line-deletion model from this portfolio. Activate a checkpoint to recommend drawings and propose removals in new rounds.")
          .foregroundStyle(.secondary)
        HStack {
          Button("Fit portfolio") { Task { await model.fit() } }.buttonStyle(.borderedProminent)
            .disabled(model.isBusy || model.needsRecovery || model.trainingProgress?.canAttemptFit != true)
            .accessibilityIdentifier("flowAuthoring.fit")
          Button("Use untrained exploration") { Task { await model.activate(nil) } }
            .disabled(model.isBusy || model.needsRecovery || model.document?.activeFitID == nil)
          Text(model.activeCheckpoint == nil ? "No active checkpoint" : "Active: " + [model.activeCheckpoint?.ranker == nil ? nil : "preference", model.activeCheckpoint?.deleter == nil ? nil : "deletion"].compactMap { $0 }.joined(separator: " + ") + (model.activeCheckpoint?.isExperimental == true ? " · experimental" : "")).font(.caption).foregroundStyle(.secondary)
        }
        if let issue = model.activeModelIssue { Text(issue).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
        if let progress = model.trainingProgress {
          Text("\(progress.feedbackPhotoCount) photos with feedback · \(progress.feedbackGroupCount) source groups · \(progress.choiceComparisonCount) choice comparisons · \(progress.rankingComparisonCount) explicit comparisons · \(progress.removeLabelCount) remove / \(progress.keepLabelCount) keep labels")
            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        if let summary = model.reportSummary { Text(summary).font(.callout).textSelection(.enabled) }
        if let report = model.fitReport {
          Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 6) {
            GridRow { Text("Model"); Text("Training loss"); Text("Holdout loss"); Text("Baseline loss"); Text("Train / holdout observations") }
            reportRow("Parameter preference", report.ranker)
            reportRow("Line deletion", report.deleter)
          }.font(.caption).padding(10).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
          Text("Deletion labels · training: \(coverage(report.deleter.trainingRemoveCount)) remove / \(coverage(report.deleter.trainingKeepCount)) keep · holdout: \(coverage(report.deleter.holdoutRemoveCount)) remove / \(coverage(report.deleter.holdoutKeepCount)) keep")
            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
          Text("Deletion at deployment threshold · precision \(metric(report.deleter.deploymentPrecision)) · recall \(metric(report.deleter.deploymentRecall)) · correction rate \(metric(report.deleter.deploymentCorrectionRate)) · keep-all baseline \(metric(report.deleter.keepAllCorrectionRate))")
            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        ForEach((model.document?.fits ?? []).reversed()) { fit in
          HStack {
            VStack(alignment: .leading) {
              Text(fit.createdAt.formatted(date: .abbreviated, time: .shortened))
              Text("Checkpoint \(fit.id.uuidString.prefix(8))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Results") { Task { await model.showReport(fit.id) } }
            Button(model.document?.activeFitID == fit.id ? "Active" : "Activate") { Task { await model.activate(fit.id) } }
              .disabled(model.document?.activeFitID == fit.id || !fit.hasCheckpoint)
          }.padding(10).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        }.disabled(model.isBusy || model.needsRecovery)
        Text("Subject and session identities define source groups for held-out evaluation. Rankings train artistic preference. Remove/restore corrections train line decisions. Finish pruning declares a complete selection target. Fitting results report held-out evidence separately from training fit.")
          .font(.caption).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
  private func reportRow(_ title: String, _ report: FlowArtistHeadReport) -> some View {
    GridRow {
      VStack(alignment: .leading) { Text(title).bold(); Text(report.status).foregroundStyle(.secondary).lineLimit(3) }
      Text(metric(report.trainingLoss)); Text(metric(report.holdoutLoss)); Text(metric(report.baselineLoss))
      VStack(alignment: .leading) {
        Text("\(report.trainingCount) train / \(report.holdoutCount) test")
        Text("\(report.trainingGroupCount) train groups / \(report.holdoutGroupCount) test groups").foregroundStyle(.secondary)
      }
    }
  }
  private func coverage(_ value: Int?) -> String { value.map(String.init) ?? "Unavailable" }
  private func metric(_ value: Double?) -> String { value.map { String(format: "%.4f", $0) } ?? "Unavailable" }

}

package struct FlowAuthoringImage: View {
  package let data: Data?
  package let identity: String
  package let maximumDimension: Int
  private struct Request: Hashable { let identity: String; let dimension: Int; let hasData: Bool }
  @State private var image: NSImage?
  @State private var loadedRequest: Request?
  package init(data: Data?, identity: String, maximumDimension: Int = 2048) {
    self.data = data; self.identity = identity; self.maximumDimension = maximumDimension
  }
  private var request: Request { .init(identity: identity, dimension: maximumDimension, hasData: data != nil) }
  package var body: some View {
    Group {
      if loadedRequest == request, let image { Image(nsImage: image).resizable().scaledToFit() }
      else { Rectangle().fill(.quaternary).overlay { Image(systemName: "photo").foregroundStyle(.secondary) } }
    }.task(id: request) {
      let captured = request
      image = nil; loadedRequest = nil
      guard let data else { return }
      let decoded = await FlowPresentationImageCache.shared.load(data: data, identity: identity,
        maximumDimension: maximumDimension)
      guard !Task.isCancelled else { return }
      image = decoded; loadedRequest = captured
    }
  }
}

private struct FlowAuthoringCanvas: NSViewRepresentable {
  let model: FlowAuthoringModel
  let program: DrawingProgram
  func makeNSView(context: Context) -> PortraitLineEditorNSView { PortraitLineEditorNSView() }
  func updateNSView(_ view: PortraitLineEditorNSView, context: Context) {
    view.model = nil; view.program = program
    view.removed = model.showsOriginal ? [] : model.removedIDs
    view.selected = model.selection
    view.editingEnabled = model.canEdit
    view.tool = model.tool
    view.onSelection = { model.selection = $0 }
    view.onRemove = { ids in Task { await model.edit(.remove, ids: ids) } }
    view.onRestore = { ids in Task { await model.edit(.restore, ids: ids) } }
    view.onUndo = { Task { await model.edit(.undo) } }
    view.onRedo = { Task { await model.edit(.redo) } }
    view.needsDisplay = true
  }
}

private struct FlowExplorationAnchor: View {
  let model: FlowAuthoringModel
  let candidate: FlowPortfolioCandidate
  let frozenPreview: Data?
  @State private var pixels: Data?
  var body: some View {
    FlowAuthoringImage(data: frozenPreview ?? model.previews[candidate.id] ?? pixels, identity: model.previewIdentity(candidate: candidate))
      .task(id: model.previewIdentity(candidate: candidate)) {
        if frozenPreview == nil { pixels = await model.thumbnail(candidate: candidate) }
      }
  }
}
