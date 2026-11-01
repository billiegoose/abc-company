import Testing
@testable import ALIARCore

@Test func stillFrameLatchIsOneShotAndResettable() {
    let latch = FrameCaptureLatch()
    #expect(latch.consume() == nil)
    latch.arm(request: 17)
    #expect(latch.consume() == 17)
    #expect(latch.consume() == nil)
    latch.arm(request: 18)
    latch.reset()
    #expect(latch.consume() == nil)
    latch.arm(request: 19)
    #expect(latch.consume() == 19)
}
