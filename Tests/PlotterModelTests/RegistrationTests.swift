import Testing

@testable import PlotterModel

@Suite("Registration and drawing transform")
struct RegistrationTests {
  @Test("affine registration fits the supplied correspondences")
  func fitRegistration() throws {
    func mapped(_ x: Double, _ y: Double) throws -> RegistrationCorrespondence {
      RegistrationCorrespondence(
        camera: try cameraPoint(x, y),
        field: try fieldPoint(2 * x + 0.5 * y + 3, -0.25 * x + 1.5 * y - 4)
      )
    }
    let registration = try FieldRegistration.fit(
      id: IDs.registration,
      correspondences: [
        mapped(0, 0), mapped(10, 0), mapped(0, 10), mapped(12, 7), mapped(-2, 6),
        mapped(3, 4), mapped(8, 2),
      ]
    )
    let result = try registration.fieldPoint(from: cameraPoint(6, 5))
    let expected = try fieldPoint(17.5, 2)
    #expect(result.distance(to: expected) < 1e-9)
    #expect(registration.correspondences.count == 7)
    #expect(registration.maximumError < 1e-9)
  }

  @Test("collinear registration points are rejected")
  func rejectsDegenerateRegistration() throws {
    let samples = try [0.0, 1, 2, 3].map { value in
      RegistrationCorrespondence(
        camera: try cameraPoint(value, value),
        field: try fieldPoint(value, value)
      )
    }
    #expect(throws: RegistrationError.degenerateGeometry) {
      _ = try FieldRegistration.fit(id: IDs.registration, correspondences: samples)
    }
  }

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

  @Test("inverse uses the affine transform and constant correction")
  func inverseForwardCheck() throws {
    let base = try drawingTransform()
    let transform = try DrawingTransform(
      machineToField: base.machineToField,
      constantFieldCorrection: Vector2(dx: 1.5, dy: -2),
      machineDomain: base.machineDomain
    )
    let commanded = try machinePoint(12, 8)
    let desired = try transform.predictedFieldPoint(for: commanded)
    let recovered = try CommandInverter.machinePoint(
      for: desired,
      using: transform,
      maximumForwardError: 1e-9
    )
    #expect(recovered.distance(to: commanded) < 1e-10)
  }

  @Test("inverse refuses commands outside the fixed machine domain")
  func inverseRefusesExtrapolation() throws {
    let transform = try drawingTransform()
    #expect(throws: GeometryError.outsideDomain) {
      _ = try CommandInverter.machinePoint(
        for: fieldPoint(10_000, 10_000),
        using: transform,
        maximumForwardError: 0.01
      )
    }
  }
}
