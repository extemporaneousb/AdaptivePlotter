import Foundation
import PlotterRuntime

public enum ControllerTranscriptFixtures {
  public static func successfulPassiveProbe(
    fragmented: Bool = true,
    delayNanoseconds: UInt64 = 10
  ) -> [SimulatedCommandExchange] {
    [
      exchange(
        .buildInfo,
        chunks: fragmented
          ? ["[VER:1.1h.20240101:]\r\n[OPT:VN,15,128]", "\r\nok\r\n"]
          : ["[VER:1.1h.20240101:]\r\n[OPT:VN,15,128]\r\nok\r\n"],
        delay: delayNanoseconds
      ),
      exchange(
        .parserState, chunks: ["[GC:G0 G54 G17 G21 G90 G94 M5 M9 T0 F0 S0]\r\nok\r\n"],
        delay: delayNanoseconds),
      exchange(
        .status, chunks: ["<Idle|MPos:0.000,0.000,0.000|FS:0,0|Pn:XYZ|XFuture:kept>\r\n"],
        delay: delayNanoseconds),
      exchange(
        .configuration, chunks: ["$10=511\r\n$30=1000\r\n$Future=opaque\r\nok\r\n"],
        delay: delayNanoseconds),
      exchange(
        .coordinateOffsets,
        chunks: ["[G54:0.000,0.000,0.000]\r\n[G92:0.000,0.000,0.000]\r\nok\r\n"],
        delay: delayNanoseconds),
    ]
  }

  public static func exchange(
    _ query: PassiveQuery,
    chunks: [String],
    delay: UInt64 = 0
  ) -> SimulatedCommandExchange {
    SimulatedCommandExchange(
      expectedWrite: query.wireBytes,
      reads: chunks.map {
        ScheduledMachineRead(
          delayNanoseconds: delay,
          outcome: .bytes(Data($0.utf8))
        )
      }
    )
  }
}
