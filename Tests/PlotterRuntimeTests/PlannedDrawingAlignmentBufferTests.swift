import Foundation
import PlotterModel
import Testing
@testable import PlotterRuntime

@Suite("Planned alignment immutable-buffer parity")
struct PlannedDrawingAlignmentBufferTests {
  @Test("row-buffer evaluation preserves exact scalar residuals, padding, edges and component formats",
    arguments: [FramePixelFormat.gray8, .rgba8, .bgra8])
  func rowBufferMatchesScalarReference(_ format: FramePixelFormat) async throws {
    let width = 71, height = 53, rowBytes = width * format.bytesPerPixel + 13
    let byteCount: Int = rowBytes * height
    var firstBytes = [UInt8](repeating: 0, count: byteCount)
    var secondBytes = [UInt8](repeating: 0, count: byteCount)
    for index in 0..<byteCount {
      let row: Int = index / rowBytes
      let first: Int = (index * 37 + row * 19) % 251
      let second: Int = (index * 23 + row * 43) % 253
      firstBytes[index] = UInt8(first)
      secondBytes[index] = UInt8(second)
    }
    let configuration = CameraConfigurationID()
    let first = try StampedFrame(sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: configuration, width: width, height: height, rowBytes: rowBytes,
      pixelFormat: format, bytes: OwnedFrameBytes(firstBytes))
    let second = try StampedFrame(sequence: 2, captureNanoseconds: 2,
      cameraConfigurationID: configuration, width: width, height: height, rowBytes: rowBytes,
      pixelFormat: format, bytes: OwnedFrameBytes(secondBytes))
    let exclusion = PixelRect(x: 17, y: 11, width: 23, height: 19)
    for stride in [1, 2, 3] {
      for (x, y) in [(-8, 5), (0, 0), (7, -8)] {
        let expected = VisionWorker.backgroundMeanAbsoluteDifference(first, second,
          excluding: exclusion, observationShiftX: x, observationShiftY: y, sampleStride: stride)
        let actual = try await VisionWorker.cancellableBackgroundMeanAbsoluteDifference(first, second,
          excluding: exclusion, observationShiftX: x, observationShiftY: y, sampleStride: stride,
          evaluatedPixelBase: 0, coarseCandidateCount: 0, verifiedCandidateCount: 0,
          baseComputation: .zero, cancellationBudget: .init(), checkpointHandler: nil)
        #expect(actual.residual.meanAbsoluteDifference == expected.meanAbsoluteDifference)
        #expect(actual.residual.pixelCount == expected.pixelCount)
      }
    }
    #expect(first.bytes.data == Data(firstBytes))
    #expect(second.bytes.data == Data(secondBytes))
  }

  @Test("wide rows retain exact byte sums beyond one Float reduction's integer range")
  func wideRowsUseExactChunks() async throws {
    let width = 70_001, height = 3, rowBytes = width * 4 + 11
    let configuration = CameraConfigurationID()
    let baseline = try StampedFrame(sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: configuration, width: width, height: height, rowBytes: rowBytes,
      pixelFormat: .bgra8, bytes: OwnedFrameBytes([UInt8](repeating: 0, count: rowBytes * height)))
    var bytes = [UInt8](repeating: 255, count: rowBytes * height)
    // An odd perturbation would be lost if a >2^24 per-channel sum were
    // accumulated as a single Float instead of exact bounded chunks.
    bytes[17 * 4 + 2] = 254
    let observation = try StampedFrame(sequence: 2, captureNanoseconds: 2,
      cameraConfigurationID: configuration, width: width, height: height, rowBytes: rowBytes,
      pixelFormat: .bgra8, bytes: OwnedFrameBytes(bytes))
    let exclusion = PixelRect(x: 20_003, y: 1, width: 103, height: 1)
    for sampleStride in [1, 2, 3] {
      let expected = VisionWorker.backgroundMeanAbsoluteDifference(baseline, observation,
        excluding: exclusion, observationShiftX: 0, observationShiftY: 0, sampleStride: sampleStride)
      let actual = try await VisionWorker.cancellableBackgroundMeanAbsoluteDifference(baseline, observation,
        excluding: exclusion, observationShiftX: 0, observationShiftY: 0, sampleStride: sampleStride,
        evaluatedPixelBase: 0, coarseCandidateCount: 0, verifiedCandidateCount: 0,
        baseComputation: .zero, cancellationBudget: .init(), checkpointHandler: nil)
      #expect(actual.residual.meanAbsoluteDifference == expected.meanAbsoluteDifference)
      #expect(actual.residual.pixelCount == expected.pixelCount)
    }
  }

  @Test("native scoring retains a textured BGRA shift at the production search radius with masked ink")
  func texturedColorShiftWithExclusion() async throws {
    let width = 97, height = 65, rowBytes = width * 4 + 7
    let shiftX = 8, shiftY = -7
    let exclusion = PixelRect(x: 30, y: 20, width: 17, height: 19)
    var firstBytes = [UInt8](repeating: 211, count: rowBytes * height)
    var secondBytes = [UInt8](repeating: 197, count: rowBytes * height)
    for y in 0..<height {
      for x in 0..<width {
        for component in 0..<4 {
          let value: Int = (x * x * 13 + y * y * 19 + x * y * 7 + component * 53) % 251
          firstBytes[y * rowBytes + x * 4 + component] = UInt8(value)
        }
      }
    }
    for y in 0..<height {
      for x in 0..<width {
        let sourceX = x - shiftX, sourceY = y - shiftY
        guard sourceX >= 0, sourceX < width, sourceY >= 0, sourceY < height else { continue }
        let masked = sourceX >= exclusion.x && sourceX < exclusion.x + exclusion.width
          && sourceY >= exclusion.y && sourceY < exclusion.y + exclusion.height
        for component in 0..<4 {
          secondBytes[y * rowBytes + x * 4 + component] = masked
            ? 0 : firstBytes[sourceY * rowBytes + sourceX * 4 + component]
        }
      }
    }
    let configuration = CameraConfigurationID()
    let baseline = try StampedFrame(sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: configuration, width: width, height: height, rowBytes: rowBytes,
      pixelFormat: .bgra8, bytes: OwnedFrameBytes(firstBytes))
    let observation = try StampedFrame(sequence: 2, captureNanoseconds: 2,
      cameraConfigurationID: configuration, width: width, height: height, rowBytes: rowBytes,
      pixelFormat: .bgra8, bytes: OwnedFrameBytes(secondBytes))
    let actual = try await VisionWorker.boundedSubsampledIntegerAlignment(baseline, observation,
      excluding: exclusion, searchRadius: 8, baseComputation: .zero, checkpointHandler: nil)
    #expect(actual.alignment.shiftX == shiftX)
    #expect(actual.alignment.shiftY == shiftY)
    #expect(actual.alignment.backgroundMeanAbsoluteDifference == 0)
    #expect(actual.coarseCandidateCount == 289)
    #expect(actual.verifiedCandidateCount == 3)
    #expect(actual.maximumEvaluationCountBetweenCancellationChecks <= width)
  }
}
