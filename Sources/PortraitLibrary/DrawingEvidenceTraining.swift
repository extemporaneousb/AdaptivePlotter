import Darwin
import Foundation
import PortraitCore

/// A task-specific immutable view of an already verified result. It owns no job,
/// run, retry, raw evidence, checkpoint, or activation state.
public enum DrawingEvidenceTask: String, Codable, Hashable, Sendable {
  case inspection = "adaptiveplotter.result-inspection/1"
  case interruption = "adaptiveplotter.interruption-state/1"
  case alignedResidual = "adaptiveplotter.aligned-residual/1"

  public var inputContract: String {
    switch self {
    case .inspection: "Exact Drawing/job/snapshot/assessment closure; unavailable facts remain explicit."
    case .interruption: "Exact native pre-motion binding and recorded stage/frontier; no elapsed-clock inference."
    case .alignedResidual: "Exact live target, attributable aligned observation, registration and measured residual label."
    }
  }
  public var labelContract: String {
    switch self {
    case .inspection: "Inspection only; no positive or negative training label."
    case .interruption: "Recorded interruption category and frontier only; no inferred ink or image residual."
    case .alignedResidual: "A registered aligned-residual measurement; testimony, preference and synthetic images are not labels."
    }
  }
}

public struct DrawingEvidenceTaskSelection: Codable, Hashable, Sendable {
  public enum Split: String, Codable, Hashable, Sendable { case inspection, training, holdout }
  public let job: JobReceiptRef
  public let snapshot: SnapshotRef?
  public let assessments: [AssessmentRef]
  public let group: String
  public let split: Split
  /// Additional known session/subject connections supplied by the owning dataset
  /// policy. These supplement, never replace, exact source/parent grouping.
  public let relatedGroups: [String]
  public init(job: JobReceiptRef, snapshot: SnapshotRef? = nil, assessments: [AssessmentRef] = [],
    group: String, split: Split = .inspection, relatedGroups: [String] = []) {
    self.job = job; self.snapshot = snapshot; self.assessments = assessments
    self.group = group; self.split = split; self.relatedGroups = relatedGroups
  }
}

public struct DrawingEvidenceTaskManifest: Codable, Equatable, Sendable {
  public struct Claim: Codable, Equatable, Sendable {
    public let reference: AssessmentRef
    public let kind: String
    public let answerType: String
    public let reviewerKind: String
    public let reviewerID: String
    public let reviewerVersion: String?
  }
  public struct Entry: Codable, Equatable, Sendable {
    public let selection: DrawingEvidenceTaskSelection
    public let drawing: DrawingRef
    public let outcome: String
    public let environment: String?
    public let claims: [Claim]
    public let groupingKeys: [String]
    public let eligible: Bool
    public let exclusions: [String]
    public let limitations: [String]
  }
  public let profile: String
  public let requiredFeatures: [String]
  public let id: UUID
  public let task: DrawingEvidenceTask
  public let taskVersion: String
  public let inputContract: String
  public let labelContract: String
  public let sourceIndex: ExchangeAsset
  public let includedAsOf: String
  public let extractorRevision: String
  public let modelRevision: String?
  public let modelRevisionUnavailableReason: String?
  public let entries: [Entry]
}

public struct FrozenDrawingEvidenceTask: Sendable {
  public let manifest: DrawingEvidenceTaskManifest
  public let asset: ExchangeAsset
  public let originalJSON: Data
}

public enum DrawingEvidenceTraining {
  public static let profile = "adaptiveplotter.drawing-evidence-task/1"

