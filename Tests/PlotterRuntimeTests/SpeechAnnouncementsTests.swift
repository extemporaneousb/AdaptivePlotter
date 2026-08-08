import Foundation
import Testing

@testable import PlotterRuntime

@Suite("Speech announcements")
struct SpeechAnnouncementsTests {
  @Test("empty announcement completes without starting speech")
  func emptyAnnouncement() async {
    let announcer = NativeSpeechAnnouncer(timeoutNanoseconds: 1_000_000)
    #expect(await announcer.announce("   ") == .completed)
  }

  @Test("queued announcements serialize and late completion cannot resolve the successor")
  func orderedIdentityBoundResolution() {
    let first = UUID()
    let second = UUID()
    var state = SpeechAnnouncementQueueState()

    #expect(state.enqueue(first) == first)
    #expect(state.activeID == first)
    #expect(state.enqueue(second) == nil)
    #expect(state.activeID == first)
    #expect(state.pendingIDs == [second])

    #expect(state.resolve(first) == second)
    #expect(state.activeID == second)
    #expect(state.resolve(first) == nil)
    #expect(state.activeID == second)
    #expect(state.resolve(second) == nil)
    #expect(state.activeID == nil)
  }

  @Test("cancelled queue returns active then pending identities exactly once")
  func cancellationOrdering() {
    let first = UUID()
    let second = UUID()
    var state = SpeechAnnouncementQueueState()
    _ = state.enqueue(first)
    _ = state.enqueue(second)
    #expect(state.cancelAll() == [first, second])
    #expect(state.cancelAll().isEmpty)
  }
}
