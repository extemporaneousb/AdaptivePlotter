import PlotterEpisodeRuntime

/// Composition only forwards one typed request to the workspace's atomic
/// controller/camera/Vision transaction. It never manufactures completion.
@MainActor
final class OperatorWorkspaceCameraCalibrationEffectPort: PlotterCameraCalibrationEffectPort {
  weak var workspace: OperatorWorkspace?

  init(workspace: OperatorWorkspace) { self.workspace = workspace }

  func execute(_ request: PlotterCameraCalibrationEffectRequest) async
    -> PlotterCameraCalibrationEffectResult
  {
    guard let workspace, !workspace.isShutdown else { return .cancelled }
    return await workspace.executeCameraCalibrationEffect(request)
  }
}