  /// Every selected receipt/snapshot/assessment must already belong to this exact
  /// self-contained result. Eligibility never changes the underlying evidence.
  public static func freeze(_ package: ValidatedExchangePackage, task: DrawingEvidenceTask,
    selections: [DrawingEvidenceTaskSelection], extractorRevision: String,
    modelRevision: String? = nil, id: UUID = UUID()) throws -> FrozenDrawingEvidenceTask {
    guard let index = package.index.known, index.kind == "result",
      package.integrityVerified, !selections.isEmpty, selections.count <= 10_000,
      !extractorRevision.isEmpty, modelRevision?.isEmpty != true,
      Set(selections).count == selections.count else {
      throw DrawingExchangeError.malformed("A task requires exact current result selections and extractor identity; feature-only Rank is not physical geometry")
    }
    let source = try ExchangeAsset(bytes: index.originalJSON, mediaType: "application/json", encoding: "adaptiveplotter.exchange/1")
    var entries: [DrawingEvidenceTaskManifest.Entry] = []
    var groups: [String: (String, DrawingEvidenceTaskSelection.Split)] = [:]
    var declaredSplits: [String: DrawingEvidenceTaskSelection.Split] = [:]
    let taskUnsupported = package.capabilities.unsupportedReasons.filter {
      !$0.hasPrefix("Unsupported assessment answer semantics:")
    }
    for selection in selections {
      guard index.jobs.contains(selection.job), let receipt = package.receipts[selection.job],
        !selection.group.isEmpty, selection.relatedGroups.allSatisfy({ !$0.isEmpty }),
        Set(selection.assessments).count == selection.assessments.count else {
        throw DrawingExchangeError.malformed("Task receipt, grouping or assessment selection")
      }
      let snapshot: ExchangeAttemptSnapshot?
      if let ref = selection.snapshot {
        guard let value = package.attempts[ref], value.job == selection.job,
          value.drawing == receipt.drawing else { throw DrawingExchangeError.malformed("Task snapshot binding") }
        snapshot = value
      } else {
        guard receipt.disposition == "refused" else { throw DrawingExchangeError.malformed("An accepted task entry needs its exact snapshot") }
        snapshot = nil
      }
      var claims: [DrawingEvidenceTaskManifest.Claim] = []
      for ref in selection.assessments {
        guard let value = package.assessments[ref], value.targets.contains(where: { target in
          switch target {
          case .drawing(let drawing): drawing == receipt.drawing
          case .attempt(let attempt): attempt == selection.snapshot
          default: false
          }
        }) else { throw DrawingExchangeError.malformed("Task assessment must target the exact selected Drawing or snapshot") }
        let json = try ExchangeJSON.validate(value.originalJSON)
        let reviewer = json["reviewer"] as? [String: Any]
        let reviewerKind = reviewer?["kind"] as? String ?? "unknown"
        let reviewerID = reviewer?["id"] as? String ?? "unknown"
        let reviewerVersion = reviewer?["version"] as? String
        // A familiar answer/reviewer name is not owning-decoder acceptance.
        // Flow's actual sole-asset feedback target contract differs from this
        // Drawing/snapshot selection contract, so retain named claims opaquely.
        claims.append(.init(reference: ref, kind: "uninterpreted-claim", answerType: value.answerType,
          reviewerKind: reviewerKind, reviewerID: reviewerID, reviewerVersion: reviewerVersion))
      }
      if let prior = declaredSplits[selection.group], prior != selection.split {
        throw DrawingExchangeError.malformed("One declared task group crosses training/holdout splits")
      }
      declaredSplits[selection.group] = selection.split
      let keys = try groupingKeys(receipt.drawing, package: package).union(selection.relatedGroups.map { "declared:" + $0 })
      for key in keys {
        if let prior = groups[key], prior.0 != selection.group || prior.1 != selection.split {
          throw DrawingExchangeError.malformed("Related source/parent/session evidence crosses task groups or splits")
        }
        groups[key] = (selection.group, selection.split)
      }
      var exclusions: [String] = [], limitations: [String] = []
      let outcome = snapshot?.state ?? "refused"
      if snapshot == nil { limitations.append("Refused before a staged attempt; no physical observation or missing-as-negative label.") }
      if snapshot?.environment == "simulation" { limitations.append("Simulation is distinct from live physical evidence.") }
      if !claims.isEmpty { limitations.append("Testimony, artistic preference and later analysis remain separately attributed claims.") }
      if !taskUnsupported.isEmpty { limitations.append(contentsOf: taskUnsupported) }
      if task != .inspection, keys.contains(where: { $0.hasPrefix("unknown-") }) { exclusions.append("Source or parent grouping is unavailable; independent training/holdout membership is not established.") }
      switch task {
      case .inspection:
        guard selection.split == .inspection else { throw DrawingExchangeError.malformed("Inspection cannot declare a training or holdout label") }
      case .interruption:
        if snapshot == nil { exclusions.append("A pre-attempt refusal has no recorded interruption frontier.") }
        if let snapshot, !["staged", "running", "cancelling", "interrupted", "failed", "cancelled"].contains(snapshot.state) {
          exclusions.append("This snapshot is not a recorded interrupted or unsuccessful stage.")
        }
        if let snapshot, !["live", "simulation"].contains(snapshot.environment) { exclusions.append("Recorded environment is unsupported or unknown.") }
        if let ref = selection.snapshot, !package.interpretableAttempts.contains(ref) {
          exclusions.append("Exact selected snapshot owner proof is unavailable; index requirements: " + index.requiredFeatures.joined(separator: ",")
            + "; snapshot requirements: " + (snapshot?.requiredFeatures.joined(separator: ",") ?? ""))
        }
      case .alignedResidual:
        if snapshot == nil { exclusions.append("A refused job has no aligned attributable observation.") }
        if let snapshot {
          if snapshot.environment != "live" { exclusions.append("Residual training requires live attributable observations, not simulation or unknown environment.") }
          if snapshot.observation != "accepted" { exclusions.append("Observation is rejected or unavailable; absence is not a negative residual label.") }
        }
        // No residual learner/measurement contract is registered by the Drawing
        // cutover. A frame, accepted outcome or human note is not such a label.
        exclusions.append("No registered aligned-residual label decoder proves exact target/observation/registration; inspection remains available.")
      }
      limitations.append("Raw monotonic ticks without a declared clock namespace cannot establish cross-event elapsed time.")
      limitations.append("Additional unrecorded subject/session connections are unknown, not asserted independent.")
      entries.append(.init(selection: selection, drawing: receipt.drawing, outcome: outcome,
        environment: snapshot?.environment, claims: claims, groupingKeys: keys.sorted(),
        eligible: exclusions.isEmpty, exclusions: exclusions, limitations: Array(Set(limitations)).sorted()))
    }
    let manifest = DrawingEvidenceTaskManifest(profile: profile, requiredFeatures: [], id: id, task: task,
      taskVersion: "1", inputContract: task.inputContract, labelContract: task.labelContract,
      sourceIndex: source, includedAsOf: index.includedAsOf, extractorRevision: extractorRevision,
      modelRevision: modelRevision, modelRevisionUnavailableReason: modelRevision == nil ? "No model revision was recorded for this frozen evidence task." : nil,
      entries: entries)
    let bytes = try DrawingArtifactCoding.encoder().encode(manifest)
    let asset = try ExchangeAsset(bytes: bytes, mediaType: "application/json", encoding: profile)
    return .init(manifest: manifest, asset: asset, originalJSON: bytes)
  }

