import Foundation
import AppKit
import SwiftUI
import PortraitStudioUI
import Darwin
@testable import DrawingLibrary
import PortraitCore
import PortraitLibrary
import PlotterModel
import Testing
@testable import PortraitStudio

@MainActor private final class DestinationPreparationGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private var entered = false
  private var released = false
  func wait() async {
    entered = true
    if !released { await withCheckedContinuation { continuation = $0 } }
  }
  func waitUntilEntered() async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !entered, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    try #require(entered, "Preparation did not enter within five seconds")
  }
  func release() { released = true; let waiting = continuation; continuation = nil; waiting?.resume() }
}
@MainActor final class DestinationFixture {
  let root: URL
  let library: DrawingLibrary
  let reference: DrawingRef
  let plan: ExecutionPlanRevision
  var live = true
  let options = DrawingDestinationOptions(drawBorder: false, sheetPlacementIsCurrent: false,
    paperCoverageIsCurrent: false, readiness: "fixture-no-device", applicability: .hash(Data("fixture-applicability".utf8)))
  init(photo: Bool = false, parent: Bool = false) async throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("dx12-destination-" + UUID().uuidString)
    library = DrawingLibrary(directoryURL: root.appendingPathComponent("library"), payloadValidators: DrawingDestinationResult.payloadValidators)
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID())
    let program = try DrawingProgramCatalog.program(for: .metricSquare40, style: style)
    var input: SourceLink<ImageInputRef> = .none
    if photo {
      let pixels = try DrawingImageAsset.gray8(Data([0, 64, 128, 255]), width: 2, height: 2)
      let source = try DrawingImageRecords.photo(identity: .init(issuer: UUID()), original: pixels, width: 2, height: 2,
        acquired: .unknown(provenance: "synthetic"), imported: .unknown(provenance: "synthetic"), captureFactsJSON: Data("{}".utf8))
      let prepared = try DrawingImageRecords.input(identity: .init(issuer: UUID()), photo: source, raster: pixels,
        width: 2, height: 2, orientation: "up", sourceToInput: ExchangeTransform([1,0,0,0,1,0,0,0,1]),
        inputToField: ExchangeTransform([1,0,0,0,1,0,0,0,1]), mask: .none, operations: [DrawingImageOperation(kind: "identity", parametersJSON: Data("{}".utf8))],
        preparation: DrawingProducerReceipt(id: "example.destination-input", version: "1", recordJSON: Data("{}".utf8)))
      try await library.commitRecords([], closure: .init(input: prepared))
      input = .present(prepared.reference)
    }
    let drawing = try Drawing(program: program, input: input, parent: .none,
      producer: DrawingProducerReceipt(id: "example.destination", version: "1", recordJSON: Data("{}".utf8)), units: DrawingUnits())
    let retained = try await library.retain(drawing, reason: "fixture").reference
    if parent {
      let child = try Drawing(program: program, input: input, parent: .present(retained),
        producer: DrawingProducerReceipt(id: "example.destination-child", version: "1", recordJSON: Data("{}".utf8)), units: DrawingUnits())
      reference = try await library.retain(child, reason: "fixture-child").reference
    } else { reference = retained }
    let placement = try DrawingPlacement(fieldAnchor: Point2<FieldSpace>(x: 20, y: 20),
      machineAnchor: Point2<MachineSpace>(x: 100, y: 100), uniformScale: 1, rotationRadians: 0)
    let provenance = try DrawingPlanningProvenance(modelRevisionID: DrawingModelRevisionID(),
      modelContentHash: Digest(bytes: Array(repeating: 0x11, count: 32)),
      registrationRevisionID: DrawingRegistrationRevisionID(), registrationContentHash: Digest(bytes: Array(repeating: 0x22, count: 32)))
    plan = try DrawingPlanner.plan(program: program, placement: placement,
      drawableRegion: DrawableMachineRegion(bounds: AxisAlignedBounds<MachineSpace>(minX: 0, minY: 0, maxX: 200, maxY: 200)), provenance: provenance)
  }
  func service(library supplied: DrawingLibrary? = nil, returns: URL? = nil) -> DrawingDestinationService {
    DrawingDestinationService(library: supplied ?? library, returnDirectory: returns ?? root.appendingPathComponent("results"),
      prepare: { ref, engine, _ in .planned(try .init(drawing: ref, destination: engine, draftRevision: 1, plan: self.plan, options: self.options)) },
      current: { self.live ? $0 : nil })
  }
  func ticket(_ service: DrawingDestinationService) async throws -> DrawingPreparedTicket {
    guard case .prepared(let ticket) = try await service.handle(.prepare(reference)) else { throw DrawingDestinationRefusal.preparationUnavailable }
    return ticket
  }
  func cleanup() async { await library.closeLibrary(); try? FileManager.default.removeItem(at: root) }
}

