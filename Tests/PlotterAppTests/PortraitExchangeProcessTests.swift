import Darwin
import Foundation
import MachO
import PortraitCore
@testable import PortraitLibrary
import Testing

@Suite("Drawing Exchange real process recovery", .serialized)
struct PortraitExchangeProcessTests {
  @Test("Direct already-built helper launch selects exactly one helper test and reports its actual loaded image")
  func helperLaunchSmoke() async throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at:root) }
    let child = try DX04Process.start(root:root,mode:"writer")
    defer { DX04Process.stop(child) }
    try await DX04Process.waitExit(child)
    let log = try String(contentsOf:child.log,encoding:.utf8)
    #expect(child.process.terminationStatus == 0)
    let starts = log.split(separator:"\n").filter { $0.contains("◇ Test \"isolated helper\" started.") }
    #expect(starts.count == 1)
    #expect(log.contains("DX04_HELPER_RUNTIME="))
    print("DX04_HELPER_SMOKE_PID=\(child.process.processIdentifier) LOG=\(log)")
  }

  @Test("Independent writer processes contend across aliases, readers and other roots work, SIGKILL releases lease")
  func processWriterOwnership() async throws {
    let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
    let library = root.appendingPathComponent("library")
    let held = try DX04Process.start(root: root, mode: "hold", library: library)
    defer { DX04Process.stop(held) }
    try await DX04Process.waitReady(held)
    let alias = root.appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: library)
    for selected in [library, alias] {
      let probe = try DX04Process.start(root: root, mode: "writer-refused", library: selected)
      try await DX04Process.waitExit(probe)
      #expect(probe.process.terminationStatus == 0)
    }
    for (mode, selected) in [("reader", library), ("writer", root.appendingPathComponent("other"))] {
      let probe = try DX04Process.start(root: root, mode: mode, library: selected)
      try await DX04Process.waitExit(probe)
      #expect(probe.process.terminationStatus == 0)
    }
    DX04Process.stop(held)
    try await DX04Process.waitExit(held)
    let reacquired = try DX04Process.start(root: root, mode: "writer", library: library)
    try await DX04Process.waitExit(reacquired)
    #expect(reacquired.process.terminationStatus == 0)
  }

  @Test("SIGKILL at each object copy/sync/install and journal/SQL/cleanup boundary recovers one exact publication")
  func publicationCrashMatrix() async throws {
    let corpus = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: corpus) }
    let admitted = try DX04Fixture.admitted(parent: corpus)
    let digests = Set(admitted.files.entries.values.map { $0.digest.description }).sorted()
    let eachObject: Set<PortraitExchangeStorageFault.Boundary> = [.beforeBlobCopy,.afterBlobCopy,.beforeBlobFileSync,.afterBlobFileSync,.beforeBlobInstall,.afterBlobInstall,.beforeBlobDirectorySync,.afterBlobDirectorySync]
    let storageCases = PortraitExchangeStorageFault.Boundary.allCases.filter { ![.beforeBackupPublish,.afterBackupPublish].contains($0) }
    var completed: [String] = []
    for boundary in storageCases {
      for path in eachObject.contains(boundary) ? digests : [""] {
        let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
        let child = try DX04Process.start(root: root, mode: "publish", boundary: boundary.rawValue, object: path)
        defer { DX04Process.stop(child) }
        try await DX04Process.waitReady(child)
        DX04Process.stop(child); try await DX04Process.waitExit(child)
        #expect(child.process.terminationReason == .uncaughtSignal && child.process.terminationStatus == SIGKILL)
        try verifyRestart(root: root, admitted: admitted)
        completed.append(boundary.rawValue + ":" + path)
      }
    }
    for boundary in [PortraitExchangeCatalogBoundary.beforeSQLPublication,.beforeSQLCommit,.afterSQLCommit,.afterSQLPublication] {
      let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
      let child = try DX04Process.start(root: root, mode: "publish", boundary: boundary.rawValue)
      defer { DX04Process.stop(child) }
      try await DX04Process.waitReady(child)
      DX04Process.stop(child); try await DX04Process.waitExit(child)
      try verifyRestart(root: root, admitted: admitted)
      completed.append(boundary.rawValue)
    }
    #expect(completed.count == storageCases.count - eachObject.count + eachObject.count * digests.count + 4)
    print("DX04_REAL_PROCESS_PUBLICATION_CRASH_CASES=\(completed.count) DISTINCT_IMMUTABLE_OBJECTS=\(digests.count) ALL_VERIFIED")
  }

  @Test("SIGKILL before/after forensic preservation and atomic restore selection always leaves a selected catalog")
  func restoreCrashMatrix() async throws {
    for boundary in [PortraitExchangeCatalogBoundary.beforeRestorePreservation,.afterRestorePreservation,.beforeRestoreSelection,.afterRestoreSelection] {
      let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at: root) }
      let store = PortraitCandidateStore(directoryURL: root.appendingPathComponent("library"))
      let admitted = try DX04Fixture.admitted(parent: root)
      let ref = PortraitExchangeReference.drawing(try #require(admitted.index.known?.roots.first))
      _ = try await store.publishExchange(admitted, metadata: [.init(reference: ref,title: "Backup",retentionReasons: ["chosen"],tombstoned: true)])
      let generation = try await store.createExchangeMetadataBackup()
      try await store.updateExchangeMetadata(.init(reference: ref,title: "Current",retentionReasons: ["current"],tombstoned: false))
      await store.closeLibrary()
      let child = try DX04Process.start(root: root, mode: "restore", boundary: boundary.rawValue, generation: generation.generationID)
      defer { DX04Process.stop(child) }
      try await DX04Process.waitReady(child)
      DX04Process.stop(child); try await DX04Process.waitExit(child)
      let sql = root.appendingPathComponent("library/library-v1.sqlite")
      #expect(FileManager.default.fileExists(atPath: sql.path))
      let db = try PortraitLibraryDatabase(url: sql)
      let restored = try PortraitExchangeCatalog(database: db)
      let metadata = try restored.metadata(ref)
      let value = try #require(metadata)
      #expect(value.title == (boundary == .afterRestoreSelection ? "Backup" : "Current"))
      try db.integrityCheck()
    }
    print("DX04_REAL_PROCESS_RESTORE_CRASH_CASES=4 ALL_VERIFIED")
  }

  @Test("Fresh-root restore intent marker is durable before selection and interrupted missing SQL never bootstraps empty")
  func freshRootRestoreCrashMatrix() async throws {
    for boundary in [PortraitExchangeCatalogBoundary.beforeRestorePreservation,.beforeRestoreSelection,.afterRestoreSelection] {
      let root = try DX04Fixture.root(); defer { try? FileManager.default.removeItem(at:root) }
      let source = PortraitCandidateStore(directoryURL:root.appendingPathComponent("source"))
      let admitted = try DX04Fixture.admitted(parent:root)
      _ = try await source.publishExchange(admitted)
      let generation = try await source.createExchangeMetadataBackup()
      await source.closeLibrary()
      let library = root.appendingPathComponent("library"), backups = library.appendingPathComponent("metadata-backups")
      try FileManager.default.createDirectory(at:backups,withIntermediateDirectories:true)
      try FileManager.default.copyItem(at:generation.rootURL,to:backups.appendingPathComponent(generation.generationID.uuidString.lowercased()))
      let child = try DX04Process.start(root:root,mode:"restore",boundary:boundary.rawValue,generation:generation.generationID)
      defer { DX04Process.stop(child) }
      try await DX04Process.waitReady(child)
      DX04Process.stop(child); try await DX04Process.waitExit(child)
      #expect(FileManager.default.fileExists(atPath:library.appendingPathComponent("exchange-authority.json").path))
      let sql = library.appendingPathComponent("library-v1.sqlite")
      if boundary != .afterRestoreSelection {
        #expect(!FileManager.default.fileExists(atPath:sql.path))
        #expect(throws:(any Error).self) { _ = try PortraitLibraryDatabase(url:sql) }
        #expect(throws:(any Error).self) { _ = try PortraitCandidateStore(directoryURL:library).loadPhotoPage() }
        try PortraitExchangeCatalog.restore(root:library,generationID:generation.generationID)
      }
      let db = try PortraitLibraryDatabase(url:sql)
      let catalog = try PortraitExchangeCatalog(database:db)
      #expect(try catalog.publish(admitted).wasAlreadyPublished)
    }
    print("DX04_REAL_PROCESS_FRESH_ROOT_RESTORE_CASES=3 ALL_VERIFIED")
  }

  private func verifyRestart(root: URL, admitted: ValidatedExchangePackage) throws {
    let db = try PortraitLibraryDatabase(url: root.appendingPathComponent("library/library-v1.sqlite"))
    let catalog = try PortraitExchangeCatalog(database: db)
    let ref = PortraitExchangeReference.drawing(try #require(admitted.index.known?.roots.first))
    _ = try catalog.publish(admitted, metadata: [.init(reference: ref,title: "Crash title",retentionReasons: ["explicit-save"],tombstoned: true)])
    #expect(try db.scalar("SELECT COUNT(*) FROM dx_transaction") == "1")
    #expect(try catalog.storage.pendingTransactions().isEmpty)
    #expect(ExchangeDigest.hash(try catalog.record(ref)) == ref.digest)
    #expect(try catalog.metadata(ref)?.retentionReasons == ["explicit-save"])
    #expect(try catalog.metadata(ref)?.tombstoned == true)
    #expect(try catalog.publish(admitted).wasAlreadyPublished)
    try db.integrityCheck()
  }
}

