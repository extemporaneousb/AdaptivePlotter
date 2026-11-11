import Foundation
import PortraitCore
import PortraitArtists
@testable import PortraitLibrary
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
@testable import PlotterRuntime
@testable import PlotterApp
import Testing

@Suite("Drawing evidence immutable task export", .serialized)
struct DrawingEvidenceTrainingTests {
  private var fixtures: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Fixtures/DrawingExchange/dx03/closure")
  }
  private func package(_ name: String, in root: URL) throws -> ValidatedExchangePackage {
    try ExchangeAdmission.validate(DrawingExchangeCarrier.stageZIP(fixtures.appendingPathComponent(name + ".zip"), stagingParent: root))
  }
  private func root() throws -> URL {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-evidence-task-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
    return path
  }
  private func selection(_ value: ValidatedExchangePackage, snapshot: SnapshotRef? = nil,
    group: String = "source", split: DrawingEvidenceTaskSelection.Split = .inspection,
    assessments: [AssessmentRef] = []) throws -> DrawingEvidenceTaskSelection {
    .init(job: try #require(value.index.known?.jobs.first), snapshot: snapshot, assessments: assessments, group: group, split: split)
  }

  private func photoPair(in directory: URL, sameSession: Bool, unsupportedSource: String? = nil) throws -> ValidatedExchangePackage {
    let original = try package("refused", in: directory), bag = directory.appendingPathComponent("photo-pair-" + UUID().uuidString)
    try DrawingExchangeCarrier.preserveDirectory(original.files, to: bag)
    let root = try #require(original.index.known?.roots.first)
    guard case .materialized(let base)? = original.drawings[root] else { throw DrawingExchangeError.malformed("Photo fixture Drawing") }
    // This disposable fixture replaces the original publication roots/jobs.
    // Retain shared CAS assets, but remove superseded typed records so every
    // remaining receipt names one of the actual new Drawing roots.
    for job in original.receipts.keys {
      try FileManager.default.removeItem(at: bag.appendingPathComponent("data/jobs/" + job.engine.uuidString.lowercased() + "/" + job.job.uuidString.lowercased() + "/receipt.json"))
    }
    for drawing in original.drawings.keys {
      try FileManager.default.removeItem(at: bag.appendingPathComponent("data/drawings/" + drawing.issuer.uuidString.lowercased() + "/" + drawing.revision.uuidString.lowercased() + "/drawing.json"))
    }
    var index = try ExchangeJSON.validate(original.index.originalJSON)
    var descriptors = try #require(index["assets"] as? [[String: Any]])
    var roots: [DrawingRef] = [], jobs: [JobReceiptRef] = []
    let session = UUID(), encoder = DrawingArtifactCoding.encoder()
    func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: encoder.encode(value)) }
    func write(_ bytes: Data, at path: String) throws {
      let target = bag.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      try bytes.write(to: target, options: .atomic)
    }
    for offset in 0..<2 {
      let pixels = try DrawingImageAsset.gray8(Data([UInt8(offset), 64, 128, 255]), width: 2, height: 2)
      let captured = PortraitPhoto(id: UUID(), data: pixels.bytes, label: "session fixture", capturedAt: Date(timeIntervalSince1970: 10),
        pose: .front, captureSessionID: sameSession ? session : UUID())
      let photo = try DrawingImageRecords.photo(identity: .init(issuer: UUID()), original: pixels, width: 2, height: 2,
        acquired: .unknown(provenance: "fixture"), imported: .unknown(provenance: "fixture"),
        captureFactsJSON: encoder.encode(FlowPortfolioCaptureProvenance(photo: captured)))
      let input = try DrawingImageRecords.input(identity: .init(issuer: UUID()), photo: photo, raster: pixels, width: 2, height: 2,
        orientation: "up", sourceToInput: ExchangeTransform([1,0,0,0,1,0,0,0,1]), inputToField: ExchangeTransform([1,0,0,0,1,0,0,0,1]),
        mask: .none, operations: [DrawingImageOperation(kind: "identity", parametersJSON: Data("{}".utf8))],
        preparation: .init(id: "example.task-session", version: "1", recordJSON: Data("{}".utf8)))
      var photoBytes = photo.record.originalJSON, photoRef = photo.reference
      if unsupportedSource?.hasPrefix("photo-") == true {
        var json = try ExchangeJSON.validate(photoBytes)
        if unsupportedSource == "photo-feature" { json["requiredFeatures"] = ["example.future-source/1"] }
        else { json["profile"] = "example.future-photo/9" }
        photoBytes = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        photoRef = .init(issuer: photoRef.issuer, revision: photoRef.revision, digest: .hash(photoBytes))
      }
      var inputJSON = try ExchangeJSON.validate(input.record.originalJSON)
      inputJSON["photo"] = try object(photoRef)
      if unsupportedSource == "input-feature" { inputJSON["requiredFeatures"] = ["example.future-source/1"] }
      else if unsupportedSource == "input-profile" { inputJSON["profile"] = "example.future-input/9" }
      let inputBytes = try JSONSerialization.data(withJSONObject: inputJSON, options: [.sortedKeys])
      let inputRef = ImageInputRef(issuer: input.reference.issuer, revision: input.reference.revision, digest: .hash(inputBytes))
      let value = try Drawing(program: base.drawing.program, input: .present(inputRef), parent: .none,
        producer: .init(id: "example.task-session", version: "1", recordJSON: Data("{}".utf8)))
      let drawing = try DrawingExchangeCodec.freeze(value, identity: .init(issuer: UUID()), createdAt: Date())
      roots.append(drawing.reference)
      let programAsset = try ExchangeAsset(bytes: drawing.originalProgramJSON, mediaType: "application/json", encoding: DrawingExchangeCodec.strokeProfile)
      try write(drawing.originalProgramJSON, at: "data/objects/sha256/" + programAsset.object.description)
      descriptors.append(try #require(object(ExchangeAssetDescriptor(asset: programAsset)) as? [String: Any]))
      for asset in input.assets {
        try write(asset.bytes, at: "data/objects/sha256/" + asset.descriptor.asset.object.description)
        descriptors.append(try #require(object(asset.descriptor) as? [String: Any]))
      }
      try write(photoBytes, at: "data/photos/" + photoRef.issuer.uuidString.lowercased() + "/" + photoRef.revision.uuidString.lowercased() + "/photo.json")
      try write(inputBytes, at: "data/inputs/" + inputRef.issuer.uuidString.lowercased() + "/" + inputRef.revision.uuidString.lowercased() + "/input.json")
      try write(drawing.originalJSON, at: "data/drawings/" + drawing.reference.issuer.uuidString.lowercased() + "/" + drawing.reference.revision.uuidString.lowercased() + "/drawing.json")
      let old = try #require(original.receipts.values.first), id = UUID()
      var receipt = try ExchangeJSON.validate(old.originalJSON)
      receipt["handle"] = ["engine": id.uuidString.lowercased(), "job": id.uuidString.lowercased()]
      receipt["client"] = ["namespace": id.uuidString.lowercased(), "request": id.uuidString.lowercased(), "requestDigest": String(repeating: "a", count: 64)]
      receipt["drawing"] = try object(drawing.reference)
      let bytes = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
      jobs.append(.init(handle: .init(engine: id, job: id), receiptDigest: .hash(bytes)))
      try write(bytes, at: "data/jobs/" + id.uuidString.lowercased() + "/" + id.uuidString.lowercased() + "/receipt.json")
    }
    index["roots"] = try object(roots); index["jobs"] = try object(jobs); index["assets"] = descriptors
    try write(JSONSerialization.data(withJSONObject: index, options: [.sortedKeys]), at: "data/exchange.json")
    try DrawingDestinationResult.seal(bag)
    return try ExchangeAdmission.validate(DrawingExchangeCarrier.stageDirectory(bag, stagingParent: directory))
  }

  @Test("Unknown ImageInput/Photo profiles and requirements grant no inferred grouping facts")
  func unknownSourceGroups() throws {
    let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
    for kind in ["input-feature", "photo-feature", "input-profile", "photo-profile"] {
      let value = try photoPair(in: directory, sameSession: false, unsupportedSource: kind)
      let jobs = try #require(value.index.known?.jobs)
      let task = try DrawingEvidenceTraining.freeze(value, task: .interruption,
        selections: jobs.map { .init(job: $0, group: "one-group", split: .training) }, extractorRevision: "unknown-source-fixture/1")
      #expect(task.manifest.entries.allSatisfy { !$0.eligible && $0.groupingKeys.contains { $0.hasPrefix(kind.hasPrefix("input") ? "unknown-input:" : "unknown-photo:") } })
      #expect(task.manifest.entries.allSatisfy { !$0.groupingKeys.contains { $0.hasPrefix("capture-session:") } })
      if let destination = ProcessInfo.processInfo.environment["DRAWING_NATIVE_TASK_FIXTURE_OUTPUT"] {
        let target = URL(fileURLWithPath: destination)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try DrawingEvidenceTraining.export(task, from: value, to: target.appendingPathComponent("unknown-" + kind + "-task.zip"), payloadValidators: .init())
      }
    }
  }

  @Test("Interruption needs exact current proof; unrelated opaque annotations do not erase that proof")
  func selectedSnapshotProof() throws {
    let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
    let staged = try DrawingExchangeCarrier.stageZIP(fixtures.appendingPathComponent("interrupted.zip"), stagingParent: directory)
    func codecs(incomplete: Bool) -> ExchangePayloadValidators {
      // Fixture-only owner facts exercise the actual admission proof boundary;
      // they assert no production payload or physical behavior validation.
      let callback: ExchangePayloadValidator = { context in
        if incomplete, context.current?.sequence == 2 { return .verified(.init()) }
        let receipt = try #require(context.receipt)
        return .verified(.init(run: context.current?.run, job: receipt.handle, drawing: receipt.drawing,
          clientRequestDigest: receipt.client.requestDigest, clientNamespace: receipt.client.namespace,
          clientRequest: receipt.client.request, issuance: receipt.issuance,
          programSemanticHash: try ExchangeDigest("960ce7fe5f34203bdaa451fbd48f401cdb34598bebcb3a8be7a739645f236097"),
          plan: receipt.preparedPlan.object, preMotion: .hash(Data("frozen pre-motion".utf8))))
      }
      return .init([.init(encoding: "adaptiveplotter.fixture.owner/1", version: "1"): callback,
        .init(encoding: "adaptiveplotter.coverage/1", version: "1"): callback])
    }
    let incomplete = try ExchangeAdmission.validate(staged, payloadValidators: codecs(incomplete: true))
    let refs = incomplete.attempts.keys.sorted { $0.sequence < $1.sequence }
    #expect(incomplete.interpretableAttempts.contains(refs[0]) && !incomplete.interpretableAttempts.contains(refs[1]))
    let blocked = try DrawingEvidenceTraining.freeze(incomplete, task: .interruption,
      selections: [selection(incomplete, snapshot: refs[1], split: .training)], extractorRevision: "fixture-proof/1")
    #expect(!blocked.manifest.entries[0].eligible)
    let bag = directory.appendingPathComponent("unrelated-annotation")
    try DrawingExchangeCarrier.preserveDirectory(incomplete.files, to: bag)
    var index = try ExchangeJSON.validate(incomplete.index.originalJSON)
    let id = ExchangeIdentity(issuer: UUID()), drawing = try #require(incomplete.index.known?.roots.first)
    func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(value)) }
    let annotation: [String: Any] = ["profile": "adaptiveplotter.assessment/1", "requiredFeatures": [String](), "ref": try object(id),
      "targets": [["kind": "drawing", "ref": try object(drawing)]], "reviewer": ["kind": "human", "id": "fixture.operator"],
      "time": ["wallTime": try #require(incomplete.index.known?.includedAsOf)], "question": ["id": "fixture.question", "version": "1", "text": "Uninterpreted note"],
      "answer": ["type": "fixture.unknown-answer", "value": false], "supportingAssets": [String]()]
    let bytes = try JSONSerialization.data(withJSONObject: annotation, options: [.sortedKeys])
    let ref = AssessmentRef(issuer: id.issuer, revision: id.revision, digest: .hash(bytes))
    let path = bag.appendingPathComponent("data/assessments/" + id.issuer.uuidString.lowercased() + "/" + id.revision.uuidString.lowercased() + ".json")
    try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true); try bytes.write(to: path, options: .atomic)
    index["assessments"] = try object([ref])
    try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys]).write(to: bag.appendingPathComponent("data/exchange.json"), options: .atomic)
    try DrawingDestinationResult.seal(bag)
    let annotated = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageDirectory(bag, stagingParent: directory), payloadValidators: codecs(incomplete: false))
    #expect(annotated.interpretableAttempts.contains(refs[1]))
    let allowed = try DrawingEvidenceTraining.freeze(annotated, task: .interruption,
      selections: [selection(annotated, snapshot: refs[1], split: .training)], extractorRevision: "fixture-proof/1")
    #expect(allowed.manifest.entries[0].eligible)
  }

  @Test("Canonical capture sessions connect distinct photos; every declared group has one split")
  func captureSessionGroups() throws {
    let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
    for sameSession in [true, false] {
      let value = try photoPair(in: directory, sameSession: sameSession)
      let jobs = try #require(value.index.known?.jobs)
      let selections = jobs.enumerated().map { offset, job in
        DrawingEvidenceTaskSelection(job: job, group: sameSession ? "group-" + String(offset) : "same-declared-group", split: offset == 0 ? .training : .holdout)
      }
      #expect(throws: (any Error).self) { _ = try DrawingEvidenceTraining.freeze(value, task: .interruption, selections: selections, extractorRevision: "session-fixture/1") }
      let task = try DrawingEvidenceTraining.freeze(value, task: .interruption,
        selections: jobs.map { .init(job: $0, group: "one-group", split: .training) }, extractorRevision: "session-fixture/1")
      if sameSession {
        #expect(!Set(task.manifest.entries[0].groupingKeys.filter { $0.hasPrefix("capture-session:") }).isDisjoint(with: task.manifest.entries[1].groupingKeys))
      }
      if let destination = ProcessInfo.processInfo.environment["DRAWING_NATIVE_TASK_FIXTURE_OUTPUT"] {
        let target = URL(fileURLWithPath: destination)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try DrawingEvidenceTraining.export(task, from: value, to: target.appendingPathComponent(sameSession ? "session-task.zip" : "disjoint-task.zip"), payloadValidators: .init())
      }
    }
  }

  @Test("Refused zero-attempt inspection exports an immutable exact closure and grants no label")
  func refusedInspection() throws {
    let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
    let value = try package("refused", in: directory)
    let selected = try selection(value)
    let task = try DrawingEvidenceTraining.freeze(value, task: .inspection, selections: [selected], extractorRevision: "fixture-inspection/1")
    #expect(task.manifest.entries.count == 1)
    #expect(task.manifest.entries[0].outcome == "refused")
    #expect(task.manifest.entries[0].eligible && task.manifest.entries[0].selection.snapshot == nil)
    #expect(task.manifest.labelContract.contains("no positive or negative"))
    let output = directory.appendingPathComponent("task.zip")
    try DrawingEvidenceTraining.export(task, from: value, to: output)
    let copied = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageZIP(output, stagingParent: directory))
    let decoded = try DrawingEvidenceTraining.read(copied)
    #expect(decoded.originalJSON == task.originalJSON && decoded.manifest == task.manifest)
    for (path, entry) in value.files.entries where path.hasPrefix("data/") && path != "data/exchange.json" {
      #expect(copied.files.entries[path]?.digest == entry.digest)
    }
    #expect(copied.attempts.isEmpty)
    #expect(throws: (any Error).self) { try DrawingEvidenceTraining.export(task, from: value, to: output) }
    let residual = try DrawingEvidenceTraining.freeze(value, task: .alignedResidual, selections: [selected], extractorRevision: "fixture-inspection/1")
    #expect(!residual.manifest.entries[0].eligible)
    #expect(residual.manifest.entries[0].exclusions.contains { $0.contains("refused") })
  }

  @Test("Opaque, unknown-state/environment/requirements and missing observations remain explicit exclusions")
  func unknownEvidence() throws {
    let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
    for name in ["interrupted", "unknown-enum"] {
      let value = try package(name, in: directory), ref = try #require(value.index.known?.attempts.first)
      let selected = try selection(value, snapshot: ref, split: .training)
      let task = try DrawingEvidenceTraining.freeze(value, task: .interruption, selections: [selected], extractorRevision: "fixture-stage/1")
      #expect(!task.manifest.entries[0].eligible && !task.manifest.entries[0].exclusions.isEmpty)
      let residual = try DrawingEvidenceTraining.freeze(value, task: .alignedResidual, selections: [selected], extractorRevision: "fixture-stage/1")
      #expect(!residual.manifest.entries[0].eligible)
      #expect(residual.manifest.entries[0].exclusions.contains { $0.contains("label decoder") })
    }
    let value = try package("interrupted", in: directory)
    for field in ["environment", "state", "requiredFeatures"] {
      let bag = directory.appendingPathComponent("changed-" + field)
      try DrawingExchangeCarrier.preserveDirectory(value.files, to: bag)
      var index = try ExchangeJSON.validate(value.index.originalJSON)
      let latest = try #require(value.index.known?.attempts.first)
      let path = bag.appendingPathComponent("data/attempts/" + latest.archive.uuidString.lowercased() + "/" + latest.run.uuidString.lowercased() + "/" + String(latest.sequence) + "/attempt.json")
      var record = try ExchangeJSON.validate(Data(contentsOf: path))
      if field == "requiredFeatures" { record[field] = ["example.future-stage/1"] }
      else { record[field] = "future-" + field }
      if field == "environment" {
        // Environment is an immutable chain binding. Make the whole disposable
        // chain unfamiliar, retaining its valid predecessor hashes and seal cut.
        var predecessor: ExchangeDigest?
        for prior in value.attempts.keys.filter({ $0.archive == latest.archive && $0.run == latest.run && $0.sequence < latest.sequence }).sorted(by: { $0.sequence < $1.sequence }) {
          let priorPath = bag.appendingPathComponent("data/attempts/" + prior.archive.uuidString.lowercased() + "/" + prior.run.uuidString.lowercased() + "/" + String(prior.sequence) + "/attempt.json")
          var priorRecord = try ExchangeJSON.validate(Data(contentsOf: priorPath))
          priorRecord["environment"] = "future-environment"
          priorRecord["previous"] = predecessor.map { $0.description as Any } ?? NSNull()
          let priorBytes = try JSONSerialization.data(withJSONObject: priorRecord, options: [.sortedKeys])
          try priorBytes.write(to: priorPath, options: .atomic)
          predecessor = .hash(priorBytes)
        }
        if let predecessor { record["previous"] = predecessor.description }
      }
      let bytes = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
      try bytes.write(to: path, options: .atomic)
      let ref = try SnapshotRef(archive: latest.archive, run: latest.run, sequence: latest.sequence, digest: .hash(bytes))
      index["attempts"] = try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode([ref]))
      try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys]).write(to: bag.appendingPathComponent("data/exchange.json"), options: .atomic)
      try DrawingDestinationResult.seal(bag)
      let changed = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageDirectory(bag, stagingParent: directory))
      if field == "environment" { #expect(changed.attempts.values.allSatisfy { $0.environment == "future-environment" }) }
      let task = try DrawingEvidenceTraining.freeze(changed, task: .interruption,
        selections: [selection(changed, snapshot: ref, split: .training)], extractorRevision: "fixture-stage/1")
      #expect(!task.manifest.entries[0].eligible)
    }
  }

  @Test("Related Drawing ancestry cannot cross heldout groups; Rank-only feedback is not a residual dataset")
  func groupingAndFeatureBoundary() throws {
    let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
    let value = try package("interrupted", in: directory)
    let refs = value.attempts.keys.sorted { $0.sequence < $1.sequence }
    try #require(refs.count == 2)
    #expect(throws: (any Error).self) {
      _ = try DrawingEvidenceTraining.freeze(value, task: .interruption, selections: [
        selection(value, snapshot: refs[0], group: "train", split: .training),
        selection(value, snapshot: refs[1], group: "holdout", split: .holdout)], extractorRevision: "fixture-stage/1")
    }
    let feedback = try package("ranking", in: directory)
    #expect(throws: (any Error).self) {
      _ = try DrawingEvidenceTraining.freeze(feedback, task: .alignedResidual,
        selections: [selection(value, snapshot: refs[0])], extractorRevision: "fixture-residual/1")
    }
  }

  @Test("Algorithm/unknown no-ink answers retain actual provenance and cannot forge task eligibility or source scope")
  func attributedClaimsAndForgery() throws {
    let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
    let value = try package("refused", in: directory)
    let bag = directory.appendingPathComponent("claims")
    try DrawingExchangeCarrier.preserveDirectory(value.files, to: bag)
    var index = try ExchangeJSON.validate(value.index.originalJSON)
    index["example.vendor-index"] = ["preserved": true]
    var originalDescriptors = try #require(index["assets"] as? [[String: Any]])
    originalDescriptors[0]["example.vendor-descriptor"] = ["preserved": true]
    index["assets"] = originalDescriptors
    let drawing = try #require(value.index.known?.roots.first)
    let identity = ExchangeIdentity(issuer: UUID())
    let record: [String: Any] = ["profile": "adaptiveplotter.assessment/1", "requiredFeatures": [String](),
      "ref": try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(identity)),
      "targets": [["kind": "drawing", "ref": try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(drawing))]],
      "reviewer": ["kind": "algorithm", "id": "example.analysis", "version": "1"],
      "time": ["wallTime": try #require(value.index.known?.includedAsOf)],
      "question": ["id": "example.observation", "version": "1", "text": "Recorded observation"],
      "answer": ["type": "example.untrusted-no-ink-name", "value": true], "supportingAssets": [String]()]
    let bytes = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    let ref = AssessmentRef(issuer: identity.issuer, revision: identity.revision, digest: .hash(bytes))
    let path = bag.appendingPathComponent("data/assessments/" + identity.issuer.uuidString.lowercased() + "/" + identity.revision.uuidString.lowercased() + ".json")
    try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
    try bytes.write(to: path, options: .atomic)
    var selectedAssessments = [ref]
    for answer in ["adaptiveplotter.flow-pruning", "adaptiveplotter.flow-choice", "adaptiveplotter.recorded-ranking-revision"] {
      let id = ExchangeIdentity(issuer: UUID())
      var named = record
      named["ref"] = try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(id))
      named["reviewer"] = answer == "adaptiveplotter.recorded-ranking-revision"
        ? ["kind": "algorithm", "id": "adaptiveplotter.flow-feedback-adapter", "version": "1"] : ["kind": "human", "id": "fixture.operator"]
      named["answer"] = ["type": answer, "value": false]
      let raw = try JSONSerialization.data(withJSONObject: named, options: [.sortedKeys])
      selectedAssessments.append(.init(issuer: id.issuer, revision: id.revision, digest: .hash(raw)))
      let location = bag.appendingPathComponent("data/assessments/" + id.issuer.uuidString.lowercased() + "/" + id.revision.uuidString.lowercased() + ".json")
      try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
      try raw.write(to: location, options: .atomic)
    }
    index["assessments"] = try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(selectedAssessments))
    try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys]).write(to: bag.appendingPathComponent("data/exchange.json"), options: .atomic)
    try DrawingDestinationResult.seal(bag)
    let claimed = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageDirectory(bag, stagingParent: directory))
    let task = try DrawingEvidenceTraining.freeze(claimed, task: .inspection,
      selections: [selection(claimed, assessments: selectedAssessments)], extractorRevision: "fixture-inspection/1")
    let claim = try #require(task.manifest.entries.first?.claims.first)
    #expect(claim.kind == "uninterpreted-claim" && claim.reviewerKind == "algorithm")
    #expect(claim.reviewerID == "example.analysis" && claim.answerType == "example.untrusted-no-ink-name")
    #expect(task.manifest.entries[0].claims.count == 4 && task.manifest.entries[0].claims.allSatisfy { $0.kind == "uninterpreted-claim" })
    #expect(task.manifest.entries[0].claims.map(\.reference) == selectedAssessments)
    let output = directory.appendingPathComponent("claims-task.zip")
    try DrawingEvidenceTraining.export(task, from: claimed, to: output)
    let exported = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageZIP(output, stagingParent: directory))
    #expect(try DrawingEvidenceTraining.read(exported).manifest == task.manifest)
    let sourceAssets = Set(try #require(claimed.index.known?.assets).map { $0.asset.object })
    for changed in ["eligible", "provenance", "groupingKeys", "sourceIndex", "sourceRequiredFeatures", "sourceAssets", "sourceScope", "sourceProfile", "sourceUnknownKeys"] {
      let modified = directory.appendingPathComponent("forged-" + changed)
      try DrawingExchangeCarrier.preserveDirectory(exported.files, to: modified)
      var taskJSON = try ExchangeJSON.validate(task.originalJSON)
      var modifiedIndex = try ExchangeJSON.validate(exported.index.originalJSON)
      var assets = try #require(modifiedIndex["assets"] as? [[String: Any]])
      func removeSupersededWrapper(_ value: ExchangeAsset) throws {
        // Original source assets, including its displaced scope, stay claimed.
        guard !sourceAssets.contains(value.object) else { return }
        assets.removeAll { $0["object"] as? String == value.object.description }
        let location = modified.appendingPathComponent("data/objects/sha256/" + value.object.description)
        if FileManager.default.fileExists(atPath: location.path) { try FileManager.default.removeItem(at: location) }
      }
      try removeSupersededWrapper(task.asset)
      let expected: DrawingExchangeError
      if ["eligible", "provenance", "groupingKeys"].contains(changed) {
        var entries = try #require(taskJSON["entries"] as? [[String: Any]])
        if changed == "eligible" { entries[0]["eligible"] = false }
        else if changed == "groupingKeys" { entries[0]["groupingKeys"] = [String]() }
        else {
          var claims = try #require(entries[0]["claims"] as? [[String: Any]])
          claims[0]["reviewerID"] = "example.forged-reviewer"
          entries[0]["claims"] = claims
        }
        taskJSON["entries"] = entries
        expected = .malformed("Task membership, source grouping or eligibility differs from exact evidence")
      } else {
        try removeSupersededWrapper(task.manifest.sourceIndex)
        var sourceJSON = try ExchangeJSON.validate(claimed.index.originalJSON)
        switch changed {
        case "sourceRequiredFeatures": sourceJSON["requiredFeatures"] = ["example.future-policy/1"]
        case "sourceAssets": sourceJSON["assets"] = Array(try #require(sourceJSON["assets"] as? [[String: Any]]).dropFirst())
        case "sourceScope":
          var brokenScope = try #require((sourceJSON["assets"] as? [[String: Any]])?.first)
          brokenScope["byteLength"] = try #require(brokenScope["byteLength"] as? Int) + 1
          sourceJSON["scope"] = brokenScope
        case "sourceProfile": sourceJSON["profile"] = "example.future-index/9"
        case "sourceUnknownKeys": sourceJSON["example.vendor-index"] = ["preserved": false]
        default: sourceJSON["includedAsOf"] = "2020-01-01T00:00:00Z"
        }
        let sourceBytes = try JSONSerialization.data(withJSONObject: sourceJSON, options: [.sortedKeys])
        let source = try ExchangeAsset(bytes: sourceBytes, mediaType: "application/json", encoding: "adaptiveplotter.exchange/1")
        try sourceBytes.write(to: modified.appendingPathComponent("data/objects/sha256/" + source.object.description), options: .atomic)
        let descriptor = try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(ExchangeAssetDescriptor(asset: source)))
        assets.append(try #require(descriptor as? [String: Any]))
        taskJSON["sourceIndex"] = try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(source))
        if changed == "sourceScope" { expected = .malformed("Task original scope was not declared by its source index") }
        else if changed == "sourceProfile" { expected = .unsupportedProfile("example.future-index/9") }
        else { expected = .malformed("Task carrier is not the exact allowed derivation of its original result index") }
      }
      let changedBytes = try JSONSerialization.data(withJSONObject: taskJSON, options: [.sortedKeys])
      let asset = try ExchangeAsset(bytes: changedBytes, mediaType: "application/json", encoding: DrawingEvidenceTraining.profile)
      try changedBytes.write(to: modified.appendingPathComponent("data/objects/sha256/" + asset.object.description), options: .atomic)
      assets.append(try #require(JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(ExchangeAssetDescriptor(asset: asset))) as? [String: Any]))
      modifiedIndex["assets"] = assets
      modifiedIndex["scope"] = try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(asset))
      try JSONSerialization.data(withJSONObject: modifiedIndex, options: [.sortedKeys]).write(to: modified.appendingPathComponent("data/exchange.json"), options: .atomic)
      try DrawingDestinationResult.seal(modified)
      let admitted = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageDirectory(modified, stagingParent: directory))
      #expect(throws: expected) { _ = try DrawingEvidenceTraining.read(admitted) }
    }
  }

  @Test("Known native result yields an exact task carrier for independent inspection without live stores")
  @MainActor func nativeResultTask() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let h = await drawingRunHarness(fixture: fixture, outcome: .cancelled)
    let ready = await h.runtime.synchronize(environment: .live)
    _ = await h.submit(.init(projection: ready.projection, intent: .start))
    let state = try await issuanceSettled(h.runtime)
    let key = try #require(h.destination.lastKey)
    guard case .decision(let decision) = try await h.destination.service.handle(.status(.request(key))),
      case .result(let source) = try await h.destination.service.handle(.exportResult(decision.job.handle)) else {
      Issue.record("No native result to freeze"); await h.destination.close(); return
    }
    let directory = try root(); defer { try? FileManager.default.removeItem(at: directory) }
    let result = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageZIP(source, stagingParent: directory),
      payloadValidators: DrawingDestinationResult.payloadValidators)
    let ref = try #require(result.index.known?.attempts.first)
    #expect(ref.run == state.terminal?.runID.rawValue)
    let task = try DrawingEvidenceTraining.freeze(result, task: .inspection,
      selections: [selection(result, snapshot: ref)], extractorRevision: "native-result-inspection/1")
    let output = directory.appendingPathComponent("native-task.zip")
    try DrawingEvidenceTraining.export(task, from: result, to: output)
    let copied = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageZIP(output, stagingParent: directory),
      payloadValidators: DrawingDestinationResult.payloadValidators)
    #expect(try DrawingEvidenceTraining.read(copied).manifest == task.manifest)
    let interruption = try DrawingEvidenceTraining.freeze(result, task: .interruption,
      selections: [selection(result, snapshot: ref, split: .training)], extractorRevision: "native-interruption/1")
    #expect(interruption.manifest.entries[0].eligible)
    let interruptionOutput = directory.appendingPathComponent("native-interruption-task.zip")
    try DrawingEvidenceTraining.export(interruption, from: result, to: interruptionOutput)
    let unknownBag = directory.appendingPathComponent("unknown-required-feature")
    try DrawingExchangeCarrier.preserveDirectory(result.files, to: unknownBag)
    var unknownIndex = try ExchangeJSON.validate(result.index.originalJSON)
    unknownIndex["requiredFeatures"] = ["example.future-result-semantics/1"]
    try JSONSerialization.data(withJSONObject: unknownIndex, options: [.sortedKeys])
      .write(to: unknownBag.appendingPathComponent("data/exchange.json"), options: .atomic)
    try DrawingDestinationResult.seal(unknownBag)
    let unknown = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageDirectory(unknownBag, stagingParent: directory),
      payloadValidators: DrawingDestinationResult.payloadValidators)
    let unsupported = try DrawingEvidenceTraining.freeze(unknown, task: .interruption,
      selections: [selection(unknown, snapshot: ref, split: .training)], extractorRevision: "native-interruption/1")
    #expect(!unsupported.manifest.entries[0].eligible)
    #expect(unsupported.manifest.entries[0].exclusions.contains { $0.contains("future-result-semantics") })
    if let destination = ProcessInfo.processInfo.environment["DRAWING_NATIVE_TASK_FIXTURE_OUTPUT"] {
      let target = URL(fileURLWithPath: destination)
      try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: output, to: target.appendingPathComponent("native-task.zip"))
      try FileManager.default.copyItem(at: interruptionOutput, to: target.appendingPathComponent("native-interruption-task.zip"))
    }
    await h.destination.close()
  }
}
