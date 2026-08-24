import PlotterModel
import PlotterRuntime
import Testing

@Suite("Machine position acceptance")
struct MachinePositionAcceptancePolicyTests {
  @Test("uses the accepted half-millimetre Euclidean settlement tolerance")
  func usesHalfMillimetreTolerance() {
    #expect(MachinePositionAcceptancePolicy.toleranceMM == 0.5)
    #expect(MachinePositionAcceptancePolicy.accepts(residualMM: 0.5))
    #expect(!MachinePositionAcceptancePolicy.accepts(residualMM: 0.501))
  }

  @Test("accepts a reproduced controller-quantized residual")
  func acceptsQuantizedResidual() throws {
    let target = try MachinePosition(x: -36.620, y: -72.210)
    let actual = try MachinePosition(x: -36.633, y: -72.210)

    let residual = MachinePositionAcceptancePolicy.residualMM(
      actual,
      from: target
    )
    #expect(abs(residual - 0.013) < 1e-9)
    #expect(MachinePositionAcceptancePolicy.accepts(residualMM: residual))
    #expect(MachinePositionAcceptancePolicy.accepts(actual, target: target))
  }

  @Test("rejects a Euclidean residual beyond controller settlement tolerance")
  func rejectsOutOfToleranceResidual() throws {
    let target = try MachinePosition(x: 0, y: 0)
    let actual = try MachinePosition(
      x: MachinePositionAcceptancePolicy.toleranceMM + 0.001,
      y: 0
    )

    #expect(!MachinePositionAcceptancePolicy.accepts(actual, target: target))
  }
}
