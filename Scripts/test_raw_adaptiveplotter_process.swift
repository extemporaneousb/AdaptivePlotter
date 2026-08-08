import Foundation

@main
private enum RawAdaptivePlotterProcessFixture {
    static func main() {
        let seconds = CommandLine.arguments.dropFirst().first
            .flatMap(TimeInterval.init) ?? 3
        Thread.sleep(forTimeInterval: seconds)
    }
}
