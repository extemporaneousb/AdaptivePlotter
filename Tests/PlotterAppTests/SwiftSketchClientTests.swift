import Foundation
import Testing
import PortraitCore
import PortraitArtists

/// Process fixtures exercise the contract only; their receipt never proves pretrained inference.
@Suite("SwiftSketch bounded process client", .serialized)
struct SwiftSketchClientTests {
  @Test
  func testOldProofDoesNotAdvertiseAvailableWhenAssetOrSourceIsRemoved() async throws {
    let fixture = try makeFixture(body: "pass\n", timeout: 3)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let client = SwiftSketchClient(configuration: fixture.configuration)
    let initial = await client.availability()
    #expect(initial.available)
    let asset = fixture.root.appendingPathComponent("assets/diffusion")
    try FileManager.default.removeItem(at: asset)
    let missingAsset = await client.availability()
    #expect(!missingAsset.available)
    #expect(missingAsset.reason.contains("diffusion"))
    try Data("fixture".utf8).write(to: asset)
    try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("upstream/SwiftSketch/model/SwiftSketch_model.py"))
    let missingSource = await client.availability()
    #expect(!missingSource.available)
    #expect(missingSource.reason.contains("upstream source"))
  }
  @Test
  func testTimeoutReapsTheWorkerAndRetainsTerminalReceipt() async throws {
    let fixture = try makeFixture(body: "import time\ntime.sleep(5)\n", timeout: 0.2)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let client = SwiftSketchClient(configuration: fixture.configuration)
    let result = try await client.generate(request: SwiftSketchRequest(inputPNG: Data("fixture".utf8)))
    #expect(result.status == .timedOut)
    #expect(result.reason != nil)
    #expect(FileManager.default.fileExists(atPath: result.attemptDirectory.appendingPathComponent("client-terminal.json").path))
  }

  @Test
  func testCancellationSuppressesLateWorkerResult() async throws {
    let fixture = try makeFixture(body: "import time\ntime.sleep(5)\n", timeout: 3)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let client = SwiftSketchClient(configuration: fixture.configuration)
    let task = Task { try await client.generate(request: SwiftSketchRequest(inputPNG: Data("fixture".utf8))) }
    try await Task.sleep(for: .milliseconds(100))
    task.cancel()
    let result = try await task.value
    #expect(result.status == .cancelled)
    #expect(result.previewPNG == nil)
  }

  @Test
  func testMismatchedResponseRetainsFailedReceipt() async throws {
    let body = """
    import argparse,json,pathlib,uuid
    p=argparse.ArgumentParser()
    for name in ('request','manifest','output'):p.add_argument('--'+name)
    a=p.parse_args();out=pathlib.Path(a.output);out.mkdir()
    (out/'response.json').write_text(json.dumps({'schema_version':1,'request_id':str(uuid.uuid4()),'status':'succeeded','reason':None,'files':{}}))
    """
    let fixture = try makeFixture(body: body, timeout: 3)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let result = try await SwiftSketchClient(configuration: fixture.configuration).generate(request: SwiftSketchRequest(inputPNG: Data("fixture".utf8)))
    #expect(result.status == .failed)
    #expect(result.reason?.contains("mismatched") == true)
    #expect(FileManager.default.fileExists(atPath: result.attemptDirectory.appendingPathComponent("refused-response.bin").path))
  }

  @Test
  func testTamperedAssetCannotBecomeSuccessfulResult() async throws {
    let body = """
    import argparse,json,pathlib
    p=argparse.ArgumentParser()
    for name in ('request','manifest','output'):p.add_argument('--'+name)
    a=p.parse_args();r=json.loads(pathlib.Path(a.request).read_text());out=pathlib.Path(a.output);out.mkdir()
    (out/'raw-curves.json').write_text('{}')
    (out/'response.json').write_text(json.dumps({'schema_version':1,'request_id':r['request_id'],'status':'succeeded','reason':None,'files':{'raw-curves.json':'0'*64}}))
    """
    let fixture = try makeFixture(body: body, timeout: 3)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let result = try await SwiftSketchClient(configuration: fixture.configuration).generate(request: SwiftSketchRequest(inputPNG: Data("fixture".utf8)))
    #expect(result.status == .failed)
    #expect(result.rawOutputJSON == Data("{}".utf8)) // Refused bytes retained only as failure evidence.
    #expect(result.reason?.contains("hash mismatch") == true)
  }

  private struct Fixture {
    let root: URL
    let configuration: SwiftSketchWorkerConfiguration
  }
  private func makeFixture(body: String, timeout: Double) throws -> Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("swiftsketch-test-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let worker=root.appendingPathComponent("worker.py"), manifest=root.appendingPathComponent("manifest.json")
    let proof=root.appendingPathComponent("fixture-proof.json")
    let script=Data(body.utf8)
    var assets: [String: [String: String]] = [:]
    let assetFolder=root.appendingPathComponent("assets",isDirectory:true)
    try FileManager.default.createDirectory(at: assetFolder,withIntermediateDirectories:true)
    for name in ["diffusion","diffusion_args","refinement","refinement_args","clip"] {
      let path=assetFolder.appendingPathComponent(name),bytes=Data("process-fixture".utf8)
      try bytes.write(to:path)
      assets[name]=["path":path.path,"sha256":DrawingPackageCodec.sha256(bytes)]
    }
    let upstream=root.appendingPathComponent("upstream",isDirectory:true)
    for name in ["SwiftSketch/model/SwiftSketch_model.py","SwiftSketch/utils/model_util.py",
      "SwiftSketch/diffusion/gaussian_diffusion.py","SwiftSketch/CLIP_/clip/model.py",
      "SwiftSketch/CLIP_/clip/clip.py","SwiftSketch/CLIP_/clip/bpe_simple_vocab_16e6.txt.gz"] {
      let path=upstream.appendingPathComponent(name)
      try FileManager.default.createDirectory(at:path.deletingLastPathComponent(),withIntermediateDirectories:true)
      try Data("process-fixture".utf8).write(to:path)
    }
    let metadata=try JSONSerialization.data(withJSONObject:["schema_version":1,
      "upstream_commit":"6f9fa8654711b9a5d3022b08a59835f0dda08f40","upstream_root":upstream.path,"assets":assets])
    try script.write(to: worker); try metadata.write(to: manifest)
    let receipt:[String:Any]=["schema_version":1,"status":"succeeded",
      "adapter_sha256":DrawingPackageCodec.sha256(script),"manifest_sha256":DrawingPackageCodec.sha256(metadata),
      "evidence_kind":"process-fixture-only"]
    try JSONSerialization.data(withJSONObject: receipt).write(to: proof)
    return Fixture(root: root, configuration: SwiftSketchWorkerConfiguration(
      pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"), workerScript: worker,
      modelManifest: manifest, proofReceipt: proof, attemptRoot: root.appendingPathComponent("attempts"), timeoutSeconds: timeout))
  }
}
