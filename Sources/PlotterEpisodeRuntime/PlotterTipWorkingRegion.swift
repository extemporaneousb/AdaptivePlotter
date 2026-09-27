import Foundation
import PlotterEpisodeModel
import PlotterModel
import PlotterRuntime

/// Admission facts for the pre-mark paper working extent. A cap map locates a
/// guide only: it is not a tip registration or a paper-coverage observation.
public struct PlotterTipWorkingRegionContext: Hashable, Sendable {
  public let boundary: AxisAlignedBounds<MachineSpace>
  public let boundaryRevisionIDs: Set<LearningArtifactRevisionID>
  public let machineMap: MachineCameraRegistration
  public let machineMapRevision: LearningArtifactRevisionID
  public let cameraConfigurationID: CameraConfigurationID
  public let controllerSessionID: UUID
  public let paper: PaperRevisionContext
  public let toolAssembly: ToolAssemblyRevision
  public let penContactProfile: PenContactProfileRevision

  public init(boundary: AxisAlignedBounds<MachineSpace>, machineMap: MachineCameraRegistration,
    machineMapRevision: LearningArtifactRevisionID, controllerSessionID: UUID,
    paper: PaperRevisionContext, toolAssembly: ToolAssemblyRevision, penContactProfile: PenContactProfileRevision,
    cameraConfigurationID: CameraConfigurationID? = nil,
    boundaryRevisionIDs: Set<LearningArtifactRevisionID> = []) {
    self.boundary = boundary
    self.boundaryRevisionIDs = boundaryRevisionIDs
    self.machineMap = machineMap
    self.machineMapRevision = machineMapRevision
    self.cameraConfigurationID = cameraConfigurationID ?? machineMap.cameraConfigurationID
    self.controllerSessionID = controllerSessionID
    self.paper = paper
    self.toolAssembly = toolAssembly
    self.penContactProfile = penContactProfile
  }

  public func matchesFrame(_ frame: PlotterExactFrameReference) -> Bool {
    let sourceMatches: Bool = switch (frame.source, machineMap.source) {
    case (.simulated, .simulated): true
    case (.live(let device), .live(let source)): device == source.rawValue
    default: false
    }
    return sourceMatches && frame.cameraConfigurationID == cameraConfigurationID
      && frame.width == machineMap.opticalConfiguration.width
      && frame.height == machineMap.opticalConfiguration.height
  }

  public func contains(_ bounds: AxisAlignedBounds<MachineSpace>) -> Bool {
    TipCalibrationWorkingRegionPolicy.permitsSpan(bounds.maxX - bounds.minX)
      && TipCalibrationWorkingRegionPolicy.permitsSpan(bounds.maxY - bounds.minY)
      && TipCalibrationWorkingRegionPolicy.contains(bounds, in: boundary)
  }
}

public struct PlotterTipWorkingRegionSelection: Hashable, Sendable {
  public let context: PlotterTipWorkingRegionContext
  public let bounds: AxisAlignedBounds<MachineSpace>

  public init(context: PlotterTipWorkingRegionContext, bounds: AxisAlignedBounds<MachineSpace>) {
    self.context = context
    self.bounds = bounds
  }
}

public struct PlotterTipWorkingRegionEdit: Hashable, Sendable {
  public let id: UUID
  public let exactFrame: PlotterExactFrameReference
  public let selection: PlotterTipWorkingRegionSelection

  public init(id: UUID, exactFrame: PlotterExactFrameReference, selection: PlotterTipWorkingRegionSelection) {
    self.id = id
    self.exactFrame = exactFrame
    self.selection = selection
  }
}

public enum PlotterTipWorkingRegionIntent: Hashable, Sendable {
  case begin(PlotterTipWorkingRegionEdit)
  case apply(PlotterTipWorkingRegionEdit, AxisAlignedBounds<MachineSpace>)
  case cancel(UUID)
}
