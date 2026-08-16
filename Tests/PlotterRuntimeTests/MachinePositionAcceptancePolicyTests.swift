import PlotterModel
import PlotterRuntime
import Testing

@Suite("Machine position acceptance")
struct MachinePositionAcceptancePolicyTests {
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

  @Test("rejects a residual beyond the shared tolerance")
  func rejectsOutOfToleranceResidual() throws {
    let target = try MachinePosition(x: 0, y: 0)
    let actual = try MachinePosition(
      x: MachinePositionAcceptancePolicy.toleranceMM + 0.001,
      y: 0
    )

    #expect(!MachinePositionAcceptancePolicy.accepts(actual, target: target))
  }

  @Test("bounds admission uses the shared nonzero machine-space tolerance")
  func boundsAdmissionUsesSharedTolerance() throws {
    let bounds = try AxisAlignedBounds<MachineSpace>(
      minX: 0,
      minY: 0,
      maxX: 100,
      maxY: 100
    )
    let accepted = try MachinePosition(
      x: 100 + MachinePositionAcceptancePolicy.toleranceMM,
      y: 50
    )
    let rejected = try MachinePosition(
      x: 100 + MachinePositionAcceptancePolicy.toleranceMM + 0.001,
      y: 50
    )

    #expect(MachinePositionAcceptancePolicy.contains(accepted, in: bounds))
    #expect(!MachinePositionAcceptancePolicy.contains(rejected, in: bounds))
  }
}
