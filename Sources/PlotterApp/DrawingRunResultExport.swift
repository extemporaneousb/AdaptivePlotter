import Foundation
import PortraitCore
import PortraitLibrary
import Darwin

/// A verified, inert export of an existing job. This adapter neither mounts a
/// second engine archive nor obtains any dispatch, cancellation or retry port.
struct DrawingRunResultExport: Sendable {
  let binding: DrawingJobIssuance
  private let files: VerifiedExchangeFiles
  private let temporary: URL

  enum Failure: LocalizedError {
    case differentDrawing, unavailable(DrawingDestinationRefusal), unexpectedReply, mismatchedResult
    var errorDescription: String? {
      switch self {
      case .differentDrawing: "Run result export is unavailable: this run is not bound to the exact selected Drawing."
      case .unavailable(let reason): "Run result export is unavailable (\(reason.rawValue)). This export response does not change the job or its raw ink evidence."
      case .unexpectedReply: "Run result export did not return a result carrier. The job and its raw evidence are unchanged."
      case .mismatchedResult: "Run result export could not verify the original job, request and Drawing binding."
      }
    }
  }

  @MainActor static func prepare(binding: DrawingJobIssuance, drawing: DrawingRef,
    destination: any DrawingDestination) async throws -> Self {
    guard binding.drawing == drawing else { throw Failure.differentDrawing }
    // Capture the original identity before entering the existing service. There
    // is no Prepare, Submit, refreshed request, or new RunID on this path.
    let reply = try await destination.handle(.exportResult(binding.job))
    let source: URL
    switch reply {
    case .result(let url): source = url
    case .refused(let reason): throw Failure.unavailable(reason)
    default: throw Failure.unexpectedReply
    }
    return try await Task.detached(priority: .utility) {
      let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-run-export-" + UUID().uuidString)
      try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      do {
        let staged = try DrawingExchangeCarrier.stageZIP(source, stagingParent: temporary)
        let admitted = try ExchangeAdmission.validate(staged, payloadValidators: DrawingDestinationResult.payloadValidators)
        guard let index = admitted.index.known, index.kind == "result", index.roots.contains(drawing),
          let reference = index.jobs.first(where: { $0.handle == binding.job }),
          let receipt = admitted.receipts[reference], receipt.drawing == drawing,
          receipt.client.namespace == binding.key.namespace, receipt.client.request == binding.key.request,
          receipt.client.requestDigest == binding.requestDigest, receipt.issuance == binding.issuance,
          receipt.preparedPlan == binding.preparedPlan, receipt.requestedMediumOptions == binding.options else {
          throw Failure.mismatchedResult
        }
        return Self(binding: binding, files: admitted.files, temporary: temporary)
      } catch {
        try? FileManager.default.removeItem(at: temporary)
        throw error
      }
    }.value
  }

  func save(to destination: URL, cancelled: @escaping @Sendable () -> Bool = { false }) async throws {
    let files = files
    try await Task.detached(priority: .utility) {
      let parent = destination.deletingLastPathComponent()
      let staged = parent.appendingPathComponent(".drawing-run-result-" + UUID().uuidString + ".zip")
      defer { try? FileManager.default.removeItem(at: staged) }
      try DrawingExchangeCarrier.preserveZIP(files, to: staged, cancelled: cancelled)
      if cancelled() { throw CancellationError() }
      // Same-directory, exclusive publication leaves an existing destination
      // unchanged and never exposes a partial archive under the chosen name.
      guard renameatx_np(AT_FDCWD, staged.path, AT_FDCWD, destination.path, UInt32(RENAME_EXCL)) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
    }.value
  }

  func discard() { try? FileManager.default.removeItem(at: temporary) }
}
