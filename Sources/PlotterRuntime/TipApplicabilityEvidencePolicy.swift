import PlotterModel

public enum DiagnosticTipCameraProjectionApplicability: Hashable, Sendable {
  case insideRecordedApplicability
  case outsideRecordedApplicability
}

/// A mathematical camera projection that carries no camera/ink evidence authority.
/// Callers must explicitly unwrap `cameraPoint` at a presentation-only boundary.
public struct DiagnosticTipCameraProjection: Hashable, Sendable {
  public let registrationRevisionID: LearningArtifactRevisionID
  public let recordedApplicabilityRectangle: AxisAlignedBounds<MachineSpace>
  public let machinePoint: Point2<MachineSpace>
  public let cameraPoint: Point2<CameraPixelSpace>
  public let applicability: DiagnosticTipCameraProjectionApplicability
}

public struct TipApplicabilityEvidenceLimitation: Hashable, Sendable {
  public static let policyRevision = "tip-applicability-evidence-v1"

  public let registrationRevisionID: LearningArtifactRevisionID
  public let recordedApplicabilityRectangle: AxisAlignedBounds<MachineSpace>
  public let firstOutsideMachinePoint: Point2<MachineSpace>
}

/// An unforgeable result from `TipApplicabilityEvidencePolicy`.
/// Importers can inspect its limitation and submit an observer closure, but
/// only this module can construct an attributable projection.
public struct TipApplicabilityEvidenceProjection: Hashable, Sendable {
  fileprivate enum Storage: Hashable, Sendable {
    case attributable([Polyline<CameraPixelSpace>])
    case diagnosticOnly(TipApplicabilityEvidenceLimitation)
  }

  fileprivate let storage: Storage

  fileprivate init(storage: Storage) {
    self.storage = storage
  }

  init(diagnosticLimitation: TipApplicabilityEvidenceLimitation) {
    storage = .diagnosticOnly(diagnosticLimitation)
  }

  public var diagnosticLimitation: TipApplicabilityEvidenceLimitation? {
    guard case .diagnosticOnly(let limitation) = storage else { return nil }
    return limitation
  }

  /// Validated observer input, or nil as a typed refusal to observe. Importers
  /// cannot construct this token or replace its validated storage.
  public var attributableCameraPolylines: [Polyline<CameraPixelSpace>]? {
    guard case .attributable(let intended) = storage else { return nil }
    return intended
  }
}

extension TipCameraRegistration {
  public func diagnosticProjection(
    at machinePoint: Point2<MachineSpace>
  ) throws -> DiagnosticTipCameraProjection {
    DiagnosticTipCameraProjection(
      registrationRevisionID: acceptedRevisionID,
      recordedApplicabilityRectangle: applicabilityRectangle,
      machinePoint: machinePoint,
      cameraPoint: try cameraFromMachine.applying(to: machinePoint),
      applicability: DrawingRegionContainmentPolicy.contains(machinePoint, in: applicabilityRectangle)
        ? .insideRecordedApplicability
        : .outsideRecordedApplicability
    )
  }
}

/// The sole projection policy for geometry that may enter planned camera/ink evidence.
/// One outside point makes the complete plan diagnostic-only; partial attribution is
/// intentionally impossible.
public enum TipApplicabilityEvidencePolicy {
  public static func project(
    paths: [Polyline<MachineSpace>],
    using registration: TipCameraRegistration
  ) throws -> TipApplicabilityEvidenceProjection {
    var projected: [Polyline<CameraPixelSpace>] = []
    projected.reserveCapacity(paths.count)
    for path in paths {
      var projectedPoints: [Point2<CameraPixelSpace>] = []
      projectedPoints.reserveCapacity(path.points.count)
      for machinePoint in path.points {
        guard DrawingRegionContainmentPolicy.contains(machinePoint, in: registration.applicabilityRectangle) else {
          return TipApplicabilityEvidenceProjection(
            storage: .diagnosticOnly(
              TipApplicabilityEvidenceLimitation(
                registrationRevisionID: registration.acceptedRevisionID,
                recordedApplicabilityRectangle: registration.applicabilityRectangle,
                firstOutsideMachinePoint: machinePoint
              )
            )
          )
        }
        projectedPoints.append(try registration.tipPixel(at: machinePoint))
      }
      projected.append(try Polyline(points: projectedPoints))
    }
    return TipApplicabilityEvidenceProjection(storage: .attributable(projected))
  }
}
