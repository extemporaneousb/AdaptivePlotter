import Foundation
import DrawingLibrary
import PortraitCore

public struct DrawingDestinationDelivery: Codable, Equatable, Sendable {
  public let id: UUID
  public let client: UUID
  public let engine: UUID?
  public let request: DrawingDestinationRequest
  public let authoredCarrier: URL?
  public init(id: UUID = UUID(), client: UUID, engine: UUID?, request: DrawingDestinationRequest, authoredCarrier: URL? = nil) {
    self.id = id; self.client = client; self.engine = engine; self.request = request; self.authoredCarrier = authoredCarrier
  }
}
public struct DrawingDestinationResponse: Codable, Equatable, Sendable {
  public let delivery: UUID
  public let client: UUID
  public let engine: UUID
  public let digest: ExchangeDigest
  public let reply: DrawingDestinationReply
}
/// Each side writes only its own subtree. File names are derived exclusively
/// from typed identities; document URLs are carrier inputs, never execution commands.
public enum DrawingDestinationFiles {
  public static var defaultRoot: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AdaptivePlotter/DrawingDestination", isDirectory: true) }
  public static let maximumControlBytes = 1_048_576
  public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
      let size = values.fileSize, size <= maximumControlBytes else { throw DrawingDestinationRefusal.invalidDelivery }
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    let bytes = try file.read(upToCount: maximumControlBytes + 1) ?? Data()
    guard bytes.count <= maximumControlBytes, try file.read(upToCount: 1)?.isEmpty != false else {
      throw DrawingDestinationRefusal.invalidDelivery
    }
    return try JSONDecoder().decode(type, from: bytes)
  }
  public static func publish<T: Encodable>(_ value: T, to url: URL) throws {
    let bytes = try DrawingArtifactCoding.encoder().encode(value)
    guard bytes.count <= maximumControlBytes else { throw DrawingDestinationRefusal.invalidDelivery }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try bytes.write(to: url, options: .atomic)
  }
  public static func requestURL(root: URL, client: UUID, delivery: UUID) -> URL {
    root.appendingPathComponent("clients/" + client.uuidString.lowercased() + "/requests/" + delivery.uuidString.lowercased() + ".drawingrequest")
  }
  public static func responseURL(root: URL, engine: UUID, client: UUID, delivery: UUID) -> URL {
    root.appendingPathComponent("engines/" + engine.uuidString.lowercased() + "/responses/" + client.uuidString.lowercased() + "/" + delivery.uuidString.lowercased() + ".json")
  }
}
public struct DrawingDestinationPreparationRecovery: Sendable {
  public let responses: [DrawingDestinationResponse]
  public let failures: [String]
}
@MainActor public final class DrawingDestinationFileServer {
  private let service: DrawingDestination
  private let library: DrawingLibrary
  public let root: URL
  private var closing = false
  private var tail: Task<URL, Error>?
  public init(service: DrawingDestination, library: DrawingLibrary, root: URL = DrawingDestinationFiles.defaultRoot) {
    self.service = service; self.library = library; self.root = root
  }
  public func closeAdmission() { closing = true }
  public func close() async { closeAdmission(); _ = try? await tail?.value }
  @discardableResult public func receive(_ url: URL) async throws -> URL {
    guard !closing else { throw DrawingLibraryError.closed }
    let prior = tail
    let task = Task { @MainActor in
      _ = try? await prior?.value
      return try await self.receiveSerial(url)
    }
    tail = task
    return try await task.value
  }
  private func receiveSerial(_ url: URL) async throws -> URL {
    let delivery = try DrawingDestinationFiles.read(DrawingDestinationDelivery.self, from: url)
    guard url.standardizedFileURL == DrawingDestinationFiles.requestURL(root: root, client: delivery.client, delivery: delivery.id).standardizedFileURL,
      case .description(let description) = try await service.handle(.describe),
      delivery.engine == nil || delivery.engine == description.engine else { throw DrawingDestinationRefusal.invalidDelivery }
    let digest = ExchangeDigest.hash(try DrawingArtifactCoding.encoder().encode(delivery))
    let kind = "adaptiveplotter.destination.delivery." + delivery.client.uuidString.lowercased()
    let destination = DrawingDestinationFiles.responseURL(root: root, engine: description.engine, client: delivery.client, delivery: delivery.id)
    if let record = try await library.record(.init(kind: kind, id: delivery.id)) {
      let response = try JSONDecoder().decode(DrawingDestinationResponse.self, from: record.payload)
      guard response.digest == digest else { throw DrawingDestinationRefusal.requestConflict }
      if case .result = response.reply {
        guard case .exportResult = delivery.request,
          try await service.handle(delivery.request) == response.reply else { throw DrawingDestinationRefusal.invalidDelivery }
      }
      try DrawingDestinationFiles.publish(response, to: destination)
      return destination
    }
    switch delivery.request {
    case .submit(let key, _): guard key.namespace == delivery.client else { throw DrawingDestinationRefusal.invalidDelivery }
    case .status(.request(let key)), .cancel(.request(let key)):
      guard key.namespace == delivery.client else { throw DrawingDestinationRefusal.invalidDelivery }
    default: break
    }
    if let carrier = delivery.authoredCarrier {
      guard case .prepare(let ref) = delivery.request, carrier.isFileURL, carrier.path.hasPrefix("/"),
        carrier.standardizedFileURL.pathComponents.starts(with: root.appendingPathComponent("clients/" + delivery.client.uuidString.lowercased() + "/artwork").standardizedFileURL.pathComponents) else { throw DrawingDestinationRefusal.invalidDelivery }
      if (try? await library.drawing(ref)) == nil {
        let refs = try await library.importDrawings(from: carrier)
        guard refs.contains(ref) else { throw DrawingDestinationRefusal.invalidDelivery }
      }
    }
    let reply = try await service.handle(delivery.request)
    let response = DrawingDestinationResponse(delivery: delivery.id, client: delivery.client, engine: description.engine, digest: digest, reply: reply)
    try await library.commitRecords([.init(kind: kind, id: delivery.id,
      payload: try DrawingArtifactCoding.encoder().encode(response))])
    try DrawingDestinationFiles.publish(response, to: destination)
    return destination
  }
  /// Recovery is intentionally Prepare-only. A durable control file is never
  /// authority to submit merely because the engine was relaunched.
  public func drainPreparations() async -> DrawingDestinationPreparationRecovery {
    guard !closing else { return .init(responses: [], failures: []) }
    let clients = root.appendingPathComponent("clients")
    guard let entries = try? FileManager.default.contentsOfDirectory(at: clients, includingPropertiesForKeys: nil) else { return .init(responses: [], failures: []) }
    var failures: [String] = []
    var responses: [DrawingDestinationResponse] = []
    var engine: UUID?
    for client in entries {
      guard !closing, !Task.isCancelled else { break }
      guard UUID(uuidString: client.lastPathComponent) != nil else { continue }
      let urls = (try? FileManager.default.contentsOfDirectory(at: client.appendingPathComponent("requests"), includingPropertiesForKeys: nil)) ?? []
      for url in urls where url.pathExtension == "drawingrequest" {
        guard !closing, !Task.isCancelled else { break }
        do {
          let delivery = try DrawingDestinationFiles.read(DrawingDestinationDelivery.self, from: url)
          guard case .prepare = delivery.request else { continue }
          guard url.standardizedFileURL == DrawingDestinationFiles.requestURL(root: root, client: delivery.client, delivery: delivery.id).standardizedFileURL else {
            throw DrawingDestinationRefusal.invalidDelivery
          }
          if engine == nil, case .description(let description) = try await service.handle(.describe) { engine = description.engine }
          guard let engine, delivery.engine == nil || delivery.engine == engine else { throw DrawingDestinationRefusal.invalidDelivery }
          let responseURL = DrawingDestinationFiles.responseURL(root: root, engine: engine, client: delivery.client, delivery: delivery.id)
          if let response = try? DrawingDestinationFiles.read(DrawingDestinationResponse.self, from: responseURL),
            response.delivery == delivery.id, response.client == delivery.client, response.engine == engine,
            response.digest == .hash(try DrawingArtifactCoding.encoder().encode(delivery)),
            let stored = try await library.record(.init(kind: "adaptiveplotter.destination.delivery." + delivery.client.uuidString.lowercased(), id: delivery.id)),
            try JSONDecoder().decode(DrawingDestinationResponse.self, from: stored.payload) == response {
            responses.append(response)
            continue
          }
          let published = try await receive(url)
          responses.append(try DrawingDestinationFiles.read(DrawingDestinationResponse.self, from: published))
        } catch { failures.append(url.lastPathComponent + ": " + error.localizedDescription) }
      }
    }
    return .init(responses: responses, failures: failures)
  }

}
/// Client identity and pending delivery are domain records in the client's existing
/// Library. Relaunch republishes the same delivery, and timeout can use request lookup.
@MainActor public final class DrawingDestinationClient {
  private let library: DrawingLibrary
  public let root: URL
  private static let identityID = UUID(uuidString: "c611e5b7-fca9-46f4-91c8-4419155c65c1")!
  private let identityKind = "adaptiveplotter.destination.client"
  private let pendingKind = "adaptiveplotter.destination.pending"
  private struct Identity: Codable { let namespace: UUID }
  private var namespaceTask: Task<UUID, Error>?
  public init(library: DrawingLibrary, root: URL = DrawingDestinationFiles.defaultRoot) { self.library = library; self.root = root }
  public func namespace() async throws -> UUID {
    if let task = namespaceTask { return try await task.value }
    let task = Task { @MainActor in try await self.loadNamespace() }
    namespaceTask = task
    do { return try await task.value } catch { namespaceTask = nil; throw error }
  }
  private func loadNamespace() async throws -> UUID {
    try await library.open()
    if let record = try await library.record(.init(kind: identityKind, id: Self.identityID)) {
      return try JSONDecoder().decode(Identity.self, from: record.payload).namespace
    }
    let identity = Identity(namespace: UUID())
    try await library.commitRecords([.init(kind: identityKind, id: Self.identityID, payload: try DrawingArtifactCoding.encoder().encode(identity))])
    return identity.namespace
  }
  public func enqueue(_ request: DrawingDestinationRequest, engine: UUID? = nil, drawing: DrawingRef? = nil) async throws -> DrawingDestinationDelivery {
    let namespace = try await namespace()
    let id = UUID()
    var carrier: URL?
    if let drawing {
      guard case .prepare(let ref) = request, ref == drawing else { throw DrawingDestinationRefusal.invalidDelivery }
      carrier = root.appendingPathComponent("clients/" + namespace.uuidString.lowercased() + "/artwork/" + id.uuidString.lowercased() + ".zip")
      try FileManager.default.createDirectory(at: carrier!.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      try await library.exportDrawing(drawing, to: carrier!)
    }
    let delivery = DrawingDestinationDelivery(id: id, client: namespace, engine: engine, request: request, authoredCarrier: carrier)
    try await library.commitRecords([.init(kind: pendingKind, id: id,
      payload: try DrawingArtifactCoding.encoder().encode(delivery), drawings: drawing.map { [$0] } ?? [])])
    try publish(delivery)
    return delivery
  }
  public func publish(_ delivery: DrawingDestinationDelivery) throws {
    try DrawingDestinationFiles.publish(delivery,
      to: DrawingDestinationFiles.requestURL(root: root, client: delivery.client, delivery: delivery.id))
  }
  public func pending() async throws -> [DrawingDestinationDelivery] {
    try await library.records(kind: pendingKind).map { try JSONDecoder().decode(DrawingDestinationDelivery.self, from: $0.payload) }
  }
  /// Observe only responses whose engine/client/delivery/digest all match.
  /// Retiring transport work never erases the engine's durable request/job facts.
  public func acknowledge(_ delivery: DrawingDestinationDelivery, engine: UUID) async throws -> DrawingDestinationReply? {
    guard let reply = try response(for: delivery, engine: engine) else { return nil }
    try await library.commitRecords([], removing: [.init(kind: pendingKind, id: delivery.id)])
    let request = DrawingDestinationFiles.requestURL(root: root, client: delivery.client, delivery: delivery.id)
    try? FileManager.default.removeItem(at: request)
    if let carrier = delivery.authoredCarrier { try? FileManager.default.removeItem(at: carrier) }
    return reply
  }
  @discardableResult public func recoverPending() async throws -> [DrawingDestinationReply] {
    var replies: [DrawingDestinationReply] = []
    let deliveries = try await pending()
    let engines = (try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("engines"), includingPropertiesForKeys: nil)) ?? []
    for delivery in deliveries {
      var observed = false
      for directory in engines {
        guard let engine = UUID(uuidString: directory.lastPathComponent) else { continue }
        if let reply = try await acknowledge(delivery, engine: engine) { replies.append(reply); observed = true; break }
      }
      if !observed {
        if case .prepare(let ref) = delivery.request, let carrier = delivery.authoredCarrier,
          !FileManager.default.fileExists(atPath: carrier.path) {
          try FileManager.default.createDirectory(at: carrier.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
          try await library.exportDrawing(ref, to: carrier)
        }
        try publish(delivery)
      }
    }
    return replies
  }
  public func response(for delivery: DrawingDestinationDelivery, engine: UUID) throws -> DrawingDestinationReply? {
    let url = DrawingDestinationFiles.responseURL(root: root, engine: engine, client: delivery.client, delivery: delivery.id)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let response = try DrawingDestinationFiles.read(DrawingDestinationResponse.self, from: url)
    guard response.delivery == delivery.id, response.client == delivery.client, response.engine == engine,
      response.digest == .hash(try DrawingArtifactCoding.encoder().encode(delivery)) else { throw DrawingDestinationRefusal.invalidDelivery }
    return response.reply
  }
}
