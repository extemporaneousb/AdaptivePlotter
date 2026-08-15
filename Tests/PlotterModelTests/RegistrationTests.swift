import Testing

@testable import PlotterModel

@Suite("Machine-camera registration")
struct RegistrationTests {
  @Test("machine to camera registration fits current-session correspondences")
  func machineCameraFit() throws {
    func sample(_ x: Double, _ y: Double) throws -> MachineCameraRegistrationCorrespondence {
      MachineCameraRegistrationCorrespondence(
        machine: try Point2(x: x, y: y),
        camera: try Point2(x: 3 * x - 0.5 * y + 200, y: 0.25 * x + 2 * y + 100)
      )
    }
    let fit = try MachineCameraRegistrationFit.fit(correspondences: [
      sample(-10, -8), sample(10, -8), sample(10, 8), sample(-10, 8), sample(0, 0),
    ])
    let projected = try fit.cameraPoint(from: Point2<MachineSpace>(x: 4, y: -3))
    let expectedCamera = try Point2<CameraPixelSpace>(x: 213.5, y: 95)
    #expect(projected.distance(to: expectedCamera) < 1e-9)
    #expect(fit.rootMeanSquareErrorPixels < 1e-9)
    #expect(fit.maximumErrorPixels < 1e-9)
    let recovered = try fit.machinePoint(from: projected)
    let expectedMachine = try Point2<MachineSpace>(x: 4, y: -3)
    #expect(recovered.distance(to: expectedMachine) < 1e-9)
  }
}
