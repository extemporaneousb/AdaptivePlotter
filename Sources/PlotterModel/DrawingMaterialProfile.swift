import Foundation

public enum MaterialWidthQualification: String, Codable, Hashable, Sendable {
  case nominal, controllerCoordinateEstimate, independentlyMeasured, bounded, unavailable
}

public struct DirectionalWidthEstimate: Codable, Hashable, Sendable {
  public let directionRadians: Double
  public let medianMM: Double
  public let uncertaintyMM: Double
  public let sampleCount: Int

  public init(directionRadians: Double, medianMM: Double, uncertaintyMM: Double, sampleCount: Int) throws {
    guard directionRadians.isFinite, medianMM.isFinite, medianMM > 0,
      uncertaintyMM.isFinite, uncertaintyMM >= 0, sampleCount > 0 else {
      throw PlotterModelError.invalidValue("Invalid directional deposited width")
    }
    self.directionRadians = directionRadians
    self.medianMM = medianMM
    self.uncertaintyMM = uncertaintyMM
    self.sampleCount = sampleCount
  }
}

public struct DepositedWidthDistribution: Codable, Hashable, Sendable {
  public let medianMM: Double?
  public let lowerBoundMM: Double
  public let upperBoundMM: Double
  public let uncertaintyMM: Double
  public let sampleCount: Int
  public let directional: [DirectionalWidthEstimate]
  public let exclusions: [String: Int]

  public init(medianMM: Double?, lowerBoundMM: Double, upperBoundMM: Double,
    uncertaintyMM: Double, sampleCount: Int, directional: [DirectionalWidthEstimate] = [],
    exclusions: [String: Int] = [:]) throws {
    guard lowerBoundMM.isFinite, lowerBoundMM >= 0, upperBoundMM.isFinite,
      upperBoundMM >= lowerBoundMM, upperBoundMM > 0, uncertaintyMM.isFinite, uncertaintyMM >= 0,
      sampleCount >= 0, medianMM.map({ $0.isFinite && $0 >= lowerBoundMM && $0 <= upperBoundMM }) ?? true,
      exclusions.values.allSatisfy({ $0 >= 0 }) else {
      throw PlotterModelError.invalidValue("Invalid deposited width distribution")
    }
    self.medianMM = medianMM
    self.lowerBoundMM = lowerBoundMM
    self.upperBoundMM = upperBoundMM
    self.uncertaintyMM = uncertaintyMM
    self.sampleCount = sampleCount
    self.directional = directional
    self.exclusions = exclusions
  }
}

/// Material identity is independent of machine geometry and contact authority.
/// Each revision is immutable; a library rejects conflicting reuse of its key.
public struct DrawingMaterialProfileRevision: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public let revision: Int
  public let name: String
  public let nominalWidthMM: Double
  public let qualification: MaterialWidthQualification
  public let depositedWidth: DepositedWidthDistribution?
  public let measurementEvidenceID: UUID?
  public let physicalMetricRevision: String?
  public let createdAt: Date
  public let measurementLimitations: [String]
  public var key: String { "\(id.uuidString.lowercased())@\(revision)" }
  public var conservativeWidthMM: Double {
    depositedWidth.map { $0.upperBoundMM + $0.uncertaintyMM } ?? nominalWidthMM
  }
  public var independentlyMeasured: Bool { qualification == .independentlyMeasured }

  public init(id: UUID = UUID(), revision: Int = 1, name: String, nominalWidthMM: Double,
    qualification: MaterialWidthQualification = .nominal,
    depositedWidth: DepositedWidthDistribution? = nil, measurementEvidenceID: UUID? = nil,
    physicalMetricRevision: String? = nil, createdAt: Date = Date(), measurementLimitations: [String] = []) throws {
    guard revision > 0, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      nominalWidthMM.isFinite, nominalWidthMM > 0,
      depositedWidth.map({ ($0.upperBoundMM + $0.uncertaintyMM).isFinite }) ?? true,
      qualification != .independentlyMeasured || (physicalMetricRevision?.isEmpty == false),
      [.nominal, .unavailable].contains(qualification) || (depositedWidth != nil && measurementEvidenceID != nil)
    else { throw PlotterModelError.invalidValue("Invalid material profile revision") }
    self.id = id; self.revision = revision; self.name = name; self.nominalWidthMM = nominalWidthMM
    self.qualification = qualification; self.depositedWidth = depositedWidth
    self.measurementEvidenceID = measurementEvidenceID; self.physicalMetricRevision = physicalMetricRevision
    self.createdAt = createdAt; self.measurementLimitations = measurementLimitations
  }

  public func validate() throws {
    _ = try Self(id: id, revision: revision, name: name, nominalWidthMM: nominalWidthMM,
      qualification: qualification, depositedWidth: depositedWidth,
      measurementEvidenceID: measurementEvidenceID, physicalMetricRevision: physicalMetricRevision, createdAt: createdAt, measurementLimitations: measurementLimitations)
    if let d = depositedWidth {
      _ = try DepositedWidthDistribution(medianMM: d.medianMM, lowerBoundMM: d.lowerBoundMM,
        upperBoundMM: d.upperBoundMM, uncertaintyMM: d.uncertaintyMM, sampleCount: d.sampleCount,
        directional: d.directional, exclusions: d.exclusions)
      for v in d.directional {
        _ = try DirectionalWidthEstimate(directionRadians: v.directionRadians, medianMM: v.medianMM,
          uncertaintyMM: v.uncertaintyMM, sampleCount: v.sampleCount)
      }
    }
  }
}
