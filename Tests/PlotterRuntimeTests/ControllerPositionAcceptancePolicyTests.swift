import PlotterRuntime
import Testing

@Suite("Controller position acceptance")
struct ControllerPositionAcceptancePolicyTests {
  @Test("accepts a reproduced controller-quantized residual")
  func acceptsQuantizedResidual() throws {
    let target = try MachinePosition(x: -36.620, y: -72.210)
    let actual = try MachinePosition(x: -36.633, y: -72.210)

    let residual = ControllerPositionAcceptancePolicy.residualMM(
      actual,
      from: target
    )
    #expect(abs(residual - 0.013) < 1e-9)
    #expect(ControllerPositionAcceptancePolicy.accepts(residualMM: residual))
    #expect(ControllerPositionAcceptancePolicy.accepts(actual, target: target))
  }

  @Test("rejects a residual beyond the shared tolerance")
  func rejectsOutOfToleranceResidual() throws {
    let target = try MachinePosition(x: 0, y: 0)
    let actual = try MachinePosition(
      x: ControllerPositionAcceptancePolicy.toleranceMM + 0.001,
      y: 0
    )

    #expect(!ControllerPositionAcceptancePolicy.accepts(actual, target: target))
  }
}
