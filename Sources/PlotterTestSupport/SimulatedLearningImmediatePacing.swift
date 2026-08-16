import PlotterRuntime

public struct SimulatedLearningImmediatePacing: SimulatedLearningExecutionPacing, Sendable {
  public init() {}

  public func suspendBetweenSteps() async {
    await Task.yield()
  }
}
