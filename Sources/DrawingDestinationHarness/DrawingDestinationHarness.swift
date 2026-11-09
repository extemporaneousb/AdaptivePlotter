import Foundation
import Darwin
import DrawingLibrary
import PortraitCore
import PortraitLibrary
import PlotterModel

/// Disposable helper process for exercising the real service/file composition.
/// No app lifecycle, production store, controller or issuance owner is constructed.
@MainActor private final class HarnessReplyBoundary: DrawingDestination {
  let service: DrawingDestinationService
  let exits: Bool
  init(_ service: DrawingDestinationService, exits: Bool) { self.service = service; self.exits = exits }
  func handle(_ request: DrawingDestinationRequest) async throws -> DrawingDestinationReply {
    let reply = try await service.handle(request)
    if exits, case .submit = request { Darwin.exit(76) }
    return reply
  }
}
@main struct DrawingDestinationHarness {
  @MainActor static func main() async throws {
    let args = CommandLine.arguments
    guard args.count == 4 || args.count == 5 else { throw DrawingDestinationRefusal.invalidDelivery }
    let root = URL(fileURLWithPath: args[1], isDirectory: true).standardizedFileURL
    let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath()
    guard root.resolvingSymlinksInPath().pathComponents.starts(with: temporary.pathComponents) else { throw DrawingDestinationRefusal.invalidDelivery }
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("engine"), payloadValidators: DrawingDestinationResult.payloadValidators)
    let transport = root.appendingPathComponent("transport")
    let planURL = URL(fileURLWithPath: args[2])
    let plan = try JSONDecoder().decode(ExecutionPlanRevision.self, from: Data(contentsOf: planURL))
    let options = DrawingDestinationOptions(drawBorder: false, sheetPlacementIsCurrent: false,
      paperCoverageIsCurrent: false, readiness: "non-device-harness", applicability: .hash(Data("disposable".utf8)))
    let service = DrawingDestinationService(library: library, returnDirectory: root.appendingPathComponent("results"),
      prepare: { ref, engine, _ in
        let drawing = try await library.drawing(ref)
        if args.last == "--exit-after-closure" { Darwin.exit(75) }
        guard drawing.program.contentHash == plan.sourceProgramContentHash else { return nil }
        return try .init(drawing: ref, destination: engine, draftRevision: 1, plan: plan, options: options)
      }, current: { $0 })
    if args.last == "--exit-before-result-publication" {
      DrawingDestinationArtifactObservation.shared.install { _, boundary in
        if boundary == .beforePublication { Darwin.exit(77) }
      }
    }
    let server = DrawingDestinationFileServer(service: HarnessReplyBoundary(service, exits: args.last == "--exit-after-decision"), library: library, root: transport)
    let response = try await server.receive(URL(fileURLWithPath: args[3]))
    print(response.path)
    await library.closeLibrary()
  }
}