  /// Recompute the task policy from the receiver's own exact result admission.
  /// Frozen eligibility booleans are never trusted as portable authority.
  public static func read(_ package: ValidatedExchangePackage) throws -> FrozenDrawingEvidenceTask {
    guard let index = package.index.known, let scope = index.scope, scope.encoding == profile else {
      throw DrawingExchangeError.unsupportedProfile("Drawing evidence task scope unavailable")
    }
    let bytes = try package.files.record(scope.object)
    try scope.validate(bytes)
    let manifest = try JSONDecoder().decode(DrawingEvidenceTaskManifest.self, from: bytes)
    guard manifest.profile == profile, manifest.requiredFeatures.isEmpty, manifest.taskVersion == "1",
      manifest.inputContract == manifest.task.inputContract, manifest.labelContract == manifest.task.labelContract,
      manifest.includedAsOf == index.includedAsOf else { throw DrawingExchangeError.malformed("Unsupported or malformed evidence task contract") }
    let sourceBytes = try package.files.record(manifest.sourceIndex.object)
    try manifest.sourceIndex.validate(sourceBytes)
    let sourceIndex = try ExchangeIndex(originalJSON: sourceBytes)
    guard sourceIndex.kind == "result",
      manifest.sourceIndex == (try ExchangeAsset(bytes: sourceBytes, mediaType: "application/json", encoding: "adaptiveplotter.exchange/1")) else {
      throw DrawingExchangeError.malformed("Task original result index differs from its included evidence")
    }
    let derived = try taskIndex(source: sourceBytes, sourceAsset: manifest.sourceIndex, taskAsset: scope)
    guard try canonicalJSON(ExchangeJSON.validate(index.originalJSON)) == canonicalJSON(derived) else {
      throw DrawingExchangeError.malformed("Task carrier is not the exact allowed derivation of its original result index")
    }
    // All original references, requirements and descriptors occur unchanged in
    // the fully admitted outer closure. The replaced original scope is the one
    // additional edge that must be proved against the original descriptor set.
    if let originalScope = sourceIndex.scope {
      guard sourceIndex.assets.contains(where: { $0.asset == originalScope }) else {
        throw DrawingExchangeError.malformed("Task original scope was not declared by its source index")
      }
      _ = try package.files.validateAsset(.init(asset: originalScope))
    }
    let expected = try freeze(package, task: manifest.task, selections: manifest.entries.map(\.selection),
      extractorRevision: manifest.extractorRevision, modelRevision: manifest.modelRevision, id: manifest.id).manifest
    guard expected.entries == manifest.entries, expected.modelRevisionUnavailableReason == manifest.modelRevisionUnavailableReason else {
      throw DrawingExchangeError.malformed("Task membership, source grouping or eligibility differs from exact evidence")
    }
    return .init(manifest: manifest, asset: scope, originalJSON: bytes)
  }

