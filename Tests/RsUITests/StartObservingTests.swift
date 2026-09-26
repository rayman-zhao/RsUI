import Foundation
import Observation
import Testing

@testable import RsUI

@Observable
private final class ObservableViewModel {
    var value = 0
}

@Suite
struct StartObservingTests {
    @Test
    @MainActor
    func returningFalseOnLaterEmissionStopsObservation() async {
        let model = ObservableViewModel()
        var received: [Int] = []
        startObserving(emitting: { model.value }) { value in
            received.append(value)
            return value != 2
        }

        await waitForCallbacks { received.contains(0) }
        model.value = 2
        await waitForCallbacks { received.contains(2) }

        model.value = 3
        try? await Task.sleep(for: .milliseconds(100))
        #expect(received == [0, 2])
    }

    @Test
    @MainActor
    func returningFalseOnInitialEmissionStopsObservation() async {
        let model = ObservableViewModel()
        var received: [Int] = []
        startObserving(emitting: { model.value }) { value in
            received.append(value)
            return false
        }

        await waitForCallbacks { !received.isEmpty }
        model.value = 1
        try? await Task.sleep(for: .milliseconds(100))
        #expect(received == [0])
    }

    /// 轮询等待首个/目标回调送达；超时不在此报错，交给断言报告实际收到的值。
    @MainActor
    private func waitForCallbacks(_ condition: () -> Bool) async {
        for _ in 0 ..< 200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
