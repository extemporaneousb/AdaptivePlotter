import PlotterEpisodeRuntime

/// Composition only forwards one typed request to the application's atomic
/// controller/camera/Vision transaction. It never manufactures completion.
@MainActor
final class PlotterApplicationRuntimeCameraCalibrationEffectPort: PlotterCameraCalibrationEffectPort {
  weak var application: PlotterApplicationRuntime?

  init(application: PlotterApplicationRuntime) { self.application = application }

  func execute(_ request: PlotterCameraCalibrationEffectRequest) async
    -> PlotterCameraCalibrationEffectResult
  {
    guard let application, !application.isShutdown else { return .cancelled }
    return await application.executeCameraCalibrationEffect(request)
  }
}
