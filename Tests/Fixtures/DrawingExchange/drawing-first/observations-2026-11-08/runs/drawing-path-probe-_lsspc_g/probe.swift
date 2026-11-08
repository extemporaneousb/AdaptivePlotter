import Foundation
let fm = FileManager.default
let temporary = fm.temporaryDirectory.appendingPathComponent("drawing-foundation-probe-" + UUID().uuidString, isDirectory: true)
try fm.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
defer { try? fm.removeItem(at: temporary) }
let bag = temporary.appendingPathComponent("bag", isDirectory: true)
let data = bag.appendingPathComponent("data", isDirectory: true)
try fm.createDirectory(at: data, withIntermediateDirectories: true)
try Data("{}".utf8).write(to: data.appendingPathComponent("exchange.json"))
let files = fm.enumerator(at: data, includingPropertiesForKeys: [.isRegularFileKey])!
var observations: [[String: String]] = []
for case let url as URL in files {
  if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
    observations.append(["bagPath": bag.path, "urlPath": url.path,
      "derivedRelative": String(url.path.dropFirst(bag.path.count + 1)),
      "canonicalBagPath": bag.resolvingSymlinksInPath().standardizedFileURL.path,
      "canonicalURLPath": url.resolvingSymlinksInPath().standardizedFileURL.path,
      "canonicalDerivedRelative": String(url.resolvingSymlinksInPath().standardizedFileURL.path.dropFirst(bag.resolvingSymlinksInPath().standardizedFileURL.path.count + 1))])
  }
}
let output = try JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
FileHandle.standardOutput.write(output)
FileHandle.standardOutput.write(Data("\n".utf8))
