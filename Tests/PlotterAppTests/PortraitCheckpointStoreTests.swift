import Darwin
import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Durable named-style checkpoint ownership")
struct PortraitCheckpointStoreTests {
  @Test("an absent library is a healthy empty renderer prior")
  func empty() async throws {
    let directory = checkpointDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let result = await PortraitCheckpointStore(directory: directory).load()
    #expect(result.canWrite)
    #expect(result.issues.isEmpty)
    #expect(result.snapshot.scopes.isEmpty)
    #expect(result.snapshot.checkpoints.isEmpty)
    #expect(result.snapshot.activeCheckpointIDs.isEmpty)
  }

  @Test("restart preserves immutable datasets, explicit activation and rollback")
  func restartAndRollback() async throws {
    let directory = checkpointDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let scope = try checkpointScope()
    let parent = try await checkpointFixture(scope: scope)
    let child = try await checkpointFixture(scope: scope, parent: parent, count: 9)
    let store = PortraitCheckpointStore(directory: directory)
    _ = try await store.saveScope(scope)
    let installed = try await store.install(parent)
    #expect(installed.activeCheckpointIDs.isEmpty)
    _ = try await store.activate(parent.id, scopeID: scope.id)
    _ = try await store.install(child)
    let restarted = PortraitCheckpointStore(directory: directory)
    let loaded = await restarted.load()
    #expect(loaded.canWrite)
    #expect(loaded.snapshot.activeCheckpointIDs[scope.id.uuidString] == parent.id)
    let restoredChild = try #require(loaded.snapshot.checkpoints.first { $0.id == child.id })
    #expect(restoredChild.payload.parentCheckpointID == parent.id)
    #expect(restoredChild.payload.initialization == .deterministicFullRefit)
    #expect(restoredChild.payload.optimizerState == .reset)
    #expect(restoredChild.payload.dataset.id == child.payload.dataset.id)
    #expect(restoredChild.payload.dataset.payload.rows.map(\.label.id) == child.payload.dataset.payload.rows.map(\.label.id))
    _ = try await restarted.activate(child.id, scopeID: scope.id)
    _ = try await restarted.activate(parent.id, scopeID: scope.id)
    let rolledBack = await PortraitCheckpointStore(directory: directory).load()
    #expect(rolledBack.snapshot.activeCheckpointIDs[scope.id.uuidString] == parent.id)
    _ = try await restarted.activate(nil, scopeID: scope.id)
    let prior = await PortraitCheckpointStore(directory: directory).load()
    #expect(prior.snapshot.activeCheckpointIDs.isEmpty)
    #expect(prior.snapshot.checkpoints.count == 2)
  }

  @Test("scope IDs, exact parent ownership and activation scope cannot be substituted")
  func identityAndParent() async throws {
    let directory = checkpointDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let scope = try checkpointScope()
    let parent = try await checkpointFixture(scope: scope)
    let child = try await checkpointFixture(scope: scope, parent: parent, count: 9)
    let store = PortraitCheckpointStore(directory: directory)
    await #expect(throws: (any Error).self) { try await store.install(parent) }
    _ = try await store.saveScope(scope)
    let conflicting = PortraitTrainingScopeDefinition(scope: .init(id: scope.id, name: "Changed meaning",
      revision: scope.scope.revision, objective: scope.scope.objective, allowedFamilies: scope.scope.allowedFamilies,
      activeParameters: scope.scope.activeParameters, frozenParameters: scope.scope.frozenParameters),
      mode: scope.mode, referenceRecipe: scope.referenceRecipe, schemaRevision: scope.schemaRevision)
    await #expect(throws: (any Error).self) { try await store.saveScope(conflicting) }
    await #expect(throws: (any Error).self) { try await store.install(child) }
    _ = try await store.install(parent)
    let repeated = try await store.install(parent)
    #expect(repeated.checkpoints.count == 1)
    let other = try checkpointScope()
    _ = try await store.saveScope(other)
    await #expect(throws: (any Error).self) { try await store.activate(parent.id, scopeID: other.id) }
    await #expect(throws: (any Error).self) { try await store.activate(nil, scopeID: UUID()) }
    let final = await store.load()
    #expect(final.snapshot.scopes.count == 2)
    #expect(final.snapshot.activeCheckpointIDs.isEmpty)
  }

