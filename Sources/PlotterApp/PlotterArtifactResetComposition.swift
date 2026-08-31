import PlotterEpisodeRuntime

@MainActor
final class OperatorWorkspaceArtifactResetRelay:
  PlotterArtifactResetEffectPort,
  PlotterArtifactResetPersistencePort
{
  weak var workspace: OperatorWorkspace?

  func execute(_ request: PlotterArtifactResetEffectRequest) async
    -> PlotterArtifactResetEffectResult
  {
    guard let workspace, !workspace.isShutdown else {
      return .cancelled("The workspace is shutting down.")
    }
    return await workspace.executeArtifactResetEffect(request)
  }

  func persist(_ request: PlotterArtifactResetPersistenceRequest) async
    -> PlotterArtifactResetPersistenceResult
  {
    guard let workspace, !workspace.isShutdown else {
      return .cancelled("The workspace is shutting down.")
    }
    return await workspace.persistArtifactReset(request)
  }
}

struct PlotterArtifactResetComposition: Sendable {
  let runtime: PlotterArtifactResetRuntime
  let relay: OperatorWorkspaceArtifactResetRelay

  @MainActor
  static func make() -> Self {
    let relay = OperatorWorkspaceArtifactResetRelay()
    return Self(
      runtime: PlotterArtifactResetRuntime(effectPort: relay, persistencePort: relay),
      relay: relay
    )
  }

  @MainActor
  func install(on workspace: OperatorWorkspace) {
    relay.workspace = workspace
  }
}
