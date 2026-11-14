import Foundation
import PortraitLibrary
import PlotterModel

/// Replays the current candidate's save path only on the harness's disposable Library clone.
enum FlowPruningProfile {
  static func run(store: FlowPortfolioStore, initial: FlowPortfolioSnapshot, directory: URL,
    output: URL, openMS: Double, fullDecoder: Bool, roundTrip: Bool) async throws {
    guard let candidateID = initial.currentCandidateID,
      let candidate = initial.candidates.first(where: { $0.id == candidateID }) else {
      throw FlowProductionProfile.ProfileError.missingConfiguration
    }
    let original = initial.latestPrune(candidateID: candidateID)?.removedIndices ?? []
    let removed = Set(original)
    guard let index = (0..<candidate.strokeCount).first(where: { !removed.contains($0) }),
      candidate.strokeCount - removed.count > 1 else {
      throw FlowProductionProfile.ProfileError.missingConfiguration
    }
    let initialFeedback = try await store.feedbackProjectionDigest()
    var rows: [[String: Any]] = []
    let actions: [(FlowPruneAction, [Int])] = roundTrip
      ? [(.remove, [index]), (.undo, []), (.redo, []), (.restore, [index]), (.completeTarget, [])]
      : [(.remove, [index])]
    for (action, indices) in actions {
      FileHandle.standardError.write(Data("Beginning prune \(action.rawValue)\n".utf8))
      let began = Date()
      let revision = try await store.applyPrune(candidateID: candidateID, action: action, indices: indices)
      let milliseconds = Date().timeIntervalSince(began) * 1000
      let retained = await store.snapshot().latestPrune(candidateID: candidateID)?.drawing != nil
      rows.append(["action": action.rawValue, "milliseconds": milliseconds,
        "removedIndices": revision.removedIndices, "revisionID": revision.id.uuidString,
        "retainedDrawing": retained])
      print("Prune \(action.rawValue): \(milliseconds) ms")
      try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        .write(to: output.appendingPathComponent("pruning-progress.json"), options: .atomic)
    }
    let expected = roundTrip ? original : (original + [index]).sorted()
    guard await store.snapshot().latestPrune(candidateID: candidateID)?.removedIndices == expected,
      try await store.feedbackProjectionDigest(matching: initial) == initialFeedback else {
      throw FlowProductionProfile.ProfileError.feedbackChanged
    }
    let feedback = try await store.feedbackProjectionDigest()
    await store.closeLibrary()
    let reopened = FlowPortfolioStore(directory: directory)
    try await reopened.loadRecords(reusingEncodedStrokeBasis: !fullDecoder)
    let reopenedState = await reopened.snapshot()
    guard let revision = reopenedState.latestPrune(candidateID: candidateID),
      revision.removedIndices == expected,
      reopenedState.pruneRevisions.count == initial.pruneRevisions.count + actions.count,
      try await reopened.feedbackProjectionDigest() == feedback else {
      throw FlowProductionProfile.ProfileError.reopenMismatch
    }
    let drawing = try await reopened.retainedDrawing(candidateID: candidateID, revisionID: revision.id)
    let base = try await reopened.candidateProgram(candidateID)
    let expectedRemoved = Set(expected)
    let expectedStrokes = base.strokes.enumerated().filter { !expectedRemoved.contains($0.offset) }.map(\.element)
    guard drawing.program.strokes == expectedStrokes else {
      throw FlowProductionProfile.ProfileError.reopenMismatch
    }
    await reopened.closeLibrary()
    let receipt: [String: Any] = ["scope": "Current candidate pruning on disposable copied Library; cold reopen and exact kept geometry verified",
      "candidateID": candidateID.uuidString, "candidateTitle": candidate.title as Any,
      "strokeCount": candidate.strokeCount, "initialRemovedIndices": original,
      "finalRemovedIndices": expected, "openMS": openMS, "rows": rows,
      "preservedInitialFeedback": true, "reopenedExactFeedback": true,
      "reopenedExactKeptStrokes": true]
    try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
      .write(to: output.appendingPathComponent("pruning-profile.json"), options: .atomic)
    print(output.appendingPathComponent("pruning-profile.json").path)
  }
}
