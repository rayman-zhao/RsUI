import Foundation
import Testing

@testable import RsUI

@Suite struct GridViewSelectionModelTests {
    // MARK: - 框选几何

    @Test func marqueeRectNormalizesRightDownDrag() {
        let rect = GridViewSelectionModel.marqueeRect(start: (10, 10), current: (110, 60))
        #expect(rect == .init(x: 10, y: 10, width: 100, height: 50))
    }

    @Test func marqueeRectNormalizesLeftUpDrag() {
        let rect = GridViewSelectionModel.marqueeRect(start: (110, 60), current: (10, 10))
        #expect(rect == .init(x: 10, y: 10, width: 100, height: 50))
    }

    @Test func marqueeRectNormalizesMixedDrag() {
        let rect = GridViewSelectionModel.marqueeRect(start: (100, 20), current: (40, 120))
        #expect(rect == .init(x: 40, y: 20, width: 60, height: 100))
    }

    @Test func marqueeRectHandlesZeroDrag() {
        let rect = GridViewSelectionModel.marqueeRect(start: (30, 40), current: (30, 40))
        #expect(rect == .init(x: 30, y: 40, width: 0, height: 0))
    }

    // MARK: - 框选启动阈值

    @Test func marqueeNotEngagedBelowThreshold() {
        let tiny = GridViewSelectionModel.marqueeRect(start: (0, 0), current: (3, 3))
        #expect(!GridViewSelectionModel.marqueeEngaged(tiny))
        let wideEnough = GridViewSelectionModel.marqueeRect(start: (0, 0), current: (4, 0))
        #expect(GridViewSelectionModel.marqueeEngaged(wideEnough))
    }

    // MARK: - 框选增量

    @Test func marqueeDeltaSelectsNewAndDeselectsRemoved() {
        let delta = GridViewSelectionModel.marqueeDelta(
            applied: [0, 1, 2], target: [1, 2, 3])
        #expect(delta.select == [3])
        #expect(delta.deselect == [0])
    }

    @Test func marqueeDeltaEmptyWhenUnchanged() {
        let delta = GridViewSelectionModel.marqueeDelta(
            applied: [1, 3], target: [3, 1])
        #expect(delta.select.isEmpty)
        #expect(delta.deselect.isEmpty)
    }

    @Test func marqueeDeltaFromEmptySelectsAll() {
        let delta = GridViewSelectionModel.marqueeDelta(applied: [], target: [0, 5])
        #expect(delta.select == [0, 5])
        #expect(delta.deselect.isEmpty)
    }

    // MARK: - 复选框可见性

    @Test func checkBoxVisibleOnlyWhenEnabledAndHovered() {
        #expect(GridViewSelectionModel.isCheckBoxVisible(isEnabled: true, isHovered: true))
        #expect(!GridViewSelectionModel.isCheckBoxVisible(isEnabled: true, isHovered: false))
        #expect(!GridViewSelectionModel.isCheckBoxVisible(isEnabled: false, isHovered: true))
        #expect(!GridViewSelectionModel.isCheckBoxVisible(isEnabled: false, isHovered: false))
    }
}
