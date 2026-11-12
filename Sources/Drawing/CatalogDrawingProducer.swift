import Foundation
import PlotterModel

/// A source-free capability exercising the same authored contract as image producers.
public struct CatalogDrawingProducer: DrawingProducing {
  public typealias Input = DrawingCatalogEntryID
  public struct Settings: Sendable {
    public let style: StrokeStyle
    public let nominalPenWidthMM: Double?
    public let tessellation: CurveTessellationPolicy
    public init(style: StrokeStyle, nominalPenWidthMM: Double? = nil, tessellation: CurveTessellationPolicy = .catalogDefault) {
      self.style = style; self.nominalPenWidthMM = nominalPenWidthMM; self.tessellation = tessellation
    }
  }
  public typealias Artifacts = Data
  public init() {}
  public func produce(input: Input, settings: Settings) async throws -> DrawingProduction<Data> {
    let program = try DrawingProgramCatalog.program(for: input, style: settings.style, tessellation: settings.tessellation)
    struct Receipt: Encodable {
      let profile = "adaptiveplotter.catalog-receipt/2"
      let entry: String
      let sourceIdentifier: String
      let tessellation: CurveTessellationPolicy
      let nominalPenWidthMillimeters: Double?
    }
    let bytes = try DrawingArtifactCoding.encoder().encode(Receipt(entry: input.rawValue,
      sourceIdentifier: program.source.sourceIdentifier, tessellation: settings.tessellation, nominalPenWidthMillimeters: settings.nominalPenWidthMM))
    let receipt = try DrawingProducerReceipt(id: "adaptiveplotter.catalog", version: "2", recordJSON: bytes)
    let drawing = try DrawingAdmission.produced(program: program, input: .none, parent: .none, producer: receipt,
      units: DrawingUnits(nominalPenWidthMM: settings.nominalPenWidthMM),
      validator: DrawingExchangeCodec.builtinValidator("adaptiveplotter.catalog", version: "2")!)
    return .init(drawing: drawing, artifacts: bytes)
  }
}
