import PlotterModel
@testable import PlotterRuntime
import Testing

@Suite("Machine position acceptance")
struct MachinePositionAcceptancePolicyTests {
  @Test("Boundary cancellation samples need compatible physical positions, not equal payloads")
  func cancellationUsesSharedSettlementPolicy() throws {
    let settled = try MachinePosition(x: -36.620, y: -72.210)
    let reported = try MachinePosition(x: -36.633, y: -72.210)
    let cancellation = JogCancelOutcome.completed(finalPosition: reported)
    #expect(cancellation != .completed(finalPosition: settled))
    #expect(cancellation.isSettled(at: settled))
    #expect(JogCancelOutcome.completed(finalPosition: try MachinePosition(x: -35.870, y: -72.210))
      .isSettled(at: settled))
    #expect(!JogCancelOutcome.completed(finalPosition: try MachinePosition(x: -35.420, y: -72.210))
      .isSettled(at: settled))
    #expect(!JogCancelOutcome.transmitted.isSettled(at: settled))
  }

  @Test("uses the accepted one-millimetre Euclidean settlement tolerance")
  func usesOneMillimetreTolerance() {
    #expect(MachinePositionAcceptancePolicy.toleranceMM == 1.0)
    #expect(MachinePositionAcceptancePolicy.accepts(residualMM: 1.0))
    #expect(!MachinePositionAcceptancePolicy.accepts(residualMM: 1.001))
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
