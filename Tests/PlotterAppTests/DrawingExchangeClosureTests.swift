import Foundation
import Testing
@testable import PortraitCore

@Suite("Drawing Exchange semantic closure", .serialized)
struct DrawingExchangeClosureTests {
  private var fixtures: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Fixtures/DrawingExchange/dx03/closure")
  }
  private func withPackage(_ name: String, _ body: (StagedExchangePackage) throws -> Void) throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("dx03-closure-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temp) }
    let package = try DrawingExchangeCarrier.stageZIP(fixtures.appendingPathComponent(name + ".zip"), stagingParent: temp)
    try body(package)
  }
  @Test("Unsupported index major preserves arbitrary bounded body without fabricated v1 fields")
  func opaqueIndex() throws {
    try withPackage("unknown-index-minimal") { staged in
      let admitted = try ExchangeAdmission.validate(staged)
      guard case .opaque(let bytes, let profile) = admitted.index else { Issue.record("Expected opaque index"); return }
      #expect(bytes == staged.indexJSON)
      #expect(profile == "adaptiveplotter.exchange/9")
      #expect(admitted.capabilities.supported == [.preserve, .inspect])
      #expect(admitted.drawings.isEmpty)
      let export = staged.stagingURL.deletingLastPathComponent().appendingPathComponent("opaque-copy.zip")
      try DrawingExchangeCarrier.preserveZIP(admitted.files, to: export)
      let again = try DrawingExchangeCarrier.stageZIP(export, stagingParent: staged.stagingURL.deletingLastPathComponent())
      #expect(again.indexJSON == bytes)
      #expect(again.files.entries.mapValues(\.digest) == staged.files.entries.mapValues(\.digest))
    }
  }
  @Test("Repeated identical refs and asset descriptors are idempotent wire mentions")
  func repeatedIdentical() throws {
    try withPackage("repeated-identical") { staged in
      let admitted = try ExchangeAdmission.validate(staged)
      let index = try #require(admitted.index.known)
      #expect(index.roots.count == 2)
      #expect(index.roots[0] == index.roots[1])
      #expect(index.assets.count == 3)
      #expect(index.assets[0] == index.assets[2])
      #expect(admitted.drawings.count == 1)
      #expect(admitted.index.originalJSON == staged.indexJSON)
      #expect(admitted.capabilities.supported.contains(.drawing))
      let export = staged.stagingURL.deletingLastPathComponent().appendingPathComponent("repeated-copy.zip")
      try DrawingExchangeCarrier.preserveZIP(admitted.files, to: export)
      let again = try DrawingExchangeCarrier.stageZIP(export, stagingParent: staged.stagingURL.deletingLastPathComponent())
      #expect(again.indexJSON == index.originalJSON)
    }
  }
  @Test("Source-free common program admits independently from image codecs")
  func sourceFree() throws {
    try withPackage("source-free") { staged in
      let admitted = try ExchangeAdmission.validate(staged)
      #expect(admitted.integrityVerified)
      #expect(admitted.knownClosureSemanticsSupported)
      #expect(admitted.capabilities.supported.contains(.drawing))
      let drawing = try #require(admitted.drawings.values.first)
      guard case .materialized(let frozen) = drawing else { Issue.record("Expected known program"); return }
      #expect(frozen.originalJSON == (try staged.files.record(at: "data/drawings/550e8400-e29b-41d4-a716-446655440000/e95e1607-a025-4598-880a-221077f27cc1/drawing.json")))
      #expect(staged.statistics.imageDecodeCount == 0)
    }
  }
  @Test("Optional bytes and declared requirements survive preservation", arguments: ["optional-index", "required-feature", "unknown-major", "interrupted"])
  func preservation(name: String) throws {
    try withPackage(name) { staged in
      let admitted = try ExchangeAdmission.validate(staged)
      let export = staged.stagingURL.deletingLastPathComponent().appendingPathComponent("preserved-" + UUID().uuidString + ".zip")
      try DrawingExchangeCarrier.preserveZIP(admitted.files, to: export)
      let again = try DrawingExchangeCarrier.stageZIP(export, stagingParent: staged.stagingURL.deletingLastPathComponent())
      #expect(again.indexJSON == admitted.index.originalJSON)
      #expect(again.files.entries.mapValues(\.digest) == admitted.files.entries.mapValues(\.digest))
      if name == "required-feature" {
        #expect((try #require(admitted.index.known)).requiredFeatures == ["example.mandatory/1"])
        #expect(!admitted.capabilities.supported.contains(.drawing))
        #expect(admitted.capabilities.supported.contains(.inspect))
        #expect(admitted.capabilities.supported.contains(.preserve))
        // A materialized Drawing would escape the unresolved external context:
        // freeze() carries intrinsic drawing requirements, not the enclosing index.
        for admission in admitted.drawings.values {
          guard case .opaque(_, let profile) = admission else {
            Issue.record("Unresolved index context exposed a refreezable Drawing"); continue
          }
          #expect(profile == DrawingExchangeCodec.drawingProfile)
        }
        let understood = try ExchangeAdmission.validate(staged, supportedFeatures: ["example.mandatory/1"])
        #expect(understood.capabilities.supported.contains(.drawing))
        #expect(understood.index.originalJSON == admitted.index.originalJSON)
        let understoodIndex = try #require(understood.index.known)
        let reference = try #require(understoodIndex.roots.first)
        guard case .materialized(let frozen) = try #require(understood.drawings[reference]) else {
          Issue.record("Explicitly understood index did not expose known Drawing"); return
        }
        #expect(frozen.reference == reference)
        #expect(frozen.drawing.requiredFeatures.isEmpty)
        try frozen.drawing.capabilities.require(.plot)
        #expect(DrawingExchangeCodec.encode(frozen) == (try staged.files.record(at: "data/drawings/550e8400-e29b-41d4-a716-446655440000/e95e1607-a025-4598-880a-221077f27cc1/drawing.json")))
      }
      if name == "unknown-major" { #expect(!admitted.opaqueRecords.isEmpty) }
    }
  }
  @Test("Recognized corruption fails after manifest staging", arguments: [
    "wrong-record-kind", "mismatched-root", "identity-kind-conflict", "refused-with-attempt", "accepted-zero",
    "lost-predecessor", "post-seal", "ink-reversion", "changed-environment", "wrong-drawing", "wrong-job",
    "wrong-predecessor", "missing-issuance", "malformed-known-index", "request-conflict", "two-runs", "sequence-path", "archive-path", "ranking-duplicate", "ranking-dangling", "unknown-reviewer-dangling-asset", "unknown-reviewer-dangling-target", "unknown-target-dangling-sibling", "unknown-response-dangling-asset", "unknown-evidence-dangling-asset", "evidence-source-type", "evidence-source-empty", "evidence-reason-type", "evidence-reason-empty", "human-reviewer-version-type", "unknown-reviewer-version-empty", "conflicting-descriptor", "conflicting-identity", "sticky-ink-reversion", "opaque-receipt-missing-intent", "opaque-receipt-missing-coverage", "opaque-receipt-missing-terminal", "opaque-receipt-missing-plan", "opaque-receipt-missing-assessment", "opaque-predecessor-missing-intent", "opaque-predecessor-missing-coverage", "opaque-predecessor-missing-terminal", "opaque-predecessor-missing-plan", "opaque-predecessor-missing-assessment", "opaque-receipt-lost-predecessor", "unindexed-object", "noncanonical-extra-bin"
  ])
  func rejects(name: String) throws {
    try withPackage(name) { staged in
      #expect(throws: (any Error).self) { try ExchangeAdmission.validate(staged) }
      #expect(FileManager.default.fileExists(atPath: staged.stagingURL.path))
    }
  }
  @Test("Refusal imports zero attempts without fabricating a run")
  func refusal() throws {
    try withPackage("refused") { staged in
      let admitted = try ExchangeAdmission.validate(staged)
      #expect(admitted.attempts.isEmpty)
      #expect(admitted.receipts.count == 1)
      #expect(admitted.receipts.values.first?.issuance == nil)
      #expect(admitted.receipts.values.first?.disposition == "refused")
    }
  }
  @Test("Sequence N roots load predecessors and unsupported native semantics grant no authority")
  func unsupportedEvidence() throws {
    try withPackage("interrupted") { staged in
      let admitted = try ExchangeAdmission.validate(staged)
      #expect((try #require(admitted.index.known)).attempts.count == 1)
      #expect(admitted.attempts.count == 2)
      #expect(admitted.attempts.values.contains { $0.sealed && $0.state == "interrupted" })
      #expect(!admitted.capabilities.supported.contains(.interpretResults))
      #expect(!admitted.capabilities.supported.contains(.physicalInterpretation))
      #expect(!admitted.capabilities.supported.contains(.train))
      #expect(admitted.capabilities.unsupportedReasons.contains { $0.contains("owner payload semantics") })
    }
  }
  @Test("Unknown disposition remains opaque without inferred acceptance or refusal", arguments: ["unknown-zero", "unknown-with-attempt"])
  func unknownDisposition(name: String) throws {
    try withPackage(name) { staged in
      let admitted = try ExchangeAdmission.validate(staged)
      #expect(admitted.receipts.values.first?.disposition == "future-disposition")
      #expect(admitted.capabilities.supported.contains(.inspect))
      #expect(!admitted.capabilities.supported.contains(.interpretResults))
    }
  }
  @Test("Unknown snapshot enum remains byte-preservable with affected operations blocked")
  func unknownEnum() throws {
    try withPackage("unknown-enum") { staged in
      let admitted = try ExchangeAdmission.validate(staged)
      #expect(admitted.attempts.values.contains { $0.dispatch == "future-dispatch" })
      #expect(!admitted.capabilities.supported.contains(.interpretResults))
      #expect(admitted.capabilities.supported.contains(.preserve))
    }
  }
  private func validators(_ makeFacts: @escaping @Sendable (ExchangePayloadContext) throws -> ExchangePayloadFacts) -> ExchangePayloadValidators {
    // Deliberately fixture-only. This is not production evidence validation.
    let callback: ExchangePayloadValidator = { context in
      let bytes = try context.resolver.record(context.descriptor.asset.object)
      _ = try ExchangeJSON.validate(bytes)
      return .verified(try makeFacts(context))
    }
    return .init([
      .init(encoding: "adaptiveplotter.fixture.owner/1", version: "1"): callback,
      .init(encoding: "adaptiveplotter.coverage/1", version: "1"): callback
    ])
  }
  @Test("Trusted owner codec facts bind exact request and pre-motion identity")
  func registeredFacts() throws {
    try withPackage("interrupted") { staged in
      let codecs = validators { context in
        let receipt = try #require(context.receipt)
        return .init(run: context.current?.run, job: receipt.handle, drawing: receipt.drawing,
          clientRequestDigest: receipt.client.requestDigest, issuance: receipt.issuance,
          programSemanticHash: try ExchangeDigest("960ce7fe5f34203bdaa451fbd48f401cdb34598bebcb3a8be7a739645f236097"),
          plan: receipt.preparedPlan.object, preMotion: .hash(Data("frozen pre-motion".utf8)))
      }
      let admitted = try ExchangeAdmission.validate(staged, payloadValidators: codecs)
      #expect(admitted.capabilities.supported.contains(.interpretResults))
      #expect(!admitted.capabilities.supported.contains(.physicalInterpretation))
    }
  }
  @Test("Recognized owner codec contradictions fail", arguments: ["request", "run", "issuance", "preMotion", "frontierOrder", "frontierReversion"])
  func invalidRegisteredFacts(kind: String) throws {
    try withPackage("interrupted") { staged in
      let codecs = validators { context in
        let receipt = try #require(context.receipt)
        var facts = ExchangePayloadFacts(run: context.current?.run, job: receipt.handle, drawing: receipt.drawing,
          clientRequestDigest: receipt.client.requestDigest, issuance: receipt.issuance)
        switch kind {
        case "request": facts.clientRequestDigest = .hash(Data("different request".utf8))
        case "run": if context.current != nil { facts.run = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440099")! }
        case "issuance": facts.issuance = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440099")!
        case "preMotion": if let current = context.current { facts.preMotion = .hash(Data("motion-\(current.sequence)".utf8)) }
        case "frontierOrder": facts.frontiers = ["planned": 1, "commanded": 2]
        case "frontierReversion": if let current = context.current { facts.frontiers = ["commanded": current.sequence == 1 ? 2 : 1] }
        default: break
        }
        return facts
      }
      #expect(throws: (any Error).self) { try ExchangeAdmission.validate(staged, payloadValidators: codecs) }
    }
  }
  @Test("Ranking capsule preserves independent feedback identity and frozen presentation order")
  func ranking() throws {
    try withPackage("ranking") { staged in
      let admitted = try ExchangeAdmission.validate(staged)
      #expect(admitted.rankingCapsules.count == 1)
      let capsule = try #require(admitted.rankingCapsules.values.first)
      #expect(capsule.presentationIDs.count == 2)
      #expect(capsule.responseKind == "ranking")
      #expect(!admitted.capabilities.supported.contains(.train))
    }
  }
  @Test("A registered codec that proves no native binding grants no interpretation")
  func emptyRegisteredFacts() throws {
    try withPackage("interrupted") { staged in
      let admitted = try ExchangeAdmission.validate(staged, payloadValidators: validators { _ in .init() })
      #expect(!admitted.capabilities.supported.contains(.interpretResults))
      #expect(admitted.capabilities.supported.contains(.inspect))
    }
  }
  @Test("Unsupported feedback enum cannot hide known sibling claims", arguments: ["unknown-reviewer", "unknown-target", "unknown-response"])
  func unsupportedFeedback(name: String) throws {
    try withPackage(name) { staged in
      let admitted = try ExchangeAdmission.validate(staged)
      #expect(admitted.capabilities.supported.contains(.inspect))
      #expect(admitted.capabilities.supported.contains(.preserve))
      #expect(!admitted.capabilities.supported.contains(.interpretResults))
      #expect(admitted.index.originalJSON == staged.indexJSON)
    }
  }
  @Test("Coverage vendor metadata and unsupported evidence status preserve exact bytes", arguments: ["coverage-vendor", "unknown-evidence-status"])
  func coverageExtensions(name: String) throws {
    try withPackage(name) { staged in
      let admitted = try ExchangeAdmission.validate(staged)
      #expect(admitted.attempts.count == 2)
      #expect(admitted.capabilities.supported.contains(.inspect))
      #expect(!admitted.capabilities.supported.contains(.interpretResults))
      let export = staged.stagingURL.deletingLastPathComponent().appendingPathComponent("coverage-copy.zip")
      try DrawingExchangeCarrier.preserveZIP(admitted.files, to: export)
      let again = try DrawingExchangeCarrier.stageZIP(export, stagingParent: staged.stagingURL.deletingLastPathComponent())
      #expect(again.files.entries.mapValues(\.digest) == staged.files.entries.mapValues(\.digest))
    }
  }
  @Test("Unknown dependencies preserve resolved known current claims without physical conclusions", arguments: ["opaque-receipt-resolved", "opaque-predecessor-resolved", "sticky-ink-unknown"])
  func unsupportedAttemptDependencies(name: String) throws {
    try withPackage(name) { staged in
      let admitted = try ExchangeAdmission.validate(staged)
      #expect(admitted.capabilities.supported.contains(.inspect))
      #expect(!admitted.capabilities.supported.contains(.interpretResults))
      #expect(!admitted.capabilities.supported.contains(.physicalInterpretation))
      #expect(!admitted.attempts.isEmpty)
      if name == "sticky-ink-unknown" { #expect(admitted.attempts.count == 3) }
      let export = staged.stagingURL.deletingLastPathComponent().appendingPathComponent("unsupported-attempt-copy.zip")
      try DrawingExchangeCarrier.preserveZIP(admitted.files, to: export)
      let again = try DrawingExchangeCarrier.stageZIP(export, stagingParent: staged.stagingURL.deletingLastPathComponent())
      #expect(again.files.entries.mapValues(\.digest) == admitted.files.entries.mapValues(\.digest))
    }
  }
  @Test("A declared opaque object remains a valid inert payload")
  func indexedOpaqueAsset() throws {
    try withPackage("indexed-opaque-asset") { staged in
      let admitted = try ExchangeAdmission.validate(staged)
      let index = try #require(admitted.index.known)
      let descriptor = try #require(index.assets.first { $0.asset.encoding == "example.opaque/77" })
      #expect(admitted.capabilities.supported.contains(.drawing))
      guard case .unsupported = try #require(admitted.assetSupport[descriptor.asset.object]) else {
        Issue.record("Opaque encoding unexpectedly interpreted"); return
      }
      let original = try staged.files.record(descriptor.asset.object)
      #expect(original == Data([111, 112, 97, 113, 117, 101, 0, 255]))
      let export = staged.stagingURL.deletingLastPathComponent().appendingPathComponent("opaque-asset-copy.zip")
      try DrawingExchangeCarrier.preserveZIP(admitted.files, to: export)
      let again = try DrawingExchangeCarrier.stageZIP(export, stagingParent: staged.stagingURL.deletingLastPathComponent())
      #expect(try again.files.record(descriptor.asset.object) == original)
      #expect(again.indexJSON == index.originalJSON)
    }
  }
  @Test("Admission byte budget excludes prior reads and prior admissions")
  func reusableReadBudget() throws {
    try withPackage("source-free") { staged in
      let before = staged.statistics.materializedBytesRead
      _ = try ExchangeAdmission.validate(staged)
      let firstAdmissionCost = staged.statistics.materializedBytesRead - before
      let path = "data/drawings/550e8400-e29b-41d4-a716-446655440000/e95e1607-a025-4598-880a-221077f27cc1/drawing.json"
      for _ in 0..<10 { _ = try staged.files.record(at: path) }
      var limits = ExchangeClosureLimits(); limits.maximumMaterializedBytes = firstAdmissionCost + 1024
      #expect(staged.statistics.materializedBytesRead > limits.maximumMaterializedBytes)
      let first = try ExchangeAdmission.validate(staged, limits: limits)
      let second = try ExchangeAdmission.validate(staged, limits: limits)
      #expect(first.index.originalJSON == second.index.originalJSON)
      #expect(first.capabilities.supported == second.capabilities.supported)
      // Returned files expose the reusable original handle, not an exhausted admission view.
      #expect(try first.files.record(at: path) == second.files.record(at: path))
    }
  }
  @Test("Closure loads obey explicit count and byte budgets")
  func boundedLoads() throws {
    try withPackage("interrupted") { staged in
      var count = ExchangeClosureLimits(); count.maximumRecords = 1
      #expect(throws: (any Error).self) { try ExchangeAdmission.validate(staged, limits: count) }
      var bytes = ExchangeClosureLimits(); bytes.maximumMaterializedBytes = 1
      #expect(throws: (any Error).self) { try ExchangeAdmission.validate(staged, limits: bytes) }
    }
  }
}
