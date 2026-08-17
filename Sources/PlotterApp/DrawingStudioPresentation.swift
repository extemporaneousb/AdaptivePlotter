import PlotterModel
import PlotterRuntime
import SwiftUI

struct DrawingStudioParameterID: RawRepresentable, Hashable, Sendable {
  let rawValue: String
}

enum DrawingStudioParameterValue: Hashable, Sendable {
  case scalar(Double)
  case integer(Int)
  case choice(String)
  case toggle(Bool)

  var displayText: String {
    switch self {
    case .scalar(let value): String(format: "%.2f", value)
    case .integer(let value): String(value)
    case .choice(let value): value
    case .toggle(let value): value ? "On" : "Off"
    }
  }
}

enum DrawingStudioParameterControl: Hashable, Sendable {
  case scalar(range: ClosedRange<Double>, step: Double, unit: String)
  case integer(range: ClosedRange<Int>, step: Int, unit: String)
  case choices([String])
  case toggle
}

struct DrawingStudioParameterPresentation: Hashable, Identifiable, Sendable {
  let id: DrawingStudioParameterID
  let title: String
  let detail: String
  let value: DrawingStudioParameterValue
  let control: DrawingStudioParameterControl
}

struct DrawingStudioCatalogItemPresentation: Hashable, Identifiable, Sendable {
  let id: DrawingCatalogEntryID
  let title: String
  let detail: String
  let systemImage: String

  init(
    id: DrawingCatalogEntryID,
    title: String,
    detail: String,
    systemImage: String
  ) {
    self.id = id
    self.title = title
    self.detail = detail
    self.systemImage = systemImage
  }

  init(catalogEntry: DrawingProgramCatalogEntry) {
    id = catalogEntry.id
    title = catalogEntry.displayName
    detail = String(
      format: "Built-in vector program · %.0f × %.0f field units%@",
      catalogEntry.fieldExtent.width,
      catalogEntry.fieldExtent.height,
      catalogEntry.supportsCurveTessellation ? " · deterministic curve tessellation" : ""
    )
    systemImage = Self.systemImage(for: catalogEntry.id)
  }

  static var builtInCatalog: [Self] {
    DrawingProgramCatalog.entries.map(Self.init(catalogEntry:))
  }

  private static func systemImage(for id: DrawingCatalogEntryID) -> String {
    switch id {
    case .line: "line.diagonal"
    case .polyline: "scribble"
    case .rectangle: "rectangle"
    case .square: "square"
    case .triangle: "triangle"
    case .regularPolygon: "hexagon"
    case .circle: "circle"
    case .ellipse: "oval"
    case .star: "star"
    case .pyramid: "pyramid"
    case .elephant: "pawprint"
    }
  }
}

struct DrawingStudioPlacementPresentation: Hashable, Sendable {
  let centerCameraPixel: Point2<CameraPixelSpace>?
  let uniformScale: Double
  let allowedScale: ClosedRange<Double>
  let rotationDegrees: Double
  let placementIsEnabled: Bool

  var locationText: String {
    guard let centerCameraPixel else { return "Drag the target onto the video" }
    return String(
      format: "Camera X %.1f Y %.1f", centerCameraPixel.x, centerCameraPixel.y)
  }

  var transformText: String {
    String(format: "Scale %.2f× · Rotation %.1f°", uniformScale, rotationDegrees)
  }
}

enum DrawingStudioTargetPreviewStatus: Hashable, Sendable {
  case unavailable(reason: String)
  case outsideDrawableRegion(reason: String)
  case ready

  var label: String {
    switch self {
    case .unavailable: "Target unavailable"
    case .outsideDrawableRegion: "Outside drawable region"
    case .ready: "Target preview ready"
    }
  }

  var detail: String? {
    switch self {
    case .unavailable(let reason), .outsideDrawableRegion(let reason): reason
    case .ready: nil
    }
  }
}

/// Planned target geometry projected onto one exact displayed frame. The same
/// program hash must be carried into execution by the coordinator; this view
/// has no promotion or motion authority.
struct DrawingStudioTargetPreview: Hashable, Sendable {
  let provenance: ExactFrameOverlayProvenance
  let strokes: [Polyline<CameraPixelSpace>]
  let bounds: AxisAlignedBounds<CameraPixelSpace>?
  let programContentHash: String
  let executionPlanContentHash: String?
  let status: DrawingStudioTargetPreviewStatus

  func matches(_ displayedFrame: DisplayedFrame) -> Bool {
    provenance.matches(displayedFrame)
  }
}

struct DrawingStudioCanvasPresentation: Hashable, Sendable {
  let placement: DrawingStudioPlacementPresentation
  let targetPreview: DrawingStudioTargetPreview?

  func targetPreview(for displayedFrame: DisplayedFrame?) -> DrawingStudioTargetPreview? {
    guard let displayedFrame, let targetPreview, targetPreview.matches(displayedFrame) else {
      return nil
    }
    return targetPreview
  }
}

enum DrawingStudioRunState: Hashable, Sendable {
  case unavailable(reason: String)
  case ready(detail: String)
  case running(capabilityID: ContextualStopCapabilityID, detail: String)
  case processing(detail: String)
  case reviewAvailable(runID: String, detail: String)
  case reviewing(runID: String, detail: String)

