import Foundation
import PortraitCore
import Testing

@Suite("DX07 exact image encoding admission")
struct DrawingLibraryPhotoEncodingTests {
  @Test("Encoded container admission stays conservative and explicit bounded pixel decoding is separate", arguments: DrawingLibraryPhotoFixture.Encoding.allCases)
  func encodingProof(encoding: DrawingLibraryPhotoFixture.Encoding) throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = try DrawingLibraryPhotoFixture(encoding: encoding)
    let source = root.appendingPathComponent("source")
    try DrawingLibraryPhotoFixture.write(fixture.packagePayload(), to: source)
    let stage = root.appendingPathComponent("stage")
    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
    let staged = try DrawingExchangeCarrier.stageDirectory(source, stagingParent: stage)
    let admitted = try ExchangeAdmission.validate(staged)
    let index = try #require(admitted.index.known)
    let descriptors = Dictionary(index.assets.map { ($0.asset.object, $0) }, uniquingKeysWith: { $1 })
    let photo = try DrawingImageAdmission.photo(fixture.photo.reference, files: admitted.files, assetDescriptors: descriptors)
    let input = try DrawingImageAdmission.input(fixture.input.reference, files: admitted.files, assetDescriptors: descriptors)
    #expect(photo.originalJSON == fixture.photo.record.originalJSON)
    #expect(input.originalJSON == fixture.input.record.originalJSON)
    #expect(input.photo == photo.reference && photo.width == 2 && photo.height == 2)
    #expect(photo.supportedSemantics == (encoding == .raw))
    #expect(input.supportedSemantics == (encoding == .raw))
    let exactPhoto = try DrawingImageRecords.admitPhoto(photo.reference, files: admitted.files)
    let exactInput = try DrawingImageRecords.admitInput(input.reference, files: admitted.files)
    #expect(exactPhoto.record.originalJSON == photo.originalJSON)
    #expect(exactInput.record.originalJSON == input.originalJSON)
    #expect(exactPhoto.record.supportedSemantics == photo.supportedSemantics)
    #expect(exactInput.record.supportedSemantics == input.supportedSemantics)
    #expect(admitted.statistics.imageDecodeCount == 0)
    if encoding != .raw {
      let descriptor = try #require(descriptors[photo.original.object])
      let decoded = try ExchangeEncodedImageProof.decode(descriptor, files: admitted.files)
      #expect(decoded.width == 2 && decoded.height == 2)
      #expect(decoded.pixels.count == decoded.rowStride * decoded.height)
      #expect(admitted.statistics.imageDecodeCount == 1)
      // Decoding does not rewrite the immutable record's admission declaration.
      #expect(!photo.supportedSemantics)
    }
    for asset in fixture.input.assets {
      #expect(try admitted.files.record(asset.descriptor.asset.object) == asset.bytes)
    }
  }
}
