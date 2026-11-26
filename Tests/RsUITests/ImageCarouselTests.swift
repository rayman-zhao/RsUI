import Testing

@testable import RsUI

// ImageCarousel 是 WinUI 控件子类（@MainActor），其静态算术随之隔离。
@MainActor
@Suite struct ImageCarouselTests {
    private let stride = 248.0
    private let count = 12

    @Test func nearestPageRoundsToClosestAndClamps() {
        #expect(ImageCarousel.nearestPage(toOffset: 0, stride: stride, count: count) == 0)
        #expect(ImageCarousel.nearestPage(toOffset: 360, stride: stride, count: count) == 1)
        #expect(ImageCarousel.nearestPage(toOffset: 380, stride: stride, count: count) == 2)
        #expect(ImageCarousel.nearestPage(toOffset: -500, stride: stride, count: count) == 0)
        #expect(ImageCarousel.nearestPage(toOffset: 9000, stride: stride, count: count) == 11)
        // Degenerate stride / empty list must not divide by zero or index out of range.
        #expect(ImageCarousel.nearestPage(toOffset: 100, stride: 0, count: count) == 0)
        #expect(ImageCarousel.nearestPage(toOffset: 100, stride: stride, count: 0) == 0)
    }
}