/// Spawned directly from the already-built Swift Testing binary. No SwiftPM process,
/// recursive build, production library, app launch or device initialization occurs.
@Suite("Drawing Exchange isolated process helper")
struct PortraitExchangeProcessHelperTests {
  @Test("isolated helper", .enabled(if: ProcessInfo.processInfo.environment["DX04_PROCESS_HELPER"] != nil))
  func helper() throws {
    let env = ProcessInfo.processInfo.environment
    let mode = try #require(env["DX04_PROCESS_HELPER"])
    let root = URL(fileURLWithPath: try #require(env["DX04_PROCESS_ROOT"]))
    let library = URL(fileURLWithPath: try #require(env["DX04_PROCESS_LIBRARY"]))
    let selected = env["DX04_PROCESS_BOUNDARY"] ?? "", object = env["DX04_PROCESS_OBJECT"] ?? ""
    let identity = try DX04Process.identity()
    print("DX04_HELPER_RUNTIME=" + String(decoding:try JSONSerialization.data(withJSONObject:identity,options:[.sortedKeys]),as:UTF8.self))
    func reached() throws {
      let ready = URL(fileURLWithPath: try #require(env["DX04_PROCESS_READY"]))
      var proof = identity
      proof["boundary"] = selected; proof["object"] = object; proof["mode"] = mode
      try JSONSerialization.data(withJSONObject:proof,options:[.sortedKeys]).write(to:ready,options:.atomic)
      let handle = try FileHandle(forWritingTo: ready); try handle.synchronize(); try handle.close()
      while true { pause() }
    }
    if mode == "restore" {
      let generationText = try #require(env["DX04_PROCESS_GENERATION"])
      let generation = try #require(UUID(uuidString:generationText))
      try PortraitExchangeCatalog.restore(root: library, generationID: generation) { if $0.rawValue == selected { try reached() } }
      throw DX04Fixture.Failure.process
    }
    if mode == "writer-refused" {
      do { _ = try PortraitLibraryDatabase(url: library.appendingPathComponent("library-v1.sqlite")); Issue.record("Competing writer unexpectedly opened") }
      catch { return }
      return
    }
    let db = try PortraitLibraryDatabase(url: library.appendingPathComponent("library-v1.sqlite"), readOnly: mode == "reader")
    if mode == "hold" { try reached() }
    if mode == "writer" || mode == "reader" { try db.integrityCheck(); return }
    let catalog = try PortraitExchangeCatalog(database: db) { event in
      if event.boundary.rawValue == selected && (object.isEmpty || object == event.path) { try reached() }
    }
    catalog.injectFault = { if $0.rawValue == selected { try reached() } }
    let admitted = try DX04Fixture.admitted(parent: root)
    let ref = PortraitExchangeReference.drawing(try #require(admitted.index.known?.roots.first))
    _ = try catalog.publish(admitted, metadata: [.init(reference: ref,title: "Crash title",retentionReasons: ["explicit-save"],tombstoned: true)])
    throw DX04Fixture.Failure.process // Targeted boundary must be reached before normal completion.
  }
}

private enum DX04Process {
  struct Child { let process: Process; let ready: URL; let log: URL; let expectedImage: String }
  static func identity() throws -> [String:Any] {
    var images: [String] = []
    for index in 0..<_dyld_image_count() {
      if let name = _dyld_get_image_name(index) {
        let path = String(cString:name)
        if URL(fileURLWithPath:path).lastPathComponent == "AdaptivePlotterPackageTests" { images.append(path) }
      }
    }
    guard images.count == 1 else { throw DX04Fixture.Failure.process }
    return ["pid":ProcessInfo.processInfo.processIdentifier,"parentPID":getppid(),"argv":CommandLine.arguments,
      "loadedImage":images[0],"helperTest":"PortraitExchangeProcessHelperTests/helper"]
  }
  static func start(root: URL, mode: String, library: URL? = nil, boundary: String = "", object: String = "", generation: UUID? = nil) throws -> Child {
    let nonce = UUID().uuidString, ready = root.appendingPathComponent("ready-" + nonce), log = root.appendingPathComponent("child-" + nonce + ".log")
    FileManager.default.createFile(atPath: log.path, contents: nil)
    let output = try FileHandle(forWritingTo: log)
    let process = Process()
    let identity = try identity(), image = try #require(identity["loadedImage"] as? String)
    process.executableURL = URL(fileURLWithPath:CommandLine.arguments[0])
    var arguments = Array(CommandLine.arguments.dropFirst())
    if process.executableURL?.lastPathComponent == "swiftpm-testing-helper" {
      guard let index = arguments.firstIndex(of:"--test-bundle-path"), index + 1 < arguments.count,
        URL(fileURLWithPath:arguments[index+1]).resolvingSymlinksInPath() == URL(fileURLWithPath:image).resolvingSymlinksInPath(),
        arguments.filter({ URL(fileURLWithPath:$0).resolvingSymlinksInPath() == URL(fileURLWithPath:image).resolvingSymlinksInPath() }).count == 2 else {
        print("DX04_PARENT_RUNTIME=" + String(describing:identity)); throw DX04Fixture.Failure.process
      }
    }
    var reporterDeviation: [String: Any]?
    if let index = arguments.firstIndex(of: "--xunit-output") {
      guard index + 1 < arguments.count else { throw DX04Fixture.Failure.process }
      let parentReport = arguments[index + 1]
      let childReport = FileManager.default.temporaryDirectory.appendingPathComponent("dx04-helper-report-" + nonce + ".xml")
      arguments[index + 1] = childReport.path
      reporterDeviation = ["mode": mode, "parentReport": parentReport, "childReport": childReport.path,
        "reason": "Unique child reporter outside tested Library/CAS/staging; image and test selection retained"]
    }
    if let index = arguments.firstIndex(of:"--filter"), index + 1 < arguments.count { arguments[index+1] = "PortraitExchangeProcessHelperTests/helper" }
    else { arguments += ["--filter","PortraitExchangeProcessHelperTests/helper"] }
    if !arguments.contains("--testing-library") { arguments += ["--testing-library","swift-testing"] }
    process.arguments = arguments
    var env = ProcessInfo.processInfo.environment
    for key in Array(env.keys) where key.hasPrefix("DX") || key.hasPrefix("LLVM_PROFILE") || key == "PORTRAIT_REAL_PILOT_ROOT" { env.removeValue(forKey: key) }
    env["DX04_PROCESS_HELPER"] = mode; env["DX04_PROCESS_ROOT"] = root.path
    env["DX04_PROCESS_LIBRARY"] = (library ?? root.appendingPathComponent("library")).path
    env["DX04_PROCESS_READY"] = ready.path; env["DX04_PROCESS_BOUNDARY"] = boundary; env["DX04_PROCESS_OBJECT"] = object
    env["DX04_PROCESS_GENERATION"] = generation?.uuidString.lowercased()
    process.environment = env; process.standardOutput = output; process.standardError = output
    try process.run(); try output.close()
    if var reporterDeviation {
      reporterDeviation["pid"] = process.processIdentifier
      print("DX04_HELPER_REPORT_ROUTING=" + String(decoding: try JSONSerialization.data(withJSONObject: reporterDeviation, options: [.sortedKeys]), as: UTF8.self))
    }
    return .init(process:process,ready:ready,log:log,expectedImage:image)
  }
  static func waitReady(_ child: Child) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(20))
    while ContinuousClock.now < deadline {
      if FileManager.default.fileExists(atPath:child.ready.path) {
        let data = try Data(contentsOf:child.ready)
        let proof = try #require(JSONSerialization.jsonObject(with:data) as? [String:Any])
        #expect(proof["pid"] as? Int32 == child.process.processIdentifier)
        #expect(proof["helperTest"] as? String == "PortraitExchangeProcessHelperTests/helper")
        #expect(proof["loadedImage"] as? String == child.expectedImage)
        print("DX04_HELPER_BOUNDARY_PROOF=" + String(decoding:data,as:UTF8.self))
        return
      }
      if !child.process.isRunning { print(try String(contentsOf: child.log, encoding: .utf8)); throw DX04Fixture.Failure.process }
      try await Task.sleep(for: .milliseconds(10))
    }
    stop(child); throw DX04Fixture.Failure.timeout
  }
  static func stop(_ child: Child) { if child.process.isRunning { _ = Darwin.kill(child.process.processIdentifier, SIGKILL) } }
  static func waitExit(_ child: Child) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(20))
    while child.process.isRunning && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    guard !child.process.isRunning else { stop(child); throw DX04Fixture.Failure.timeout }
    if child.process.terminationStatus != 0 && child.process.terminationReason != .uncaughtSignal { print(try String(contentsOf: child.log, encoding: .utf8)) }
  }
}
