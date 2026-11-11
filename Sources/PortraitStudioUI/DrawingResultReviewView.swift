import AppKit
import CoreGraphics
import DrawingLibrary
import Foundation
import ImageIO
import Observation
import PortraitCore
import SwiftUI

/// Presentation of one exact mounted delivery. It has no raw execution port,
/// local no-ink action or authority to issue or retry a job.
package struct DrawingResultInspection: Sendable {
  package struct Job: Sendable, Identifiable {
    package let id: JobReceiptRef
    package let disposition: String
    package let reason: String
    package let request: UUID
  }
  package struct Snapshot: Sendable, Identifiable {
    package let id: SnapshotRef
    package let previous: ExchangeDigest?
    package let environment: String
    package let state: String
    package let dispatch: String
    package let observation: String
    package let sealed: Bool
    package let isSelectedRoot: Bool
    package let frontiers: [String]
    package let declared: [String]
    package let missing: [String]
  }
  package struct Media: Sendable, Identifiable, Equatable {
    package let id: Int
    package let snapshot: SnapshotRef
    package let kind: String
    package let capture: String
    package let descriptor: ExchangeAssetDescriptor
  }
  package struct Annotation: Sendable, Identifiable {
    package let id: AssessmentRef
    package let targets: [String]
    package let reviewer: String
    package let answerType: String
    package let declaredAnswer: String
    package let limitations: [String]
  }
  package let result: DrawingLibraryResultRef
  package let drawing: DrawingRef
  package let includedAsOf: String
  package let jobs: [Job]
  package let snapshots: [Snapshot]
  package let media: [Media]
  package let annotations: [Annotation]
  package let limitations: [String]

  private struct Coverage: Decodable {
    struct Cell: Decodable {
      let kind: String
      let status: String
      let asset: ExchangeAsset?
      let reason: String?
      let count: UInt64?
      let rawFrameID: String?
      let rawCaptureTicks: String?
      let captureClock: String?
    }
    let profile: String
    let requiredFeatures: [String]
    let entries: [Cell]
    let frontiers: [String: Cell]
  }

  package static func read(_ package: ValidatedExchangePackage, result: DrawingLibraryResultRef,
    drawing: DrawingRef) throws -> Self {
    guard let index = package.index.known, index.kind == "result", index.roots.contains(drawing),
      ExchangeDigest.hash(package.index.originalJSON) == result.indexDigest else {
      throw DrawingExchangeError.malformed("Result does not contain the exact selected Drawing")
    }
    var descriptors: [ExchangeDigest: ExchangeAssetDescriptor] = [:]
    for descriptor in index.assets {
      if let prior = descriptors[descriptor.asset.object], prior != descriptor {
        throw DrawingExchangeError.malformed("Returned asset descriptors conflict")
      }
      descriptors[descriptor.asset.object] = descriptor
    }
    let jobs = index.jobs.compactMap { ref -> Job? in
      guard let receipt = package.receipts[ref], receipt.drawing == drawing else { return nil }
      return .init(id: ref, disposition: receipt.disposition, reason: receipt.reason, request: receipt.client.request)
    }
    // Include exact retained predecessors of selected roots. Other runs merely
    // mentioned by annotations never become selected raw evidence here.
    var selected = Set<SnapshotRef>()
    func include(_ ref: SnapshotRef) throws {
      guard let snapshot = package.attempts[ref], snapshot.drawing == drawing,
        selected.insert(ref).inserted else { return }
      if let digest = snapshot.previous {
        try include(SnapshotRef(archive: ref.archive, run: ref.run, sequence: ref.sequence - 1, digest: digest))
      }
    }
    for ref in index.attempts { try include(ref) }
    let ordered = selected.sorted {
      if $0.archive != $1.archive { return $0.archive.uuidString < $1.archive.uuidString }
      if $0.run != $1.run { return $0.run.uuidString < $1.run.uuidString }
      return $0.sequence < $1.sequence
    }
    var media: [Media] = []
    let snapshots = try ordered.compactMap { ref -> Snapshot? in
      guard let snapshot = package.attempts[ref], snapshot.drawing == drawing else { return nil }
      var frontiers: [String] = [], declared: [String] = [], missing: [String] = []
      if package.interpretableAttempts.contains(ref),
        descriptors[snapshot.coverage]?.asset.encoding == "adaptiveplotter.native-coverage/1" {
        let bytes = try package.files.record(snapshot.coverage)
        let coverage = try JSONDecoder().decode(Coverage.self, from: bytes)
        guard coverage.profile == "adaptiveplotter.coverage/1", coverage.requiredFeatures.isEmpty else {
          throw DrawingExchangeError.unsupportedFeature("Returned coverage requires an unsupported interpretation")
        }
        for key in ["planned", "commanded", "controllerCompleted", "inkVerified"] {
          if let cell = coverage.frontiers[key], cell.status == "present", let count = cell.count {
            frontiers.append("\(key): \(count) declared strokes")
          } else {
            frontiers.append("\(key): unavailable — \(coverage.frontiers[key]?.reason ?? "not declared")")
          }
        }
        for cell in coverage.entries {
          let nativeOriginal = ["adaptiveplotter.raw-baseline", "adaptiveplotter.raw-progress", "adaptiveplotter.raw-terminal"].contains(cell.kind)
          if nativeOriginal, cell.status == "present", let asset = cell.asset,
            let descriptor = descriptors[asset.object], descriptor.asset == asset,
            asset.mediaType.hasPrefix("image/") || descriptor.pixelLayout != nil {
            let frame = cell.rawFrameID.map { "Frame \($0)" } ?? "Frame identity unavailable"
            let ticks = cell.rawCaptureTicks.map { "capture ticks \($0)" } ?? "capture ticks unavailable"
            media.append(.init(id: media.count, snapshot: ref, kind: cell.kind,
              capture: frame + " · " + ticks + " · clock " + (cell.captureClock ?? "unavailable"), descriptor: descriptor))
          } else if cell.status != "present" {
            missing.append(cell.kind + ": " + (cell.reason ?? "unavailable"))
          } else if !nativeOriginal {
            declared.append(cell.kind + ": declared present; no original-camera attribution is inferred")
          }
        }
      } else {
        missing.append("This delivery's coverage codec is unavailable; no frontier or photograph interpretation is inferred.")
      }
      return .init(id: ref, previous: snapshot.previous, environment: snapshot.environment,
        state: snapshot.state, dispatch: snapshot.dispatch, observation: snapshot.observation,
        sealed: snapshot.sealed, isSelectedRoot: index.attempts.contains(ref), frontiers: frontiers, declared: declared, missing: missing)
    }
    let annotations = try package.assessments.keys.sorted { $0.digest.description < $1.digest.description }.compactMap { ref -> Annotation? in
      guard let assessment = package.assessments[ref] else { return nil }
      let targets = assessment.targets.compactMap { target -> String? in
        switch target {
        case .drawing(let value) where value == drawing: return "Drawing \(value.issuer)/\(value.revision)/\(value.digest)"
        case .attempt(let value) where selected.contains(value): return "Snapshot \(value.archive)/\(value.run)/\(value.sequence)/\(value.digest)"
        default: return nil
        }
      }
      guard !targets.isEmpty else { return nil }
      let json = try ExchangeJSON.validate(assessment.originalJSON)
      let reviewer = try JSONSerialization.data(withJSONObject: json["reviewer"] ?? [:], options: [.sortedKeys, .fragmentsAllowed])
      let answer = (json["answer"] as? [String: Any])?["value"] ?? NSNull()
      let declared = try JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys, .fragmentsAllowed])
      return .init(id: ref, targets: targets, reviewer: String(decoding: reviewer, as: UTF8.self),
        answerType: assessment.answerType, declaredAnswer: String(decoding: declared, as: UTF8.self),
        limitations: assessment.unsupportedReasons + assessment.requiredFeatures.map { "Annotation required feature: " + $0 })
    }
    return .init(result: result, drawing: drawing, includedAsOf: index.includedAsOf,
      jobs: jobs, snapshots: snapshots, media: media,
      annotations: annotations,
      limitations: package.capabilities.unsupportedReasons)
  }
}