  @Test("changed payload under an old ID and rehashed invalid numerical models are refused")
  func decodedModelValidation() async throws {
    let directory = checkpointDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let scope = try checkpointScope()
    let checkpoint = try await checkpointFixture(scope: scope)
    let store = PortraitCheckpointStore(directory: directory)
    _ = try await store.saveScope(scope)
    _ = try await store.install(checkpoint)
    _ = try await store.activate(checkpoint.id, scopeID: scope.id)
    var json = try #require(JSONSerialization.jsonObject(with: PortraitCandidateCoding.encoder().encode(checkpoint)) as? [String: Any])
    var payload = try #require(json["payload"] as? [String: Any])
    var model = try #require(payload["model"] as? [String: Any])
    model["thresholds"] = [1, 1, 1, 1]
    payload["model"] = model; json["payload"] = payload
    let decoded = try JSONDecoder().decode(PortraitPreferenceCheckpoint.self, from: JSONSerialization.data(withJSONObject: json))
    await #expect(throws: (any Error).self) { try await store.install(decoded) }
    let rehashed = try PortraitPreferenceCheckpoint(payload: decoded.payload)
    await #expect(throws: (any Error).self) { try await store.install(rehashed) }
    let result = await store.load()
    #expect(result.canWrite)
    #expect(result.snapshot.checkpoints.map(\.id) == [checkpoint.id])
    #expect(result.snapshot.activeCheckpointIDs[scope.id.uuidString] == checkpoint.id)
  }

  @Test("missing model disables dependent children without losing healthy models; repairing bytes recovers")
  func missingParentRecovery() async throws {
    let directory = checkpointDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let scope = try checkpointScope()
    let parent = try await checkpointFixture(scope: scope)
    let child = try await checkpointFixture(scope: scope, parent: parent, count: 9)
    let store = PortraitCheckpointStore(directory: directory)
    _ = try await store.saveScope(scope)
    _ = try await store.install(parent)
    _ = try await store.install(child)
    _ = try await store.activate(child.id, scopeID: scope.id)
    let url = checkpointAsset(parent.id, in: directory)
    let original = try Data(contentsOf: url)
    try FileManager.default.removeItem(at: url)
    let restarted = PortraitCheckpointStore(directory: directory)
    let damaged = await restarted.load()
    #expect(!damaged.canWrite)
    #expect(!damaged.issues.isEmpty)
    #expect(damaged.snapshot.checkpoints.isEmpty)
    #expect(damaged.snapshot.activeCheckpointIDs.isEmpty)
    let index = try Data(contentsOf: directory.appendingPathComponent("index-v1.json"))
    await #expect(throws: (any Error).self) { try await restarted.activate(nil, scopeID: scope.id) }
    #expect(try Data(contentsOf: directory.appendingPathComponent("index-v1.json")) == index)
    try original.write(to: url)
    let recovered = await restarted.load()
    #expect(recovered.canWrite)
    #expect(recovered.snapshot.checkpoints.count == 2)
    #expect(recovered.snapshot.activeCheckpointIDs[scope.id.uuidString] == child.id)
  }

  @Test("corrupt model bytes preserve healthy parent and block archive replacement")
  func corruptAsset() async throws {
    let directory = checkpointDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let scope = try checkpointScope()
    let parent = try await checkpointFixture(scope: scope)
    let child = try await checkpointFixture(scope: scope, parent: parent, count: 9)
    let store = PortraitCheckpointStore(directory: directory)
    _ = try await store.saveScope(scope)
    _ = try await store.install(parent)
    _ = try await store.install(child)
    _ = try await store.activate(parent.id, scopeID: scope.id)
    let url = checkpointAsset(child.id, in: directory)
    let original = try Data(contentsOf: url)
    try Data("corrupt model".utf8).write(to: url)
    let damaged = await PortraitCheckpointStore(directory: directory).load()
    #expect(!damaged.canWrite)
    #expect(damaged.snapshot.checkpoints.map(\.id) == [parent.id])
    #expect(damaged.snapshot.activeCheckpointIDs[scope.id.uuidString] == parent.id)
    await #expect(throws: (any Error).self) { try await store.install(child) }
    #expect(try Data(contentsOf: url) == Data("corrupt model".utf8))
    try original.write(to: url)
    #expect(await store.load().canWrite)
  }

