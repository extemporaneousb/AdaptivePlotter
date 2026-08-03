import Foundation

/// Deterministic, explicitly simulated composition data for the operator shell.
public enum OfflineRuntimePrototype {
  public static func simulatedPassiveTranscript() -> [TranscriptEntry] {
    func tx(_ query: PassiveQuery) -> TranscriptEntry {
      TranscriptEntry(direction: .transmit, bytes: query.wireBytes)
    }
    func rx(_ text: String) -> TranscriptEntry {
      TranscriptEntry(direction: .receive, bytes: Data(text.utf8), delayNanoseconds: 1_000_000)
    }
    return [
      tx(.buildInfo), rx("[VER:simulated-offline:]\r\nok\r\n"),
      tx(.parserState), rx("[GC:G0 G54 G17 G21 G90]\r\nok\r\n"),
      tx(.status), rx("<Idle|MPos:0.000,0.000,0.000|FS:0,0>\r\n"),
      tx(.configuration), rx("$10=511\r\nok\r\n"),
      tx(.coordinateOffsets), rx("[G54:0.000,0.000,0.000]\r\nok\r\n"),
    ]
  }
}