/// SQL summaries load independently of payload inspection. Selection and close
/// generations guard every asynchronous adoption, including original media.
@Observable @MainActor
package final class DrawingResultReviewModel {
  package private(set) var entries: [DrawingLibraryResultEntry] = []
  package private(set) var inspection: DrawingResultInspection?
  package private(set) var image: NSImage?
  package private(set) var imageDetail: String?
  package private(set) var error: String?
  package private(set) var isBusy = false
  package private(set) var isClosed = false
  package var hasMore: Bool { cursor != nil }
  @ObservationIgnored private let library: DrawingLibrary
  @ObservationIgnored private let drawing: DrawingRef
  @ObservationIgnored private let readResult: @Sendable (DrawingLibraryResultRef) async throws -> ValidatedExchangePackage
  @ObservationIgnored private var cursor: DrawingLibraryResultCursor?
  @ObservationIgnored private var generation: UInt64 = 0
  @ObservationIgnored private var selected: DrawingLibraryResultRef?
  @ObservationIgnored private var admitted: ValidatedExchangePackage?
  @ObservationIgnored private let images = FlowPresentationImageCache(maximumEntries: 1, maximumBytes: 32 * 1024 * 1024, maximumInflight: 1)
  private nonisolated static let maximumMediaBytes = 64 * 1024 * 1024

  package init(library: DrawingLibrary, drawing: DrawingRef,
    readResult: (@Sendable (DrawingLibraryResultRef) async throws -> ValidatedExchangePackage)? = nil) {
    self.library = library; self.drawing = drawing
    self.readResult = readResult ?? { try await library.result($0) }
  }
  package func load(more: Bool = false) async {
    guard !isClosed, !isBusy, !more || cursor != nil else { return }
    generation &+= 1; let request = generation
    isBusy = true; defer { if request == generation { isBusy = false } }
    do {
      let page = try await library.results(for: drawing, after: more ? cursor : nil)
      guard !isClosed, request == generation, !Task.isCancelled else { return }
      entries = more ? entries + page.entries : page.entries
      cursor = page.next; error = nil
    } catch { if !isClosed, request == generation { self.error = error.localizedDescription } }
  }
  package func inspect(_ reference: DrawingLibraryResultRef) async {
    guard !isClosed, entries.contains(where: { $0.reference == reference }) else { return }
    generation &+= 1; let request = generation
    selected = reference; admitted = nil; inspection = nil; image = nil; imageDetail = nil
    isBusy = true; defer { if request == generation { isBusy = false } }
    do {
      let package = try await readResult(reference)
      guard !isClosed, request == generation, selected == reference, !Task.isCancelled else { return }
      let drawing = self.drawing
      let value = try await Task.detached(priority: .userInitiated) {
        try DrawingResultInspection.read(package, result: reference, drawing: drawing)
      }.value
      guard !isClosed, request == generation, selected == reference, !Task.isCancelled else { return }
      admitted = package; inspection = value; error = nil
    } catch { if !isClosed, request == generation { self.error = error.localizedDescription } }
  }
  package func showMedia(_ media: DrawingResultInspection.Media) async {
    guard !isClosed, let admitted, let inspection, inspection.media.contains(media) else { return }
    generation &+= 1; let request = generation
    image = nil; imageDetail = nil; isBusy = true
    defer { if request == generation { isBusy = false } }
    do {
      let descriptor = media.descriptor
      guard descriptor.asset.byteLength <= UInt64(Self.maximumMediaBytes) else {
        throw DrawingExchangeError.limit("Original media is retained; this preview supports at most 64 MiB per image")
      }
      let bytes = try await Task.detached(priority: .userInitiated) {
        let bytes = try admitted.files.record(descriptor.asset.object, maximumBytes: Self.maximumMediaBytes)
        try descriptor.asset.validate(bytes, maximumBytes: Self.maximumMediaBytes)
        return try Self.previewBytes(bytes, descriptor: descriptor)
      }.value
      guard !isClosed, request == generation, !Task.isCancelled else { return }
      let key = inspection.result.indexDigest.description + ":" + inspection.result.packageDigest.description + ":" + String(media.id)
      let preview = await images.load(data: bytes, identity: key)
      guard !isClosed, request == generation, !Task.isCancelled else { return }
      guard let preview else { throw DrawingExchangeError.unsupportedFeature("This retained image has no supported preview decoder") }
      image = preview; imageDetail = media.capture + "\nPreview of retained original pixels; not an ink or motion verification."; error = nil
    } catch { if !isClosed, request == generation { self.error = error.localizedDescription } }
  }
  package func close() {
    isClosed = true; generation &+= 1; admitted = nil; inspection = nil
    image = nil; imageDetail = nil; isBusy = false; images.invalidate()
  }
  private nonisolated static func previewBytes(_ bytes: Data, descriptor: ExchangeAssetDescriptor) throws -> Data {
    if descriptor.asset.mediaType == "image/png" || descriptor.asset.mediaType == "image/jpeg" { return bytes }
    guard let layout = descriptor.pixelLayout, layout.supportedSemantics,
      ["linear-gray", "sRGB"].contains(layout.colorInterpretation),
      let provider = CGDataProvider(data: bytes as CFData) else {
      throw DrawingExchangeError.unsupportedFeature("Original pixels are retained, but their declared layout is not supported for preview")
    }
    try layout.validate(bytes)
    let gray = layout.pixelFormat == "gray"
    let space = gray ? CGColorSpace(name: CGColorSpace.linearGray) : CGColorSpace(name: CGColorSpace.sRGB)
    let alpha: CGImageAlphaInfo = layout.pixelFormat == "rgba" ? .last : layout.pixelFormat == "bgra" ? .first : .none
    var bitmap = CGBitmapInfo(rawValue: alpha.rawValue)
    if layout.pixelFormat == "bgra" { bitmap.insert(.byteOrder32Little) }
    else if layout.pixelFormat == "rgba" { bitmap.insert(.byteOrder32Big) }
    guard let space, let image = CGImage(width: layout.width, height: layout.height, bitsPerComponent: 8,
      bitsPerPixel: layout.bytesPerPixel * 8, bytesPerRow: layout.rowStride, space: space,
      bitmapInfo: bitmap, provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
      throw DrawingExchangeError.unsupportedFeature("Original pixels could not be presented")
    }
    let orientations = ["up": 1, "up-mirrored": 2, "down": 3, "down-mirrored": 4, "left-mirrored": 5, "right": 6, "right-mirrored": 7, "left": 8]
    let encoded = NSMutableData()
    guard let output = CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil) else {
      throw DrawingExchangeError.unsupportedFeature("Original pixels could not be presented")
    }
    CGImageDestinationAddImage(output, image, [kCGImagePropertyOrientation: orientations[layout.orientation] ?? 1] as CFDictionary)
    guard CGImageDestinationFinalize(output) else { throw DrawingExchangeError.malformed("Image preview encoding failed") }
    return encoded as Data
  }
}