  @Test("forged checksummed index associations are rejected")
  func invalidIndexAssociations() async throws {
    let directory = checkpointDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let scope = try checkpointScope()
    let parent = try await checkpointFixture(scope: scope)
    let store = PortraitCheckpointStore(directory: directory)
    _ = try await store.saveScope(scope)
    _ = try await store.install(parent)
    _ = try await store.activate(parent.id, scopeID: scope.id)
    let url = directory.appendingPathComponent("index-v1.json")
    let original = try Data(contentsOf: url)
    for mutation in ["cycle", "unknownScope", "unknownActivation", "checksum"] {
      var envelope = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
      var payload = try #require(envelope["payload"] as? [String: Any])
      var entries = try #require(payload["checkpoints"] as? [[String: Any]])
      switch mutation {
      case "cycle": entries[0]["parentCheckpointID"] = parent.id
      case "unknownScope": entries[0]["scopeID"] = UUID().uuidString
      case "unknownActivation": payload["activeCheckpointIDs"] = [scope.id.uuidString: String(repeating: "0", count: 64)]
      default: payload["revision"] = "future-format"
      }
      payload["checkpoints"] = entries
      envelope["payload"] = payload
      if mutation != "checksum" {
        let typedPayload = try JSONDecoder().decode(CheckpointIndexFixture.self,
          from: JSONSerialization.data(withJSONObject: payload))
        envelope["sha256"] = PortraitCandidateCoding.digest(try PortraitCandidateCoding.encoder().encode(typedPayload))
      }
      let badBytes = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys, .withoutEscapingSlashes])
      try badBytes.write(to: url)
      let restarted = PortraitCheckpointStore(directory: directory)
      let result = await restarted.load()
      #expect(!result.canWrite)
      #expect(result.snapshot.checkpoints.isEmpty)
      let expected = switch mutation {
      case "cycle": "cyclic"
      case "unknownScope": "unknown scope"
      case "unknownActivation": "impossible activation"
      default: "checksum"
      }
      #expect(result.issues.contains { $0.localizedCaseInsensitiveContains(expected) },
        "Mutation \(mutation) expected \(expected), received: \(result.issues.joined(separator: "; "))")
      await #expect(throws: (any Error).self) { try await restarted.saveScope(scope) }
      #expect(try Data(contentsOf: url) == badBytes)
    }
    try original.write(to: url)
    #expect(await store.load().canWrite)
  }

  @Test("a failed model install preserves the active prior and can be retried")
  func failedInstallRecovery() async throws {
    let directory = checkpointDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let scope = try checkpointScope()
    let parent = try await checkpointFixture(scope: scope)
    let child = try await checkpointFixture(scope: scope, parent: parent, count: 9)
    let store = PortraitCheckpointStore(directory: directory)
    _ = try await store.saveScope(scope)
    _ = try await store.install(parent)
    _ = try await store.activate(parent.id, scopeID: scope.id)
    let obstruction = checkpointAsset(child.id, in: directory)
    try FileManager.default.createDirectory(at: obstruction, withIntermediateDirectories: false)
    await #expect(throws: (any Error).self) { try await store.install(child) }
    let prior = await store.load()
    #expect(prior.canWrite)
    #expect(prior.snapshot.checkpoints.map(\.id) == [parent.id])
    #expect(prior.snapshot.activeCheckpointIDs[scope.id.uuidString] == parent.id)
    try FileManager.default.removeItem(at: obstruction)
    let installed = try await store.install(child)
    #expect(installed.checkpoints.count == 2)
    #expect(installed.activeCheckpointIDs[scope.id.uuidString] == parent.id)
  }

  @Test("failed activation does not replace the previously committed active checkpoint")
  func failedActivationRecovery() async throws {
    let directory = checkpointDirectory()
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
      try? FileManager.default.removeItem(at: directory) }
    let scope = try checkpointScope()
    let parent = try await checkpointFixture(scope: scope)
    let child = try await checkpointFixture(scope: scope, parent: parent, count: 9)
    let store = PortraitCheckpointStore(directory: directory)
    _ = try await store.saveScope(scope)
    _ = try await store.install(parent)
    _ = try await store.install(child)
    _ = try await store.activate(parent.id, scopeID: scope.id)
    // The application runs as a normal macOS user; this exercises the real filesystem failure.
    try #require(geteuid() != 0)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    await #expect(throws: (any Error).self) { try await store.activate(child.id, scopeID: scope.id) }
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    let prior = await PortraitCheckpointStore(directory: directory).load()
    #expect(prior.snapshot.activeCheckpointIDs[scope.id.uuidString] == parent.id)
    let activated = try await store.activate(child.id, scopeID: scope.id)
    #expect(activated.activeCheckpointIDs[scope.id.uuidString] == child.id)
  }
}

