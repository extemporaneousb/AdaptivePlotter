import CoreGraphics
import Testing

@testable import PlotterApp

@Suite("Learning workbench layout policy")
struct LearningWorkbenchLayoutTests {
  private let policy = LearningWorkbenchLayoutPolicy()

  @Test("camera is the largest region at the supported minimum window width")
  func minimumWindowWidth() {
    let allocation = policy.allocation(for: LearningWorkbenchLayoutPolicy.minimumWindowWidth)

    #expect(allocation.totalWidth == LearningWorkbenchLayoutPolicy.minimumWindowWidth)
    #expect(allocation.cameraWidth >= policy.minimumCameraWidth)
    #expect(allocation.cameraWidth > allocation.navigatorWidth)
    #expect(allocation.cameraWidth > allocation.detailWidth)
  }

  @Test("camera receives wide and full-screen growth")
  func wideWindow() {
    let normal = policy.allocation(for: 1_440)
    let wide = policy.allocation(for: 2_560)

    #expect(wide.navigatorWidth == normal.navigatorWidth)
    #expect(wide.detailWidth == normal.detailWidth)
    #expect(wide.cameraWidth > normal.cameraWidth)
    #expect(wide.totalWidth == 2_560)
  }

  @Test("side regions shrink before the protected camera")
  func undersizedWindow() {
    let allocation = policy.allocation(for: 1_000)

    #expect(allocation.cameraWidth == policy.minimumCameraWidth)
    #expect(allocation.navigatorWidth < policy.preferredNavigatorWidth)
    #expect(allocation.detailWidth < policy.preferredDetailWidth)
    #expect(allocation.totalWidth == 1_000)
  }

  @Test("nonfinite and negative widths remain bounded")
  func malformedWidths() {
    for width: CGFloat in [.nan, -CGFloat.infinity, -1] {
      let allocation = policy.allocation(for: width)
      #expect(allocation.totalWidth == 0)
      #expect(allocation.navigatorWidth == 0)
      #expect(allocation.cameraWidth == 0)
      #expect(allocation.detailWidth == 0)
    }
  }
}