  var title: String {
    switch self {
    case .unavailable: "Run unavailable"
    case .ready: "Ready to run"
    case .running: "Drawing in progress"
    case .processing: "Processing drawing evidence"
    case .reviewAvailable: "Run review available"
    case .reviewing: "Reviewing drawing run"
    }
  }

  var detail: String {
    switch self {
    case .unavailable(let reason), .ready(let reason), .running(_, let reason),
      .processing(let reason),
      .reviewAvailable(_, let reason), .reviewing(_, let reason):
      reason
    }
  }
}

enum DrawingStudioAction: Hashable, Sendable {
  case selectCatalogItem(DrawingCatalogEntryID)
  case setParameter(DrawingStudioParameterID, DrawingStudioParameterValue)
  case placeAtCameraPoint(Point2<CameraPixelSpace>)
  case setUniformScale(Double)
  case setRotationDegrees(Double)
  case centerInDrawableRegion
  case run
  case stop(ContextualStopCapabilityID)
  case reviewRun
  case resumeLivePreview
  case newRun
}

struct DrawingStudioControl: Hashable, Identifiable, Sendable {
  let action: DrawingStudioAction
  let title: String
  let systemImage: String
  let role: OperatorButtonRole
  let isEnabled: Bool

  var id: DrawingStudioAction { action }

  init(
    action: DrawingStudioAction,
    title: String,
    systemImage: String,
    role: OperatorButtonRole,
    isEnabled: Bool = true
  ) {
    self.action = action
    self.title = title
    self.systemImage = systemImage
    self.role = role
    self.isEnabled = isEnabled
  }
}

struct DrawingStudioPresentation: Hashable, Sendable {
  let catalog: [DrawingStudioCatalogItemPresentation]
  let selectedCatalogItemID: DrawingCatalogEntryID?
  let sourceParameters: [DrawingStudioParameterPresentation]
  let canvas: DrawingStudioCanvasPresentation
  let editingIsEnabled: Bool
  let runState: DrawingStudioRunState

  init(
    catalog: [DrawingStudioCatalogItemPresentation],
    selectedCatalogItemID: DrawingCatalogEntryID?,
    sourceParameters: [DrawingStudioParameterPresentation],
    canvas: DrawingStudioCanvasPresentation,
    editingIsEnabled: Bool,
    runState: DrawingStudioRunState
  ) {
    self.catalog = catalog
    self.selectedCatalogItemID = selectedCatalogItemID
    self.sourceParameters = sourceParameters
    self.canvas = DrawingStudioCanvasPresentation(
      placement: DrawingStudioPlacementPresentation(
        centerCameraPixel: canvas.placement.centerCameraPixel,
        uniformScale: canvas.placement.uniformScale,
        allowedScale: canvas.placement.allowedScale,
        rotationDegrees: canvas.placement.rotationDegrees,
        placementIsEnabled: canvas.placement.placementIsEnabled && editingIsEnabled
      ),
      targetPreview: canvas.targetPreview
    )
    self.editingIsEnabled = editingIsEnabled
    self.runState = runState
  }

  var selectedCatalogItem: DrawingStudioCatalogItemPresentation? {
    guard let selectedCatalogItemID else { return nil }
    return catalog.first { $0.id == selectedCatalogItemID }
  }

  var controls: [DrawingStudioControl] {
    let center = DrawingStudioControl(
      action: .centerInDrawableRegion,
      title: "Center Target",
      systemImage: "scope",
      role: .neutral,
      isEnabled: editingIsEnabled
    )
    switch runState {
    case .unavailable:
      return [center]
    case .ready:
      return [
        center,
        DrawingStudioControl(
          action: .run,
          title: "Run Drawing",
          systemImage: "play.fill",
          role: .affirmative,
          isEnabled: editingIsEnabled
        ),
      ]
    case .running(let capabilityID, _):
      return [
        DrawingStudioControl(
          action: .stop(capabilityID),
          title: "Stop",
          systemImage: "stop.fill",
          role: .negative
        )
      ]
    case .processing:
      return []
    case .reviewAvailable:
      return [
        DrawingStudioControl(
          action: .reviewRun,
          title: "Review Run",
          systemImage: "square.stack.3d.up",
          role: .neutral
        ),
        DrawingStudioControl(
          action: .newRun,
          title: "New Drawing",
          systemImage: "plus",
          role: .affirmative
        ),
      ]
    case .reviewing:
      return [
        DrawingStudioControl(
          action: .resumeLivePreview,
          title: "Resume Live Preview",
          systemImage: "video.fill",
          role: .neutral
        ),
        DrawingStudioControl(
          action: .newRun,
          title: "New Drawing",
          systemImage: "plus",
          role: .affirmative
        ),
      ]
    }
  }
}