  /// Export a new immutable task carrier. Original Drawing, receipts, snapshots,
  /// raw payloads and media are copied byte-for-byte; only the new index scope
  /// and its added task/index assets differ from the source delivery.
  public static func export(_ frozen: FrozenDrawingEvidenceTask, from package: ValidatedExchangePackage,
    to destination: URL, payloadValidators: ExchangePayloadValidators = DrawingDestinationResult.payloadValidators) throws {
    let manifest = frozen.manifest
    try frozen.asset.validate(frozen.originalJSON)
    guard manifest.sourceIndex.object == .hash(package.index.originalJSON),
      try freeze(package, task: manifest.task, selections: manifest.entries.map(\.selection),
        extractorRevision: manifest.extractorRevision, modelRevision: manifest.modelRevision, id: manifest.id).originalJSON == frozen.originalJSON,
      !FileManager.default.fileExists(atPath: destination.path) else {
      throw DrawingExchangeError.malformed("Task source or immutable destination differs")
    }
    let temporary = destination.deletingLastPathComponent().appendingPathComponent(".drawing-task-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: temporary) }
    let bag = temporary.appendingPathComponent("bag", isDirectory: true)
    try DrawingExchangeCarrier.preserveDirectory(package.files, to: bag)
    for (asset, bytes) in [(manifest.sourceIndex, package.index.originalJSON), (frozen.asset, frozen.originalJSON)] {
      let path = bag.appendingPathComponent("data/objects/sha256/" + asset.object.description)
      try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
      if !FileManager.default.fileExists(atPath: path.path) { try bytes.write(to: path, options: .atomic) }
      else { try asset.validate(Data(contentsOf: path)) }
    }
    let index = try taskIndex(source: package.index.originalJSON, sourceAsset: manifest.sourceIndex, taskAsset: frozen.asset)
    try canonicalJSON(index)
      .write(to: bag.appendingPathComponent("data/exchange.json"), options: .atomic)
    try DrawingDestinationResult.seal(bag)
    let staged = try DrawingExchangeCarrier.stageDirectory(bag, stagingParent: temporary)
    let admitted = try ExchangeAdmission.validate(staged, payloadValidators: payloadValidators)
    let zip = temporary.appendingPathComponent("task.zip")
    try DrawingExchangeCarrier.preserveZIP(admitted.files, to: zip)
    let fd = Darwin.open(zip.path, O_RDONLY | O_NOFOLLOW)
    guard fd >= 0 else { throw DrawingExchangeError.malformed("Task synchronization") }
    let synchronized = Darwin.fsync(fd); Darwin.close(fd)
    guard synchronized == 0, Darwin.renamex_np(zip.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
      throw DrawingExchangeError.malformed("Immutable task publication")
    }
    let parent = Darwin.open(destination.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY)
    guard parent >= 0 else { throw DrawingExchangeError.malformed("Task directory synchronization") }
    let result = Darwin.fsync(parent); Darwin.close(parent)
    guard result == 0 else { throw DrawingExchangeError.malformed("Task directory synchronization") }
  }

  /// The sole task-carrier index transformation. Preserve every unknown field
  /// and original descriptor verbatim as JSON values; only append these two
  /// immutable assets and replace scope. Read uses precisely this same rule.
  private static func taskIndex(source: Data, sourceAsset: ExchangeAsset, taskAsset: ExchangeAsset) throws -> [String: Any] {
    var index = try ExchangeJSON.validate(source)
    guard index["profile"] as? String == "adaptiveplotter.exchange/1", index["kind"] as? String == "result",
      var assets = index["assets"] as? [[String: Any]] else {
      throw DrawingExchangeError.malformed("Task original index profile, kind or asset descriptors")
    }
    for asset in [sourceAsset, taskAsset] {
      let descriptor = try ExchangeJSON.validate(DrawingArtifactCoding.encoder().encode(ExchangeAssetDescriptor(asset: asset)))
      let encoded = try canonicalJSON(descriptor)
      let contains = try assets.contains(where: { try canonicalJSON($0) == encoded })
      if !contains { assets.append(descriptor) }
    }
    index["assets"] = assets
    index["scope"] = try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(taskAsset))
    return index
  }