@Suite("DX12 shared destination service", .serialized)
@MainActor struct DrawingDestinationTests {
  @Test("Failed Prepare without a real plan stays jobless")
  func failedPrepare() async throws {
    let fixture = try await DestinationFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
    let service = DrawingDestinationService(library: fixture.library, returnDirectory: fixture.root.appendingPathComponent("results"),
      prepare: { _, _, _ in nil }, current: { _ in nil })
    #expect(try await service.handle(.prepare(fixture.reference)) == .refused(.preparationUnavailable))
    #expect(try await fixture.library.records(kind: "adaptiveplotter.destination.job").isEmpty)
    #expect(try await fixture.library.records(kind: "adaptiveplotter.destination.prepared").isEmpty)
    await fixture.library.closeLibrary()
  }
  @Test("Concurrent duplicates, namespaces, changed ticket, stale lookup and metadata-only restart")
  func deduplication() async throws {
    let fixture = try await DestinationFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
    let service = fixture.service(), ticket = try await fixture.ticket(service)
    let key = DrawingRequestKey(namespace: UUID())
    async let a = service.handle(.submit(key, ticket))
    async let b = service.handle(.submit(key, ticket))
    let replies = try await (a, b)
    #expect(replies.0 == replies.1)
    guard case .decision(let first) = replies.0 else { Issue.record("Missing refusal decision"); return }
    #expect(first.phase == .refused && first.reason == .issuanceSeamUnavailable)
    #expect(try ExchangeJobReceipt(originalJSON: first.receipt).issuance == nil)
    fixture.live = false
    #expect(try await service.handle(.submit(key, ticket)) == replies.0)
    #expect(try await service.handle(.status(.request(key))) == replies.0)
    let changed = DrawingPreparedTicket(facts: ticket.facts)
    #expect(try await service.handle(.submit(key, changed)) == .refused(.requestConflict))
    let originalJSON = try #require(JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(ticket)) as? [String: Any])
    let originalFacts = try #require(originalJSON["facts"] as? [String: Any])
    for field in ["drawing", "destination", "plan", "options"] {
      var json = originalJSON, facts = originalFacts
      if field == "destination" { facts[field] = UUID().uuidString.lowercased() }
      else {
        var value = try #require(facts[field] as? [String: Any])
        value[field == "drawing" ? "digest" : "object"] = String(repeating: "f", count: 64)
        facts[field] = value
      }
      json["facts"] = facts
      let tampered = try JSONDecoder().decode(DrawingPreparedTicket.self, from: JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]))
      #expect(tampered.id == ticket.id)
      #expect(try await service.handle(.submit(key, tampered)) == .refused(.requestConflict), "Changed \(field) must conflict under the original key/ticket identities")
    }
    let staleKey = DrawingRequestKey(namespace: key.namespace)
    #expect(try await service.handle(.submit(staleKey, ticket)) == .refused(.stalePreview))
    #expect(try await service.handle(.status(.request(staleKey))) == .refused(.stalePreview))
    #expect(try await service.handle(.submit(staleKey, changed)) == .refused(.requestConflict))
    fixture.live = true
    let other = DrawingRequestKey(namespace: UUID(), request: key.request)
    guard case .decision(let separate) = try await service.handle(.submit(other, ticket)) else { Issue.record("Namespace collided"); return }
    #expect(separate.job != first.job)
    #expect(try await service.handle(.cancel(.job(first.job.handle))) == .cancellation(acknowledged: false, settled: true))
    await fixture.library.closeLibrary()
    let reopened = DrawingLibrary(directoryURL: fixture.root.appendingPathComponent("library"))
    let restarted = fixture.service(library: reopened)
    _ = try await restarted.handle(.describe)
    let beforeStatus = DrawingLibraryDiagnostics.shared.snapshot()
    #expect(try await restarted.handle(.status(.job(first.job.handle))) == replies.0)
    let afterStatus = DrawingLibraryDiagnostics.shared.snapshot()
    for counter in ["storageObjectReads", "storageFileVerifications", "storageStreamHashBytes"] {
      #expect(afterStatus[counter, default: 0] == beforeStatus[counter, default: 0], "Status unexpectedly loaded artwork at \(counter)")
    }
    #expect(try await restarted.handle(.submit(key, ticket)) == replies.0)
    let rows = try await reopened.records(kind: "adaptiveplotter.destination.job")
    #expect(rows.allSatisfy { $0.payload.count < 16_384 && !String(decoding: $0.payload, as: UTF8.self).contains("\"strokes\"") })
    await reopened.closeLibrary()
  }
  @Test("Engine-owned source-free and Photo refusal export closes offline with zero runs and exact bytes", arguments: [false, true])
  func refusalClosure(photo: Bool) async throws {
    let fixture = try await DestinationFixture(photo: photo, parent: true); defer { try? FileManager.default.removeItem(at: fixture.root) }
    let service = fixture.service(), ticket = try await fixture.ticket(service)
    let before = fixture.root.appendingPathComponent("authored")
    try await fixture.library.exportDrawing(fixture.reference, to: before)
    let stagedBefore = try DrawingExchangeCarrier.stageDirectory(before, stagingParent: fixture.root)
    guard case .decision(let decision) = try await service.handle(.submit(.init(namespace: UUID()), ticket)),
      case .result(let url) = try await service.handle(.exportResult(decision.job.handle)) else { Issue.record("Missing result"); return }
    if let path = ProcessInfo.processInfo.environment["DRAWING_DESTINATION_EVIDENCE_DIRECTORY"] {
      let evidence = URL(fileURLWithPath: path, isDirectory: true)
      try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
      let target = evidence.appendingPathComponent(photo ? "photo-refusal.zip" : "source-free-refusal.zip")
      try? FileManager.default.removeItem(at: target)
      try FileManager.default.copyItem(at: url, to: target)
    }
    let staged = try DrawingExchangeCarrier.stageZIP(url, stagingParent: fixture.root)
    let admitted = try ExchangeAdmission.validate(staged, payloadValidators: DrawingDestinationResult.payloadValidators)
    #expect(admitted.index.known?.attempts.isEmpty == true)
    #expect(admitted.receipts[decision.job]?.disposition == "refused")
    #expect(admitted.index.known?.includedAsOf == admitted.receipts[decision.job]?.issuedAt.wallTime)
    let rewrittenControls: Set<String> = ["data/exchange.json", "manifest-sha256.txt", "tagmanifest-sha256.txt"]
    for entry in stagedBefore.files.entries.values where !rewrittenControls.contains(entry.path) {
      #expect(try staged.files.record(at: entry.path) == stagedBefore.files.record(at: entry.path), "Exact authored byte change at \(entry.path)")
    }
    let empty = DrawingLibrary(directoryURL: fixture.root.appendingPathComponent("empty"), payloadValidators: DrawingDestinationResult.payloadValidators)
    _ = try await empty.mountResult(from: url)
    let drawing = try await empty.drawing(fixture.reference)
    #expect(drawing.reference == fixture.reference && drawing.units.nominalPenWidthMM == nil)
    #expect(try await empty.results().entries.first?.attemptReferences.isEmpty == true)
    await empty.closeLibrary(); await fixture.library.closeLibrary()
  }
  @Test("File reply publication loss, client restart, engine closure retention and identity bounds")
  func fileTransport() async throws {
    let fixture = try await DestinationFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
    let transport = fixture.root.appendingPathComponent("transport")
    let client = DrawingDestinationClient(library: fixture.library, root: transport)
    let engineLibrary = DrawingLibrary(directoryURL: fixture.root.appendingPathComponent("engine"))
    let service = fixture.service(library: engineLibrary)
    let server = DrawingDestinationFileServer(service: service, library: engineLibrary, root: transport)
    let delivery = try await client.enqueue(.prepare(fixture.reference), drawing: fixture.reference)
    let requestURL = DrawingDestinationFiles.requestURL(root: transport, client: delivery.client, delivery: delivery.id)
    // Client restart before engine installation reconstructs its own carrier
    // from the existing durable Library, preserving the pending delivery identity.
    try FileManager.default.removeItem(at: #require(delivery.authoredCarrier))
    let restartingClient = DrawingDestinationClient(library: fixture.library, root: transport)
    try await restartingClient.recoverPending()
    #expect(FileManager.default.fileExists(atPath: try #require(delivery.authoredCarrier).path))
    async let firstDelivery = server.receive(requestURL)
    async let duplicateDelivery = server.receive(requestURL)
    let received = try await (firstDelivery, duplicateDelivery)
    #expect(received.0 == received.1)
    let replyURL = received.0
    let response = try DrawingDestinationFiles.read(DrawingDestinationResponse.self, from: replyURL)
    guard case .prepared(let ticket) = response.reply else { Issue.record("No ticket"); return }
    try FileManager.default.removeItem(at: replyURL)
    try FileManager.default.removeItem(at: #require(delivery.authoredCarrier))
    // Original pathname is gone; reply recovery uses the durable engine delivery.
    _ = try await server.receive(requestURL)
    #expect(try client.response(for: delivery, engine: response.engine) == .prepared(ticket))
    let reopenedClient = DrawingDestinationClient(library: fixture.library, root: transport)
    #expect(try await reopenedClient.namespace() == delivery.client)
    #expect(try await reopenedClient.pending().contains(delivery))
    let key = DrawingRequestKey(namespace: delivery.client)
    let submit = try await client.enqueue(.submit(key, ticket), engine: response.engine)
    let responseDirectory = DrawingDestinationFiles.responseURL(root: transport, engine: response.engine, client: submit.client, delivery: submit.id).deletingLastPathComponent()
    try FileManager.default.removeItem(at: responseDirectory)
    try Data("blocked response directory".utf8).write(to: responseDirectory)
    let submitURL = DrawingDestinationFiles.requestURL(root: transport, client: submit.client, delivery: submit.id)
    do { _ = try await server.receive(submitURL); Issue.record("Expected interrupted reply publication") } catch {}
    try FileManager.default.removeItem(at: responseDirectory)
    _ = try await server.receive(submitURL)
    let lookup = try await client.enqueue(.status(.request(key)), engine: response.engine)
    let lookupURL = try await server.receive(DrawingDestinationFiles.requestURL(root: transport, client: lookup.client, delivery: lookup.id))
    guard case .decision(let decision) = try DrawingDestinationFiles.read(DrawingDestinationResponse.self, from: lookupURL).reply else { Issue.record("Timeout lookup failed"); return }
    #expect(decision.reason == .issuanceSeamUnavailable)
    let malformed = DrawingDestinationDelivery(id: lookup.id, client: lookup.client, engine: UUID(), request: .describe)
    try DrawingDestinationFiles.publish(malformed, to: requestURL)
    do { _ = try await server.receive(requestURL); Issue.record("Wrong delivery accepted") } catch {}
    try Data(repeating: 32, count: DrawingDestinationFiles.maximumControlBytes + 1).write(to: requestURL)
    do { _ = try await server.receive(requestURL); Issue.record("Oversized request accepted") } catch {}
    await engineLibrary.closeLibrary(); await fixture.library.closeLibrary()
  }
  @Test("Failed result publication retries without creating another job")
  func failedReturn() async throws {
    let fixture = try await DestinationFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
    let blocked = fixture.root.appendingPathComponent("blocked")
    try Data("block directory".utf8).write(to: blocked)
    let service = fixture.service(returns: blocked), ticket = try await fixture.ticket(service)
    let key = DrawingRequestKey(namespace: UUID())
    guard case .decision(let decision) = try await service.handle(.submit(key, ticket)) else { Issue.record("Missing decision"); return }
    do { _ = try await service.handle(.exportResult(decision.job.handle)); Issue.record("Expected publication failure") } catch {}
    try FileManager.default.removeItem(at: blocked)
    guard case .result(let url) = try await service.handle(.exportResult(decision.job.handle)) else { Issue.record("Retry failed"); return }
    let original = try Data(contentsOf: url)
    #expect(try await service.handle(.exportResult(decision.job.handle)) == .result(url))
    #expect(try Data(contentsOf: url) == original)
    try FileManager.default.removeItem(at: url)
    let divergent = Data("divergent existing engine-owned result".utf8)
    try divergent.write(to: url)
    do { _ = try await service.handle(.exportResult(decision.job.handle)); Issue.record("Divergent existing target was accepted") } catch {}
    #expect(try Data(contentsOf: url) == divergent)
    #expect(try await service.handle(.status(.request(key))) == .decision(decision))
    #expect(try await fixture.library.records(kind: "adaptiveplotter.destination.job").count == 1)
    await fixture.library.closeLibrary()
  }
  @Test("Separate helper processes use the actual shared service across closure/decision/reply boundaries", .enabled(if: ProcessInfo.processInfo.environment["DRAWING_DESTINATION_HARNESS"] != nil))
  func separateProcess() async throws {
    guard let executable = ProcessInfo.processInfo.environment["DRAWING_DESTINATION_HARNESS"] else {
      return
    }
    let fixture = try await DestinationFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
    let planURL = fixture.root.appendingPathComponent("plan.json")
    try DrawingArtifactCoding.encoder().encode(fixture.plan).write(to: planURL)
    let client = DrawingDestinationClient(library: fixture.library, root: fixture.root.appendingPathComponent("transport"))
    func invoke(_ delivery: DrawingDestinationDelivery, boundary: String? = nil) async throws -> (Int32, String) {
      let input = DrawingDestinationFiles.requestURL(root: client.root, client: delivery.client, delivery: delivery.id)
      return try await Task.detached { () async throws -> (Int32, String) in
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [fixture.root.path, planURL.path, input.path] + (boundary.map { [$0] } ?? [])
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run()
        defer {
          // This harness owns only this process. Cancellation or a read error
          // must not leave its helper running after the fixture is removed.
          if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
          try? pipe.fileHandleForReading.close()
          try? pipe.fileHandleForWriting.close()
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while process.isRunning, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        if process.isRunning {
          process.terminate()
          let terminationDeadline = ContinuousClock.now.advanced(by: .seconds(2))
          while process.isRunning, ContinuousClock.now < terminationDeadline { try await Task.sleep(for: .milliseconds(10)) }
          if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
            let killDeadline = ContinuousClock.now.advanced(by: .seconds(2))
            while process.isRunning, ContinuousClock.now < killDeadline { try await Task.sleep(for: .milliseconds(10)) }
            if process.isRunning { Issue.record("Owned destination helper did not terminate after SIGKILL: \(process.processIdentifier)") }
          }
          throw DrawingDestinationRefusal.preparationUnavailable
        }
        let bytes = pipe.fileHandleForReading.readDataToEndOfFile()
        // isRunning is already false and stdout reached EOF. Calling
        // waitUntilExit again can wait on a different thread's run loop after
        // the asynchronous polling above; terminationStatus is available now.
        return (process.terminationStatus, String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
      }.value
    }
    func run(_ delivery: DrawingDestinationDelivery) async throws -> DrawingDestinationResponse {
      let result = try await invoke(delivery)
      guard result.0 == 0 else { throw DrawingDestinationRefusal.invalidDelivery }
      return try DrawingDestinationFiles.read(DrawingDestinationResponse.self, from: URL(fileURLWithPath: result.1))
    }
    let opening = try await client.enqueue(.prepare(fixture.reference), drawing: fixture.reference)
    #expect(try await invoke(opening, boundary: "--exit-after-closure").0 == 75)
    try FileManager.default.removeItem(at: #require(opening.authoredCarrier))
    let prepared = try await run(opening)
    guard case .prepared(let ticket) = prepared.reply else { Issue.record("No remote ticket"); return }
    // Lose the response and restart the helper; engine metadata recovers it.
    let responseURL = DrawingDestinationFiles.responseURL(root: client.root, engine: prepared.engine, client: opening.client, delivery: opening.id)
    try FileManager.default.removeItem(at: responseURL)
    #expect(try await run(opening) == prepared)
    let key = DrawingRequestKey(namespace: opening.client)
    let submission = try await client.enqueue(.submit(key, ticket), engine: prepared.engine)
    #expect(try await invoke(submission, boundary: "--exit-after-decision").0 == 76)
    let submitted = try await run(submission)
    guard case .decision(let decision) = submitted.reply else { Issue.record("No remote decision"); return }
    #expect(try await run(submission) == submitted)
    let lookup = try await client.enqueue(.status(.request(key)), engine: prepared.engine)
    #expect(try await run(lookup).reply == .decision(decision))
    let result = try await client.enqueue(.exportResult(decision.job.handle), engine: prepared.engine)
    #expect(try await invoke(result, boundary: "--exit-before-result-publication").0 == 77)
    let finalURL = fixture.root.appendingPathComponent("results/" + decision.job.job.uuidString.lowercased() + ".zip")
    #expect(!FileManager.default.fileExists(atPath: finalURL.path))
    guard case .result(let resultURL) = try await run(result).reply else { Issue.record("No remote result"); return }
    try FileManager.default.removeItem(at: resultURL)
    // A cached return response must repair missing publication, never resubmit.
    #expect(try await run(result).reply == .result(resultURL))
    let repeatedResult = try await client.enqueue(.exportResult(decision.job.handle), engine: prepared.engine)
    #expect(try await run(repeatedResult).reply == .result(resultURL))
    let postReturnLookup = try await client.enqueue(.status(.request(key)), engine: prepared.engine)
    #expect(try await run(postReturnLookup).reply == .decision(decision))
    if let path = ProcessInfo.processInfo.environment["DRAWING_DESTINATION_EVIDENCE_DIRECTORY"] {
      let evidence = URL(fileURLWithPath: path, isDirectory: true)
      try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
      let target = evidence.appendingPathComponent("separate-process-refusal.zip")
      try? FileManager.default.removeItem(at: target)
      try FileManager.default.copyItem(at: resultURL, to: target)
    }
    let empty = DrawingLibrary(directoryURL: fixture.root.appendingPathComponent("offline"), payloadValidators: DrawingDestinationResult.payloadValidators)
    _ = try await empty.mountResult(from: resultURL)
    #expect(try await empty.drawing(fixture.reference).units.nominalPenWidthMM == nil)
    await empty.closeLibrary(); await fixture.library.closeLibrary()
  }

  @Test("Standalone actual handoff queues only Prepare and retires verified pending delivery")
  func standaloneHandoff() async throws {
    let fixture = try await DestinationFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
    let delegate = PortraitStudioApplicationDelegate()
    delegate.library = fixture.library
    delegate.destinationRoot = fixture.root.appendingPathComponent("transport")
    var handedURL: URL?
    delegate.openDestination = { handedURL = $0 }
    let drawing = try await fixture.library.drawing(fixture.reference)
    #expect(await delegate.prepareAtDestination(drawing) == nil)
    let url = try #require(handedURL)
    let delivery = try DrawingDestinationFiles.read(DrawingDestinationDelivery.self, from: url)
    #expect(delivery.request == .prepare(fixture.reference))
    let engineLibrary = DrawingLibrary(directoryURL: fixture.root.appendingPathComponent("engine"))
    let server = DrawingDestinationFileServer(service: fixture.service(library: engineLibrary), library: engineLibrary, root: delegate.destinationRoot)
    _ = try await server.receive(url)
    await delegate.recoverDestinationRequests()
    #expect(!FileManager.default.fileExists(atPath: url.path))
    let client = DrawingDestinationClient(library: fixture.library, root: delegate.destinationRoot)
    #expect(try await client.pending().isEmpty)
    #expect(try await engineLibrary.records(kind: "adaptiveplotter.destination.job").isEmpty)
    handedURL = nil
    #expect(await delegate.prepareAtDestination(drawing, isStillCurrent: { false }) != nil)
    #expect(handedURL == nil)
    #expect(try await client.pending().isEmpty)
    await engineLibrary.closeLibrary(); await fixture.library.closeLibrary()
  }
  @Test("Standalone document open reveals the exact imported Drawing in the existing global Library route", arguments: [0, 1, 2])
  func standaloneDocumentReveal(phase: Int) async throws {
    let fixture = try await DestinationFixture(parent: true); defer { try? FileManager.default.removeItem(at: fixture.root) }
    let document = fixture.root.appendingPathComponent("opened-drawing.zip")
    try await fixture.library.exportDrawing(fixture.reference, to: document)
    let targetRoot = fixture.root.appendingPathComponent("standalone")
    let library = DrawingLibrary(directoryURL: targetRoot)
    let acquisition = PortraitStudioModel(library: library)
    let authoring = FlowAuthoringModel(directory: targetRoot, library: library)
    let delegate = PortraitStudioApplicationDelegate()
    var route = DrawingLibraryRoute()
    route.workspace = .drawingStudio; route.collection = .children
    route.branchParent = fixture.reference
    route.photo = .init(issuer: UUID(), revision: UUID(), digest: .hash(Data("stale Photo route".utf8)))
    route.input = .init(issuer: UUID(), revision: UUID(), digest: .hash(Data("stale input route".utf8)))
    let window = PortraitStudioAuthoringWindow(authoring: authoring, acquisition: acquisition, library: library, delegate: delegate,
      route: Binding(get: { route }, set: { route = $0 }))
    // Exercise both an event before any window owner exists and a completed
    // import whose window reveal callback has not been installed yet.
    if phase == 1 { delegate.library = library; delegate.acquisition = acquisition }
    if phase == 2 { window.installDocumentHandling() }
    delegate.application(NSApplication.shared, open: [document])
    if phase < 2 {
      await delegate.settleDrawingDocuments()
      #expect(route.workspace == .drawingStudio)
      window.installDocumentHandling()
    }
    await delegate.settleDrawingDocuments()
    #expect(route.workspace == .library && route.activeCollection == .drawings)
    #expect(route.drawing == fixture.reference)
    #expect(route.photo == nil && route.input == nil && route.branchParent == nil)
    let opened = try #require(acquisition.sketches.selected)
    let original = try await fixture.library.drawing(fixture.reference)
    #expect(opened.reference == fixture.reference && opened.program == original.program)
    #expect(opened.parent == original.parent && opened.producer.originalJSON == original.producer.originalJSON)
    #expect(delegate.documentError == nil)
    #expect(try await library.records(kind: "adaptiveplotter.destination.job").isEmpty)
    let beforeFailure = route
    delegate.application(NSApplication.shared, open: [fixture.root.appendingPathComponent("missing.zip")])
    await delegate.settleDrawingDocuments()
    #expect(delegate.documentError != nil && route == beforeFailure)
    #expect(acquisition.sketches.selected?.reference == fixture.reference)
    await acquisition.shutdown(); _ = await authoring.shutdown()
    await library.closeLibrary(); await fixture.library.closeLibrary()
  }
  @Test("Closing admission drains an already accepted preparation before borrowed Library shutdown")
  func closeDrain() async throws {
    let fixture = try await DestinationFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
    let gate = DestinationPreparationGate()
    defer { gate.release() }
    let service = DrawingDestinationService(library: fixture.library, returnDirectory: fixture.root.appendingPathComponent("results"),
      prepare: { ref, engine, _ in
        await gate.wait()
        return .planned(try .init(drawing: ref, destination: engine, draftRevision: 1, plan: fixture.plan, options: fixture.options))
      }, current: { $0 })
    let work = Task { try await service.handle(.prepare(fixture.reference)) }
    try await gate.waitUntilEntered()
    let closing = Task { await service.close() }
    await Task.yield()
    gate.release()
    #expect(try await work.value == .refused(.preparationUnavailable))
    await closing.value
    do { _ = try await service.handle(.describe); Issue.record("Closed service admitted work") } catch {}
    let reopened = fixture.service()
    #expect(try await reopened.handle(.describe) != .refused(.preparationUnavailable))
    await fixture.library.closeLibrary()
  }

  @Test("Actual standalone quit joins admitted handoff but suppresses its late opening status")
  func quitSuppressesLateHandoffPresentation() async throws {
    let fixture = try await DestinationFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
    let delegate = PortraitStudioApplicationDelegate(), gate = DestinationPreparationGate()
    delegate.library = fixture.library
    delegate.destinationRoot = fixture.root.appendingPathComponent("quit-handoff")
    delegate.openDestination = { _ in await gate.wait() }
    var replies: [Bool] = [], foregrounds = 0
    delegate.replyToTermination = { _, accepted in replies.append(accepted) }
    delegate.restorePortfolioWindow = { foregrounds += 1 }
    let drawing = try await fixture.library.drawing(fixture.reference)
    let admitted = Task { await delegate.prepareAtDestination(drawing) }
    try await gate.waitUntilEntered()
    delegate.destinationStatus = "Closing handoff fixture"
    delegate.documentError = "Retained error fixture"
    #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
    await Task.yield(); #expect(replies.isEmpty)
    gate.release()
    #expect(await admitted.value == nil)
    try await waitForTermination { !replies.isEmpty }
    #expect(replies == [true] && foregrounds == 0)
    #expect(delegate.destinationStatus == "Closing handoff fixture" && delegate.documentError == "Retained error fixture")
    let reopened = DrawingLibrary(directoryURL: fixture.library.directoryURL)
    let client = DrawingDestinationClient(library: reopened, root: delegate.destinationRoot)
    #expect(try await client.pending().count == 1)
    #expect(try await reopened.drawing(fixture.reference).reference == fixture.reference)
    #expect(try await reopened.records(kind: "adaptiveplotter.destination.job").isEmpty)
    await reopened.closeLibrary()
  }

  @Test("Actual standalone quit retains a committed import without late selection, reveal or foreground")
  func quitSuppressesLateDocumentPresentation() async throws {
    let fixture = try await DestinationFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
    let document = fixture.root.appendingPathComponent("late-document.drawingexchange")
    try await fixture.library.exportDrawing(fixture.reference, to: document)
    let directory = fixture.root.appendingPathComponent("closing-document-library")
    let library = DrawingLibrary(directoryURL: directory)
    // The window's collection borrows the actual importing owner.
    let importedAcquisition = PortraitStudioModel(library: library)
    let delegate = PortraitStudioApplicationDelegate(), gate = StudioDocumentCommitGate()
    var reveals: [DrawingRef] = [], replies: [Bool] = [], foregrounds = 0
    delegate.installDocumentHandling(library: library, acquisition: importedAcquisition, reveal: { reveals.append($0) })
    delegate.replyToTermination = { _, accepted in replies.append(accepted) }
    delegate.restorePortfolioWindow = { foregrounds += 1 }
    try await library.holdStudioPublication(gate, failAfterRelease: false)
    delegate.application(NSApplication.shared, open: [document])
    try await gate.waitUntilEntered()
    delegate.destinationStatus = "Closing import fixture"
    #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
    await Task.yield(); #expect(replies.isEmpty)
    gate.release(); await delegate.settleDrawingDocuments()
    try await waitForTermination { !replies.isEmpty }
    #expect(replies == [true] && reveals.isEmpty && foregrounds == 0)
    #expect(importedAcquisition.sketches.selected == nil)
    #expect(delegate.destinationStatus == "Closing import fixture" && delegate.documentError == nil)
    let reopened = DrawingLibrary(directoryURL: directory)
    #expect(try await reopened.drawing(fixture.reference).reference == fixture.reference)
    await reopened.closeLibrary(); await fixture.library.closeLibrary()
  }

  @Test("A quit canceled by an admitted autosave failure restores standalone Drawing handoff admission")
  func canceledQuitRestoresDrawingAdmission() async throws {
    let fixture = try await DestinationFixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
    let authoring = FlowAuthoringModel(library: fixture.library, purpose: .validationFixture)
    await authoring.open()
    let gate = StudioDocumentCommitGate()
    try await fixture.library.holdStudioPublication(gate, failAfterRelease: true)
    let autosave = Task { await authoring.addPhoto(data: FlowAuthoringFixture.image(7), title: "Quit-cancel fixture") }
    try await gate.waitUntilEntered()
    let delegate = PortraitStudioApplicationDelegate()
    delegate.library = fixture.library; delegate.authoring = authoring
    delegate.destinationRoot = fixture.root.appendingPathComponent("canceled-quit-handoff")
    var replies: [Bool] = [], foregrounds = 0, openings = 0
    delegate.replyToTermination = { _, accepted in replies.append(accepted) }
    delegate.restorePortfolioWindow = { foregrounds += 1 }
    delegate.openDestination = { _ in openings += 1 }
    #expect(!authoring.needsRecovery)
    #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
    gate.release(); await autosave.value
    try await waitForTermination { !replies.isEmpty }
    #expect(replies == [false] && foregrounds == 1 && authoring.needsRecovery)
    await fixture.library.clearStudioPublicationFault()
    await authoring.recoverAutosave()
    #expect(!authoring.needsRecovery)
    let drawing = try await fixture.library.drawing(fixture.reference)
    #expect(await delegate.prepareAtDestination(drawing) == nil)
    #expect(openings == 1 && delegate.destinationStatus?.hasPrefix("Opening the drawing preview") == true)
    _ = await authoring.shutdown(); await fixture.library.closeLibrary()
  }

  private func waitForTermination(_ finished: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !finished(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    try #require(finished(), "The admitted termination did not settle")
  }

}

private final class StudioDocumentCommitGate: @unchecked Sendable {
  private let condition = NSCondition()
  private var entered = false
  private var released = false
  func hold() {
    condition.lock(); entered = true
    let deadline = Date().addingTimeInterval(20)
    while !released { if !condition.wait(until: deadline) { break } }
    condition.unlock()
  }
  private var hasEntered: Bool { condition.lock(); defer { condition.unlock() }; return entered }
  @MainActor func waitUntilEntered() async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !hasEntered, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    try #require(hasEntered, "Library publication did not enter")
  }
  func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
}
private extension DrawingLibrary {
  func holdStudioPublication(_ gate: StudioDocumentCommitGate, failAfterRelease: Bool) throws {
    let catalog = try commonCatalog()
    var armed = true
    catalog.injectFault = { boundary in
      guard armed, boundary == .beforeSQLPublication else { return }
      armed = false; gate.hold()
      if failAfterRelease { throw DrawingLibraryError.unavailable("Injected admitted autosave failure") }
    }
  }
  func clearStudioPublicationFault() { cachedExchangeCatalog?.injectFault = nil }
}
