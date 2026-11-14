import Foundation

/// One synchronous semantic admission owns this context. Resolver authority,
/// descriptors and validator capabilities cannot change underneath its memo.
/// Nothing here survives a public decode or exchange-admission boundary.
final class DrawingRecordAdmissionContext {
  private let sourceObjects: ExchangeObjectResolver
  private var invocationObjects: ExchangeObjectResolver?
  /// Each top-level codec call keeps its original read-work budget. Recursive
  /// calls share it; the closure's scoped file resolver also retains its own
  /// aggregate budget across all calls. Memoization does not enlarge either.
  var objects: ExchangeObjectResolver { invocationObjects ?? freshObjects() }
  let validators: DrawingProducerValidators
  let supportedFeatures: Set<String>
  let assetDescriptors: [ExchangeDigest: ExchangeAssetDescriptor]
  let jsonProofs = ExchangeJSONProofCache()

  private struct Entry {
    let admission: DrawingRecordAdmission
    /// Longest parent/universe edge path, including opaque Drawing endpoints.
    let descendantDepth: Int
  }
  private var completed: [DrawingRef: Entry] = [:]
  private var active = Set<ExchangeDigest>()
  private var deepestVisits: [Int] = []

  init(objects: ExchangeObjectResolver, validators: DrawingProducerValidators,
    supportedFeatures: Set<String>, assetDescriptors: [ExchangeDigest: ExchangeAssetDescriptor]) {
    sourceObjects = objects; self.validators = validators
    self.supportedFeatures = supportedFeatures; self.assetDescriptors = assetDescriptors
  }

  func decode(_ record: Data, expected: DrawingRef?, depth: Int = 0) throws -> DrawingRecordAdmission {
    let isTopLevel = deepestVisits.isEmpty
    if isTopLevel { invocationObjects = freshObjects() }
    defer { if isTopLevel { invocationObjects = nil } }
    guard depth <= 64 else { throw DrawingExchangeError.limit("Record depth") }
    if case .dictionary(let dictionary) = objects, dictionary.count > 10_000 {
      throw DrawingExchangeError.limit("Record closure")
    }
    guard record.count <= ExchangeJSON.maximumRecordBytes else { throw DrawingExchangeError.limit("Record bytes") }
    let digest = ExchangeDigest.hash(record)
    if case .files(let files, _) = objects { files.counters.update { $0.semanticBytesHashed += UInt64(record.count) } }
    if let expected, expected.digest != digest { throw DrawingExchangeError.digestMismatch("Drawing bytes") }
    guard !active.contains(digest) else { throw DrawingExchangeError.malformed("Cyclic drawing dependency") }
    // Exact reference equality includes issuer and revision, not only digest.
    // Even a hit has consumed the caller's verified record read above this layer.
    if let expected, let entry = completed[expected] {
      guard entry.descendantDepth <= 64 - depth else { throw DrawingExchangeError.limit("Record depth") }
      observe(depth + entry.descendantDepth)
      return entry.admission
    }
    active.insert(digest); deepestVisits.append(depth)
    defer { active.remove(digest); deepestVisits.removeLast() }
    let admission = try DrawingExchangeCodec.decodeRecord(record, context: self,
      expected: expected, recordDigest: digest, depth: depth)
    let deepest = deepestVisits.last!
    let reference: DrawingRef?
    switch admission {
    case .materialized(let value): reference = value.reference
    case .opaque: reference = expected
    }
    if let reference {
      completed[reference] = Entry(admission: admission, descendantDepth: deepest - depth)
    }
    if deepestVisits.count > 1 {
      let parent = deepestVisits.count - 2
      deepestVisits[parent] = max(deepestVisits[parent], deepest)
    }
    return admission
  }

  private func observe(_ depth: Int) {
    if !deepestVisits.isEmpty {
      deepestVisits[deepestVisits.count - 1] = max(deepestVisits.last!, depth)
    }
  }

  private func freshObjects() -> ExchangeObjectResolver {
    switch sourceObjects {
    case .dictionary: return sourceObjects
    case .files(let files, _):
      return .files(files, budget: .init(maximum: files.limits.maximumMaterializedBytes))
    }
  }

  /// Memoized dependencies remain exact only while their selected files do.
  /// Invoke once at the successful public boundary, including after callbacks.
  func revalidateFiles() throws {
    if case .files(let files, _) = sourceObjects { try files.revalidateSelected() }
  }
}