  private static func canonicalJSON(_ value: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
  }

  private static func groupingKeys(_ drawing: DrawingRef, package: ValidatedExchangePackage) throws -> Set<String> {
    var result = Set<String>(), seen = Set<DrawingRef>()
    func visit(_ ref: DrawingRef) throws {
      guard seen.insert(ref).inserted else { return }
      result.insert("drawing:" + ref.issuer.uuidString.lowercased() + "/" + ref.revision.uuidString.lowercased())
      guard let admission = package.drawings[ref], case .materialized(let frozen) = admission else {
        result.insert("unknown-drawing:" + ref.digest.description); return
      }
      switch frozen.drawing.parent {
      case .present(let parent): try visit(parent)
      case .unavailable: result.insert("unknown-parent:" + ref.digest.description)
      case .none: break
      }
      if case .unavailable = frozen.drawing.input { result.insert("unknown-input:" + ref.digest.description) }
      if case .present(let input) = frozen.drawing.input {
        result.insert("input:" + input.issuer.uuidString.lowercased() + "/" + input.revision.uuidString.lowercased())
        let raw = try package.files.record(at: "data/inputs/" + input.issuer.uuidString.lowercased() + "/" + input.revision.uuidString.lowercased() + "/input.json")
        let json = try ExchangeJSON.validate(raw)
        guard json["profile"] as? String == "adaptiveplotter.image-input/1",
          (json["requiredFeatures"] as? [String])?.isEmpty == true else {
          result.insert("unknown-input:" + input.digest.description); return
        }
        let photo = try JSONDecoder().decode(PhotoRef.self, from: JSONSerialization.data(withJSONObject: json["photo"] as Any))
        result.insert("photo:" + photo.issuer.uuidString.lowercased() + "/" + photo.revision.uuidString.lowercased())
        let photoJSON = try ExchangeJSON.validate(package.files.record(at: "data/photos/" + photo.issuer.uuidString.lowercased() + "/" + photo.revision.uuidString.lowercased() + "/photo.json"))
        guard photoJSON["profile"] as? String == "adaptiveplotter.photo/1",
          (photoJSON["requiredFeatures"] as? [String])?.isEmpty == true else {
          result.insert("unknown-photo:" + photo.digest.description); return
        }
        let asset = try JSONDecoder().decode(ExchangeAsset.self, from: JSONSerialization.data(withJSONObject: photoJSON["original"] as Any))
        result.insert("photo-bytes:" + asset.object.description)
        if let capture = photoJSON["captureFacts"] {
          let descriptor = try JSONDecoder().decode(ExchangeAsset.self, from: JSONSerialization.data(withJSONObject: capture))
          let bytes = try package.files.record(descriptor.object)
          try descriptor.validate(bytes)
          let factsJSON = descriptor.encoding == "utf8-json" && descriptor.mediaType == "application/json" ? try ExchangeJSON.validate(bytes) : nil
          if photoJSON["profile"] as? String == "adaptiveplotter.photo/1",
            (photoJSON["requiredFeatures"] as? [String])?.isEmpty == true,
            let factsJSON, factsJSON["requiredFeatures"] == nil || (factsJSON["requiredFeatures"] as? [String])?.isEmpty == true,
            let facts = try? JSONDecoder().decode(FlowPortfolioCaptureProvenance.self, from: bytes),
            facts.imageSHA256 == asset.object.description {
            result.insert("capture-session:" + facts.captureSessionID.uuidString.lowercased())
          } else { result.insert("unknown-capture-session:" + descriptor.object.description) }
        }
      }
    }
    try visit(drawing)
    return result
  }
}
