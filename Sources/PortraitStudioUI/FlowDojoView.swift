import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PlotterModel
import PlotterRuntime
import PortraitArtists
import PortraitCore
import PortraitLibrary

/// The single authoring journey: explore a source, prune, rank, fit, and repeat.
package struct FlowDojoView: View {
  @Bindable package var model: FlowDojoModel
  @Bindable package var camera: PortraitStudioModel
  package var selectCamera: () async -> String? = { nil }
  package var handoffTitle = "Export Drawing"
  package var handoff: ((Data) async -> String?)? = nil
  @State private var importing = false
  @State private var cameraSettings = false
  @State private var curating = false
  @State private var curationSourceID: UUID?
  @State private var curationExcluded = false
  @State private var subject = ""
  @State private var session = ""
  @State private var captureBusy = false
  @State private var message: String?

  package init(model: FlowDojoModel, camera: PortraitStudioModel,
    selectCamera: @escaping () async -> String? = { nil }, handoffTitle: String = "Export Drawing",
    handoff: ((Data) async -> String?)? = nil) {
    self.model = model; self.camera = camera; self.selectCamera = selectCamera
    self.handoffTitle = handoffTitle; self.handoff = handoff
  }

  package var body: some View {
    VStack(spacing: 0) {
      acquisitionBar.padding(12)
      if model.document?.purpose == .validationFixture {
        Text("VALIDATION PORTFOLIO — test-created judgments, not your artistic preferences")
          .font(.caption.weight(.semibold)).foregroundStyle(.orange).padding(.bottom, 6)
      }
      Divider()
      HSplitView {
        portfolioSidebar.frame(minWidth: 190, idealWidth: 220, maxWidth: 300)
        VStack(alignment: .leading, spacing: 12) {
          stageBar
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
        if model.isBusy { Button("Cancel") { model.cancel() }.keyboardShortcut(.escape, modifiers: []) }
        Text(model.directory.lastPathComponent).font(.caption).foregroundStyle(.secondary).help(model.directory.path)
      }.padding(8)
    }
    .accessibilityIdentifier("flowDojo.workspace")
    .task { await model.open() }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg]) { result in
      Task {
        do {
          let url = try result.get()
          let bytes = try await Task.detached { try FlowDojoFiles.readImage(url) }.value
          await model.addPhoto(data: bytes, title: url.deletingPathExtension().lastPathComponent,
            mediaType: url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg")
        } catch { message = error.localizedDescription }
      }
    }
    .alert("Portrait Studio", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
      Button("OK") { message = nil }
    } message: { Text(message ?? "") }
    .background {
      PortraitScreenIllumination(isActive: camera.screenIlluminationActive) {
        Task { await camera.cancelRendering() }
      }
    }
  }

  private var acquisitionBar: some View {
    HStack(spacing: 10) {
      Text("Flow Edge Dojo").font(.title2.weight(.semibold))
      Button("Import Photo", systemImage: "photo.badge.plus") { importing = true }
        .accessibilityIdentifier("flowDojo.importPhoto")
      Button(camera.isCapturing ? "Cancel Capture" : "Capture Photo", systemImage: "camera") {
        if camera.isCapturing { Task { await camera.cancelRendering() }; return }
        captureBusy = true
        Task {
          defer { captureBusy = false }
          if let error = await selectCamera() { message = error; return }
          guard camera.cameraIsRunning else { message = "Choose an available portrait camera first."; return }
          if let photo = await camera.captureForPortfolio(strokeStyle: model.strokeStyle) {
            await model.addPhoto(data: photo.data, title: photo.label)
          } else if let error = camera.cameraStatus { message = error }
        }
      }.disabled(!camera.isCapturing && (captureBusy || camera.selectedDeviceID == nil))
      Button { cameraSettings.toggle() } label: { Image(systemName: "slider.horizontal.3") }
        .help("Camera settings").popover(isPresented: $cameraSettings) {
          VStack(alignment: .leading) {
            Text("Portrait camera").font(.headline)
            Picker("Camera", selection: $camera.selectedDeviceID) {
              Text("Choose camera").tag(Optional<CameraDeviceID>.none)
              ForEach(camera.devices) { Text($0.name).tag(Optional($0.id)) }
            }.disabled(camera.isCapturing || camera.cameraIsStarting)
          }.padding().frame(width: 300)
        }
      Spacer()
      Menu("Portfolio") {
        Button("Open Portfolio…") { Task { if let url = await FlowDojoFiles.openPortfolio() { await model.switchPortfolio(to: url) } } }
        Button("New Portfolio…") { Task { if let url = await FlowDojoFiles.newPortfolio() { await model.switchPortfolio(to: url) } } }
      }
      Button(handoffTitle, systemImage: "square.and.arrow.up") {
        Task {
          do {
            let bytes = try await model.exportPackage()
            if let handoff { message = await handoff(bytes) }
            else if let url = await FlowDojoFiles.exportDrawing() { try await Task.detached { try bytes.write(to: url, options: .atomic) }.value }
          } catch { message = error.localizedDescription }
        }
      }.disabled(model.candidate == nil || model.program?.strokes.count == model.removedIndices.count)
        .accessibilityIdentifier("flowDojo.exportDrawing")
    }.disabled(model.isBusy || model.needsRecovery).controlSize(.regular)
  }

  private var portfolioSidebar: some View {
    List {
      Section("Photos") {
        ForEach(model.document?.sources ?? []) { source in
          Button { Task { await model.selectSource(source.id) } } label: {
            HStack {
              Image(systemName: source.excluded ? "eye.slash" : "photo")
              Text(source.title).lineLimit(2)
              Spacer(minLength: 0)
              if source.id == model.selectedSource?.id { Image(systemName: "checkmark") }
            }.contentShape(Rectangle())
          }.buttonStyle(.plain)
        }
      }
      if let source = model.selectedSource {
        Section("Rounds for this photo") {
          ForEach((model.document?.rounds ?? []).filter { $0.sourceID == source.id }.reversed()) { round in
            Button {
              Task { await model.selectRound(round.id) }
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(round.parentCandidateID == nil ? "Broad exploration" : "Refinement")
                Text("\(round.candidateIDs.count) drawings · \(round.status.rawValue)").font(.caption).foregroundStyle(.secondary)
              }
            }.buttonStyle(.plain)
          }
        }
      }
    }.listStyle(.sidebar).disabled(model.isBusy || model.needsRecovery)
  }

  private var stageBar: some View {
    HStack {
      Picker("Curation stage", selection: $model.stage) {
        ForEach(FlowDojoModel.Stage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.segmented).frame(maxWidth: 480)
      Spacer()
      if let source = model.selectedSource {
        Button(source.excluded ? "Source excluded" : "Curate source") {
          curationSourceID = source.id; curationExcluded = source.excluded
          subject = source.subjectID ?? ""; session = source.sessionID ?? ""; curating = true
        }.popover(isPresented: $curating) { sourceCuration }
      }
    }.disabled(model.isBusy || model.needsRecovery)
  }

  private var sourceCuration: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Source identity & training").font(.headline)
      Text("Optional identities keep related photos together during evaluation.").font(.caption).foregroundStyle(.secondary)
      TextField("Subject identity (optional)", text: $subject)
        .onSubmit { saveSourceGroups() }
      TextField("Photo session (optional)", text: $session)
        .onSubmit { saveSourceGroups() }
      Toggle("Include this source in training", isOn: Binding(
        get: { !curationExcluded },
        set: { value in curationExcluded = !value; saveSourceGroups() }))
      Text("Edits and drawings remain in the portfolio when excluded.").font(.caption).foregroundStyle(.secondary)
    }.padding().frame(width: 340)
      .onChange(of: subject) { _, _ in saveSourceGroups() }
      .onChange(of: session) { _, _ in saveSourceGroups() }
  }
  private func saveSourceGroups() {
    guard let id = curationSourceID else { return }
    let subject = subject, session = session, excluded = curationExcluded
    Task { await model.curateSource(sourceID: id, subject: subject, session: session, excluded: excluded) }
  }

  private var exploration: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 14) {
        if let data = model.sourceData { FlowDojoImage(data: data).frame(width: 100, height: 110) }
        VStack(alignment: .leading, spacing: 8) {
          Text(model.selectedSource?.title ?? "Choose a photo to begin").font(.title3.weight(.semibold))
          Text("Explore different Flow Edge constructions, choose a direction, then refine it or remove lines.")
            .foregroundStyle(.secondary)
          HStack {
            Stepper("\(model.count) drawings", value: $model.count, in: 3...9).fixedSize()
            Button("Broad exploration") { Task { await model.generate(refining: false) } }
              .disabled(model.selectedSource == nil)
              .accessibilityIdentifier("flowDojo.broad")
            Button("Refine chosen drawing") { Task { await model.generate(refining: true) } }
              .disabled(model.candidate == nil)
              .accessibilityIdentifier("flowDojo.refine")
            Button("Prune chosen drawing") { model.stage = .prune }.disabled(model.candidate == nil)
          }
        }
      }.disabled(model.isBusy || model.needsRecovery)
      if let round = model.round, !round.failures.isEmpty {
        Text("\(round.failures.count) proposal(s) unavailable: " + round.failures.map(\.message).joined(separator: "; "))
          .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
      }
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
          ForEach(model.roundCandidates) { candidate in
            VStack(alignment: .leading, spacing: 6) {
              FlowDojoImage(data: model.previews[candidate.id]).frame(height: 220)
              HStack {
                Text("Drawing \(candidate.slot + 1)").font(.headline)
                Spacer()
                if candidate.id == model.round?.recommendedCandidateID { Label("Recommended", systemImage: "sparkle").font(.caption) }
              }
              HStack {
                Button(model.candidate?.id == candidate.id ? "Chosen" : "Choose") { Task { await model.selectCandidate(candidate.id) } }
                  .buttonStyle(.borderedProminent).tint(model.candidate?.id == candidate.id ? .green : .accentColor)
                  .accessibilityIdentifier("flowDojo.choose.\(candidate.slot)")
                Button("Prune") { Task { await model.selectCandidate(candidate.id, prune: true) } }
                Spacer()
                Button { Task { await model.excludeCandidate(candidate, excluded: !candidate.excluded) } } label: {
                  Image(systemName: candidate.excluded ? "eye.slash" : "eye")
                }.help(candidate.excluded ? "Include in training" : "Exclude from training")
              }.disabled(model.isBusy || model.needsRecovery)
              Text("\(candidate.strokeCount) source lines" + (candidate.excluded ? " · excluded" : ""))
                .font(.caption).foregroundStyle(.secondary)
            }.padding(10).background(.background, in: RoundedRectangle(cornerRadius: 8))
              .overlay { RoundedRectangle(cornerRadius: 8).stroke(model.candidate?.id == candidate.id ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1) }
          }
        }.padding(2)
      }
      if model.roundCandidates.isEmpty && !model.isBusy {
        ContentUnavailableView("Build your portfolio", systemImage: "pencil.and.outline",
          description: Text("Import or capture a photo, then start broad exploration. Every drawing and choice is saved automatically."))
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var pruning: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let program = model.program {
        HStack {
          Picker("Tool", selection: $model.tool) { ForEach(PortraitLineEditModel.Tool.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            .pickerStyle(.segmented).frame(width: 320)
          Button("Delete Selected") { Task { await model.edit(.remove, ids: model.selection) } }.disabled(model.selection.isEmpty)
          Button("Undo") { Task { await model.edit(.undo) } }.disabled(model.prune?.undoOperationIDs.isEmpty != false)
          Button("Redo") { Task { await model.edit(.redo) } }.disabled(model.prune?.redoOperationIDs.isEmpty != false)
        }.disabled(model.isBusy || model.needsRecovery || model.showsOriginal || model.showsPhoto)
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
            .accessibilityIdentifier("flowDojo.finishPruning")
        }
        if model.prune?.action == .completeTarget {
          Text("Completed selection target retained for training. Further edits create a new unfinished revision.").font(.caption).foregroundStyle(.secondary)
        }
        GeometryReader { proxy in
          if model.showsPhoto { FlowDojoImage(data: model.sourceData).frame(maxWidth: .infinity, maxHeight: .infinity) }
          else {
            ScrollView([.horizontal, .vertical]) {
              FlowDojoCanvas(model: model, program: program)
                .frame(width: max(100, proxy.size.width * model.zoom), height: max(100, proxy.size.height * model.zoom))
            }
          }
        }
      } else {
        ContentUnavailableView("Choose a drawing", systemImage: "cursorarrow", description: Text("Choose a result from an exploration round to remove or restore whole lines."))
      }
    }
  }

  private var rankings: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Rank by artistic preference").font(.title3.weight(.semibold))
      Text("1 is your favorite. Equal ranks are ties; unranked drawings supply no preference. Each change is saved.").foregroundStyle(.secondary)
      PortraitAdaptiveRow {
        Button("Random set: this round") { if let round = model.round { Task { await model.presentRanking(scope: .round(round.id)) } } }.disabled(model.round == nil)
        Button("This drawing’s revisions") { if let candidate = model.candidate { Task { await model.presentRanking(scope: .candidate(candidate.id)) } } }.disabled(model.candidate == nil)
        Button("Random set: this photo") { if let source = model.selectedSource { Task { await model.presentRanking(scope: .source(source.id)) } } }.disabled(model.selectedSource == nil)
        Button("Random set: portfolio") { Task { await model.presentRanking(scope: .portfolio) } }
      }.disabled(model.isBusy || model.needsRecovery)
      PortraitAdaptiveRow {
        if !(model.document?.presentations.isEmpty ?? true) {
          Menu("Previous comparisons") {
            ForEach((model.document?.presentations ?? []).reversed()) { presentation in
              Button(presentation.createdAt.formatted(date: .abbreviated, time: .shortened) + " · \(presentation.items.count) drawings") {
                Task { await model.selectPresentation(presentation.id) }
              }
            }
          }
        }
        Button("Neither / none worth keeping") { Task { await model.declineRanking(neither: true) } }.disabled(model.presentation == nil)
        Button("Skip") { Task { await model.declineRanking(neither: false) } }.disabled(model.presentation == nil)
      }.disabled(model.isBusy || model.needsRecovery)
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
          ForEach(model.presentation?.items ?? []) { item in
            VStack(spacing: 8) {
              FlowDojoImage(data: model.rankingPreviews[item.id]).frame(height: 240)
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
    VStack(alignment: .leading, spacing: 12) {
      Text("Train your Flow Edge artist").font(.title3.weight(.semibold))
      Text("Fit a parameter preference model and a line-deletion model from this portfolio. Activate a checkpoint to recommend drawings and propose removals in new rounds.")
        .foregroundStyle(.secondary)
      HStack {
        Button("Fit portfolio") { Task { await model.fit() } }.buttonStyle(.borderedProminent)
          .disabled(model.isBusy || model.needsRecovery || model.document?.candidates.isEmpty != false)
          .accessibilityIdentifier("flowDojo.fit")
        Button("Use untrained exploration") { Task { await model.activate(nil) } }
          .disabled(model.isBusy || model.needsRecovery || model.document?.activeFitID == nil)
        Text(model.activeCheckpoint == nil ? "No active checkpoint" : "Active: " + [model.activeCheckpoint?.ranker == nil ? nil : "preference", model.activeCheckpoint?.deleter == nil ? nil : "deletion"].compactMap { $0 }.joined(separator: " + ") + (model.activeCheckpoint?.isExperimental == true ? " · experimental" : "")).font(.caption).foregroundStyle(.secondary)
      }
      if let summary = model.reportSummary { Text(summary).font(.callout).textSelection(.enabled) }
      if let report = model.fitReport {
        Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 6) {
          GridRow { Text("Model"); Text("Training loss"); Text("Holdout loss"); Text("Baseline loss"); Text("Train / holdout observations") }
          reportRow("Parameter preference", report.ranker)
          reportRow("Line deletion", report.deleter)
        }.font(.caption).padding(10).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
        Text("Deletion at deployment threshold · precision \(metric(report.deleter.deploymentPrecision)) · recall \(metric(report.deleter.deploymentRecall)) · correction rate \(metric(report.deleter.deploymentCorrectionRate)) · keep-all baseline \(metric(report.deleter.keepAllCorrectionRate))")
          .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      }
      List((model.document?.fits ?? []).reversed()) { fit in
        HStack {
          VStack(alignment: .leading) {
            Text(fit.createdAt.formatted(date: .abbreviated, time: .shortened))
            Text("Checkpoint \(fit.id.uuidString.prefix(8))").font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Button("Results") { Task { await model.showReport(fit.id) } }
          Button(model.document?.activeFitID == fit.id ? "Active" : "Activate") { Task { await model.activate(fit.id) } }
            .disabled(model.document?.activeFitID == fit.id || !fit.hasCheckpoint)
        }
      }.disabled(model.isBusy || model.needsRecovery)
      Text("Rankings train artistic preference. Remove/restore corrections train line decisions. Finish pruning declares a complete selection target. Fitting results report held-out evidence separately from training fit.")
        .font(.caption).foregroundStyle(.secondary)
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
  private func metric(_ value: Double?) -> String { value.map { String(format: "%.4f", $0) } ?? "Unavailable" }

}

package struct FlowDojoImage: View {
  package let data: Data?
  package var body: some View {
    if let data, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit() }
    else { Rectangle().fill(.quaternary).overlay { Image(systemName: "photo").foregroundStyle(.secondary) } }
  }
}

private struct FlowDojoCanvas: NSViewRepresentable {
  let model: FlowDojoModel
  let program: DrawingProgram
  func makeNSView(context: Context) -> PortraitLineEditorNSView { PortraitLineEditorNSView() }
  func updateNSView(_ view: PortraitLineEditorNSView, context: Context) {
    view.model = nil; view.program = program
    view.removed = model.showsOriginal ? [] : model.removedIDs
    view.selected = model.selection
    view.editingEnabled = !model.isBusy && !model.needsRecovery && !model.showsOriginal && !model.showsPhoto
    view.tool = model.tool
    view.onSelection = { model.selection = $0 }
    view.onRemove = { ids in Task { await model.edit(.remove, ids: ids) } }
    view.onRestore = { ids in Task { await model.edit(.restore, ids: ids) } }
    view.onUndo = { Task { await model.edit(.undo) } }
    view.onRedo = { Task { await model.edit(.redo) } }
    view.needsDisplay = true
  }
}
