import Foundation

/// Source identity, declared subjects and sessions form connected components.
/// Compute the exact canonical key set once per component, before curation.
/// Excluded sources still join groups so holdouts cannot leak through a bridge.
enum FlowSourceConnectivity {
  static func groups(_ members: [(id: UUID, keys: [String])]) -> [UUID: String] {
    var parents = Array(members.indices), sizes = Array(repeating: 1, count: members.count)
    var keyOwners: [String: Int] = [:]
    func root(_ index: Int) -> Int {
      var current = index
      while parents[current] != current {
        parents[current] = parents[parents[current]]
        current = parents[current]
      }
      return current
    }
    for (index, member) in members.enumerated() {
      for key in member.keys {
        if let owner = keyOwners[key] {
          var left = root(index), right = root(owner)
          if left == right { continue }
          if sizes[left] < sizes[right] { swap(&left, &right) }
          parents[right] = left; sizes[left] += sizes[right]
        } else { keyOwners[key] = index }
      }
    }
    var componentKeys: [Int: Set<String>] = [:]
    for (index, member) in members.enumerated() {
      componentKeys[root(index), default: []].formUnion(member.keys)
    }
    let canonical = componentKeys.mapValues { $0.sorted().joined(separator: "|") }
    return Dictionary(uniqueKeysWithValues: members.enumerated().map { index, member in
      (member.id, canonical[root(index)]!)
    })
  }
}
