import Foundation
import PlotterRuntime
import Testing

@Suite("GRBL parser")
struct GRBLParserTests {
  @Test("fragmented lines preserve raw bytes and unknown grblHAL fields")
  func fragmentationAndUnknownFields() {
    var parser = GRBLParser()
    #expect(parser.consume(Data("<Idle|MPos:1.0,2".utf8)).isEmpty)
    let lines = parser.consume(Data(".0,3.0|Pn:XYZ|Future:value>\r\n".utf8))
    #expect(lines.count == 1)
    #expect(lines[0].rawBytes == Data("<Idle|MPos:1.0,2.0,3.0|Pn:XYZ|Future:value>".utf8))
    guard case .status(let status) = lines[0].kind else {
      Issue.record("expected status")
      return
    }
    #expect(status.state == "Idle")
    #expect(status.pins == "XYZ")
    #expect(status.fields.contains(ControllerField(name: "Future", value: "value")))
  }

  @Test("errors alarms configuration bracket reports and unknowns remain distinct")
  func goldenKinds() {
    let cases: [(String, ControllerLineKind)] = [
      ("ok", .acknowledgement),
      ("error:20", .error(code: "20")),
      ("ALARM:2", .alarm(code: "2")),
      ("$10=511", .configuration(key: "$10", value: "511")),
      ("[GC:G0 G54]", .bracketReport(name: "GC", value: "G0 G54")),
      ("future-extension", .unknown),
    ]
    for (line, expected) in cases {
      #expect(GRBLParser.parseLine(Data(line.utf8)).kind == expected)
    }
  }

  @Test("unterminated data is explicitly recoverable on timeout or disconnect")
  func unterminated() {
    var parser = GRBLParser()
    _ = parser.consume(Data("error:9".utf8))
    let line = parser.finishUnterminatedLine()
    #expect(line?.kind == .error(code: "9"))
    #expect(parser.finishUnterminatedLine() == nil)
  }
}