private func checkpointDirectory() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent("portrait-checkpoints-\(UUID().uuidString)")
}

private func checkpointAsset(_ id: String, in directory: URL) -> URL {
  directory.appendingPathComponent("checkpoints").appendingPathComponent(id + ".json")
}

private func checkpointScope() throws -> PortraitTrainingScopeDefinition {
  let recipe = try portraitPersistenceCandidate().recipe
  return .init(scope: .init(id: UUID(), name: "Checkpoint test style", revision: 1,
    objective: .screenAesthetic, allowedFamilies: [.hatch], activeParameters: [.tonalStrength], frozenParameters: []),
    mode: .drawingStyle, referenceRecipe: recipe, schemaRevision: PortraitTrainingScopeDefinition.currentRevision)
}

private func checkpointFixture(scope: PortraitTrainingScopeDefinition,
  parent: PortraitPreferenceCheckpoint? = nil, count: Int = 8) async throws -> PortraitPreferenceCheckpoint {
  let base = try portraitPersistenceCandidate()
  var archive = PortraitCandidateArchive()
  for index in 0..<count {
    var options = scope.referenceRecipe.vectorOptions
    options.tonalStrength = 0.5 + Double(index) * 0.15
    let recipe = PortraitStyleRecipe(id: "checkpoint-fixture-\(index)", title: "Checkpoint fixture",
      seed: UInt64(index), style: .hatch, vectorOptions: options, analysisOptions: scope.referenceRecipe.analysisOptions)
    let style = try StrokeStyle(nominalLineWidth: 0.8,
      penProfileID: PenProfileID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))
    let program = try PortraitVectorizer.program(from: base.raster, pose: .front, style: .hatch,
      strokeStyle: style, vectorOptions: options)
    let candidate = try PortraitCandidate(sourceData: Data([UInt8(index), 13, 57]),
      sourcePixelExtent: base.sourcePixelExtent, raster: base.raster, recipe: recipe, program: program,
      photoID: PortraitVectorizer.stableID("checkpoint-photo-\(index)"),
      captureSessionID: PortraitVectorizer.stableID("checkpoint-session-\(index)"),
      createdAt: Date(timeIntervalSince1970: 100))
    let label = try PortraitLabelRevision(candidate: candidate, rating: min(5, 1 + index / 2), scope: scope.scope,
      presentation: .init(), id: PortraitVectorizer.stableID("checkpoint-label-\(index)"),
      createdAt: Date(timeIntervalSince1970: 100))
    archive.entries.append(.init(candidate: candidate, reasons: [.init(reason: .rated(labelRevisionID: label.id))]))
    archive.labels.append(label)
  }
  let dataset = try PortraitPreferenceDatasetBuilder.freeze(archive: archive, scope: scope, seed: 7)
  var configuration = PortraitOrdinalFitConfiguration.standard
  configuration.maximumIterations = 30
  return try await PortraitOrdinalTrainer.fit(dataset: dataset, parent: parent, configuration: configuration)
}

/// Typed disk-format fixture preserves the same numeric encoding as the store,
/// allowing forged associations to pass checksum validation before rejection.
private struct CheckpointIndexFixture: Codable {
  struct Entry: Codable {
    let id: String
    let sha256: String
    let scopeID: UUID
    let parentCheckpointID: String?
  }
  let revision: String
  let scopes: [PortraitTrainingScopeDefinition]
  let checkpoints: [Entry]
  let activeCheckpointIDs: [String: String]
}