/// Selection and transform shell for an already-projected drawing program.
/// Every mutation is returned as a typed intent; the view owns no planner,
/// controller, evidence store, or readiness decision.
struct DrawingStudioView: View {
  let presentation: DrawingStudioPresentation
  let perform: (DrawingStudioAction) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Drawing Studio")
          .font(.title3.bold())
        Text(
          "Select a deterministic drawing program, place its projected target, then run the exact reviewed plan."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      catalog
      if let selected = presentation.selectedCatalogItem {
        Text(selected.detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      sourceParameters
      placement
      runStatus
      controls
    }
    .padding(12)
    .accessibilityElement(children: .contain)
  }

  private var catalog: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Drawing program").font(.headline)
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(presentation.catalog) { item in
            Button {
              perform(.selectCatalogItem(item.id))
            } label: {
              VStack(spacing: 5) {
                Image(systemName: item.systemImage)
                  .font(.title2)
                Text(item.title)
                  .font(.caption)
                  .lineLimit(1)
              }
              .frame(minWidth: 76, minHeight: 58)
            }
            .buttonStyle(.bordered)
            .tint(item.id == presentation.selectedCatalogItemID ? .accentColor : .secondary)
            .disabled(!presentation.editingIsEnabled)
            .accessibilityHint(item.detail)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var sourceParameters: some View {
    if !presentation.sourceParameters.isEmpty {
      VStack(alignment: .leading, spacing: 9) {
        Text("Source parameters").font(.headline)
        ForEach(presentation.sourceParameters) { parameter in
          parameterControl(parameter)
            .disabled(!presentation.editingIsEnabled)
        }
      }
    }
  }

  @ViewBuilder
  private func parameterControl(_ parameter: DrawingStudioParameterPresentation) -> some View {
    switch (parameter.control, parameter.value) {
    case (.scalar(let range, let step, let unit), .scalar(let value)):
      labeledValue(parameter, value: "\(parameter.value.displayText) \(unit)") {
        Slider(
          value: Binding(
            get: { value },
            set: { perform(.setParameter(parameter.id, .scalar($0))) }
          ),
          in: range,
          step: step
        )
      }
    case (.integer(let range, let step, let unit), .integer(let value)):
      Stepper(
        value: Binding(
          get: { value },
          set: { perform(.setParameter(parameter.id, .integer($0))) }
        ),
        in: range,
        step: step
      ) {
        Text("\(parameter.title): \(value) \(unit)")
      }
      .help(parameter.detail)
    case (.choices(let options), .choice(let value)):
      Picker(
        parameter.title,
        selection: Binding(
          get: { value },
          set: { perform(.setParameter(parameter.id, .choice($0))) }
        )
      ) {
        ForEach(options, id: \.self) { Text($0).tag($0) }
      }
      .help(parameter.detail)
    case (.toggle, .toggle(let value)):
      Toggle(
        parameter.title,
        isOn: Binding(
          get: { value },
          set: { perform(.setParameter(parameter.id, .toggle($0))) }
        )
      )
      .help(parameter.detail)
    default:
      Text("\(parameter.title): incompatible presentation value")
        .font(.caption)
        .foregroundStyle(.orange)
    }
  }

  private func labeledValue<Content: View>(
    _ parameter: DrawingStudioParameterPresentation,
    value: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(parameter.title)
        Spacer()
        Text(value).monospacedDigit().foregroundStyle(.secondary)
      }
      content()
    }
    .help(parameter.detail)
  }

  private var placement: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Placement").font(.headline)
      Label(presentation.canvas.placement.locationText, systemImage: "hand.draw")
        .font(.caption)
      HStack {
        Text("Size")
        Slider(
          value: Binding(
            get: { presentation.canvas.placement.uniformScale },
            set: { perform(.setUniformScale($0)) }
          ),
          in: presentation.canvas.placement.allowedScale
        )
        Text(String(format: "%.2f×", presentation.canvas.placement.uniformScale))
          .monospacedDigit()
          .frame(width: 52, alignment: .trailing)
      }
      .disabled(!presentation.editingIsEnabled)
      HStack {
        Text("Rotation")
        Slider(
          value: Binding(
            get: { presentation.canvas.placement.rotationDegrees },
            set: { perform(.setRotationDegrees($0)) }
          ),
          in: -180...180
        )
        Text(String(format: "%.1f°", presentation.canvas.placement.rotationDegrees))
          .monospacedDigit()
          .frame(width: 58, alignment: .trailing)
      }
      .disabled(!presentation.editingIsEnabled)
    }
  }

  private var runStatus: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(presentation.runState.title).font(.headline)
      Text(presentation.runState.detail)
        .font(.caption)
        .foregroundStyle(.secondary)
      if let preview = presentation.canvas.targetPreview {
        Text("Program \(preview.programContentHash) · \(preview.status.label)")
          .font(.caption2.monospaced())
          .foregroundStyle(preview.status == .ready ? .cyan : .orange)
        if let detail = preview.status.detail {
          Text(detail).font(.caption2).foregroundStyle(.orange)
        }
      }
    }
  }

  private var controls: some View {
    HStack(spacing: 8) {
      ForEach(presentation.controls) { control in
        Button {
          perform(control.action)
        } label: {
          Label(control.title, systemImage: control.systemImage)
        }
        .operatorButton(control.role)
        .disabled(!control.isEnabled)
      }
    }
  }
}