@MainActor
package struct DrawingResultReviewView: View {
  @State private var model: DrawingResultReviewModel
  private let export: (@MainActor (DrawingLibraryResultRef) async -> Void)?
  package init(library: DrawingLibrary, drawing: DrawingRef,
    export: (@MainActor (DrawingLibraryResultRef) async -> Void)? = nil) {
    _model = State(initialValue: DrawingResultReviewModel(library: library, drawing: drawing))
    self.export = export
  }
  package var body: some View {
    DisclosureGroup("Returned results") {
      VStack(alignment: .leading, spacing: 10) {
        Button("Refresh Results") { Task { await model.load() } }.disabled(model.isBusy)
        if model.entries.isEmpty { Text("No returned result is mounted for this exact Drawing revision.").foregroundStyle(.secondary) }
        ForEach(model.entries) { entry in
          HStack {
            Text("\(entry.includedAsOf) · \(entry.jobReferences.count) jobs · \(entry.attemptReferences.count) run snapshots")
            Button("Inspect") { Task { await model.inspect(entry.reference) } }
              .accessibilityIdentifier("drawing.results.inspect")
            if let export {
              Button("Export Result") { Task { await export(entry.reference) } }
                .accessibilityIdentifier("drawing.results.export")
            }
          }
        }
        if model.hasMore { Button("More Results") { Task { await model.load(more: true) } } }
        if let result = model.inspection {
          Text("Declared return data · read only").font(.headline)
          Text("This delivery cannot release local no-redraw protection or authorize another run.").font(.caption).foregroundStyle(.secondary)
          Text("Drawing \(result.drawing.issuer)/\(result.drawing.revision)\n\(result.drawing.digest)")
          Text("Result \(result.result.indexDigest)\nInventory \(result.result.packageDigest)").font(.caption)
          ForEach(result.jobs) { job in
            Text("Job \(job.id.handle.engine)/\(job.id.handle.job)\nRequest \(job.request) · \(job.disposition): \(job.reason)")
          }
          if result.snapshots.isEmpty { Text("Zero attempt snapshots declared in this delivery.") }
          ForEach(Array(result.snapshots.prefix(100))) { snapshot in
            VStack(alignment: .leading, spacing: 4) {
              Text("Run \(snapshot.id.run) · sequence \(snapshot.id.sequence) · \(snapshot.sealed ? "sealed" : "provisional")").font(.headline)
              Text("\(snapshot.environment) · \(snapshot.state) · dispatch \(snapshot.dispatch) · observation \(snapshot.observation)")
              Text("Snapshot \(snapshot.id.digest)\nPredecessor \(snapshot.previous?.description ?? "none (first snapshot)")").font(.caption)
              Text(snapshot.isSelectedRoot ? "Selected result root" : "Retained predecessor in the exact selected chain").font(.caption)
              ForEach(snapshot.frontiers, id: \.self) { Text($0) }
              ForEach(Array(snapshot.declared.enumerated()), id: \.offset) { Text($0.element).font(.caption).foregroundStyle(.secondary) }
              ForEach(Array(snapshot.missing.enumerated()), id: \.offset) { Text($0.element).font(.caption).foregroundStyle(.secondary) }
            }
          }
          if result.snapshots.count > 100 { Text("Showing the first 100 of \(result.snapshots.count) verified retained snapshots; the complete chain remains exportable.").font(.caption) }
          ForEach(Array(result.annotations.prefix(100))) { annotation in
            VStack(alignment: .leading, spacing: 4) {
              Text("Attributed annotation · \(annotation.answerType)").font(.headline)
              Text("Reviewer \(annotation.reviewer)").font(.caption)
              ForEach(annotation.targets, id: \.self) { Text($0).font(.caption) }
              Text("Declared answer: \(annotation.declaredAnswer)")
              ForEach(annotation.limitations, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
              Text("Annotation testimony does not change raw coverage or authorize retry.").font(.caption).foregroundStyle(.secondary)
            }
          }
          ForEach(Array(result.media.prefix(100))) { media in
            Button("View \(media.kind) · sequence \(media.snapshot.sequence)") { Task { await model.showMedia(media) } }
          }
          if result.media.count > 100 { Text("Showing the first 100 of \(result.media.count) retained media entries; the complete original delivery remains exportable.").font(.caption) }
          ForEach(result.limitations, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
        }
        if let image = model.image { Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 480) }
        if let detail = model.imageDetail { Text(detail).font(.caption).textSelection(.enabled) }
        if let error = model.error { Text(error).foregroundStyle(.red) }
        if model.isBusy { ProgressView().controlSize(.small) }
      }.textSelection(.enabled)
    }.accessibilityIdentifier("drawing.results")
      .task { await model.load() }
      .onDisappear { model.close() }
  }
}
