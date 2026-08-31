import PlotterEpisodeRuntime

@MainActor
final class PlotterApplicationRuntimeArtifactResetRelay:
  PlotterArtifactResetEffectPort,
  PlotterArtifactResetPersistencePort
{
  weak var application: PlotterApplicationRuntime?

  func execute(_ request: PlotterArtifactResetEffectRequest) async
    -> PlotterArtifactResetEffectResult
  {
    guard let application, !application.isShutdown else {
      return .cancelled("The application is shutting down.")
    }
    return await application.executeArtifactResetEffect(request)
  }

  func persist(_ request: PlotterArtifactResetPersistenceRequest) async
    -> PlotterArtifactResetPersistenceResult
  {
    guard let application, !application.isShutdown else {
      return .cancelled("The application is shutting down.")
    }
    return await application.persistArtifactReset(request)
  }
}

struct PlotterArtifactResetComposition: Sendable {
  let runtime: PlotterArtifactResetRuntime
  let relay: PlotterApplicationRuntimeArtifactResetRelay

  @MainActor
  static func make() -> Self {
    let relay = PlotterApplicationRuntimeArtifactResetRelay()
    return Self(
      runtime: PlotterArtifactResetRuntime(effectPort: relay, persistencePort: relay),
      relay: relay
    )
  }

  @MainActor
  func install(on application: PlotterApplicationRuntime) {
    relay.application = application
  }
}
