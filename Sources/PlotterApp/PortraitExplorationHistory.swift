import Foundation
import Observation

/// Completed transient drawings, independent of qualified durable retention.
/// Byte accounting bounds encoded candidate payloads; it is not a process-RSS
/// measurement. Navigation metadata has a separate finite visit limit.
@Observable @MainActor
final class PortraitExplorationHistory {
  private struct Node {
    let candidate: PortraitCandidate
    let encodedBytes: Int
  }

  private let maximumCount: Int
  private let maximumBytes: Int
  private let maximumVisits: Int
  private var nodes: [String: Node] = [:]
  private var insertionOrder: [String] = []
  private var visits: [String] = []
  private var cursor = -1
  private(set) var retainedBytes = 0
  private(set) var status: String?

  init(maximumCount: Int = 24, maximumBytes: Int = 96 * 1024 * 1024) {
    self.maximumCount = max(1, maximumCount)
    self.maximumBytes = max(1, maximumBytes)
    maximumVisits = self.maximumCount > Int.max / 4 ? Int.max : max(2, self.maximumCount * 4)
  }

  var current: PortraitCandidate? {
    guard visits.indices.contains(cursor) else { return nil }
    return nodes[visits[cursor]]?.candidate
  }
  var candidates: [PortraitCandidate] { insertionOrder.compactMap { nodes[$0]?.candidate } }
  var parent: PortraitCandidate? {
    guard let id = current?.lineage.parentID else { return nil }
    return nodes[id]?.candidate
  }
  var children: [PortraitCandidate] {
    guard let id = current?.id else { return [] }
    return candidates.filter { $0.lineage.parentID == id }
  }
  var canGoBack: Bool { cursor > 0 }
  var canGoForward: Bool { cursor >= 0 && cursor + 1 < visits.count }

  func record(_ candidate: PortraitCandidate) {
    // The first completed payload owns this identity, including its metadata.
    // Repeated renders of the same identity are visits, never replacements.
    if nodes[candidate.id] != nil {
      _ = select(candidate.id)
      return
    }
    let size: Int
    do {
      try candidate.validateIntegrity()
      size = try PortraitCandidateCoding.encoder().encode(candidate).count
    } catch {
      status = "This drawing could not enter transient history: \(error.localizedDescription)"
      return
    }
    guard size <= maximumBytes else {
      status = "This drawing exceeds the transient history limit; exact history recovery is unavailable."
      return
    }
    // The incoming drawing becomes current. Expire older payloads only; use
    // subtraction before addition so budget accounting cannot overflow Int.
    var evicted = false
    while insertionOrder.count >= maximumCount || retainedBytes > maximumBytes - size {
      guard !insertionOrder.isEmpty else { break }
      let expired = insertionOrder.removeFirst()
      if let node = nodes.removeValue(forKey: expired) { retainedBytes -= node.encodedBytes }
      evicted = true
    }
    nodes[candidate.id] = Node(candidate: candidate, encodedBytes: size)
    insertionOrder.append(candidate.id)
    retainedBytes += size
    appendVisit(candidate.id)
    pruneVisits()
    status = evicted ? "Older transient drawings expired; their exact history recovery is unavailable." : nil
  }

  @discardableResult
  func select(_ id: String) -> PortraitCandidate? {
    guard let candidate = nodes[id]?.candidate else {
      status = "This drawing expired or is unavailable in transient history; exact recovery is unavailable."
      return nil
    }
    appendVisit(id)
    status = nil
    return candidate
  }

  @discardableResult
  func goBack() -> PortraitCandidate? {
    guard canGoBack else { return nil }
    cursor -= 1
    status = nil
    return current
  }

  @discardableResult
  func goForward() -> PortraitCandidate? {
    guard canGoForward else { return nil }
    cursor += 1
    status = nil
    return current
  }

  @discardableResult
  func goToParent() -> PortraitCandidate? {
    guard let parentID = current?.lineage.parentID else { return nil }
    guard nodes[parentID] != nil else {
      status = "The parent drawing expired or is unavailable in transient history; exact recovery is unavailable."
      return nil
    }
    return select(parentID)
  }

  private func appendVisit(_ id: String) {
    if current?.id == id { return }
    if cursor + 1 < visits.count { visits.removeSubrange((cursor + 1)..<visits.count) }
    visits.append(id)
    if visits.count > maximumVisits { visits.removeFirst(visits.count - maximumVisits) }
    cursor = visits.count - 1
  }

  private func pruneVisits() {
    let retainedBeforeCurrent = visits.prefix(cursor + 1).filter { nodes[$0] != nil }.count
    visits.removeAll { nodes[$0] == nil }
    cursor = retainedBeforeCurrent - 1
  }
}
