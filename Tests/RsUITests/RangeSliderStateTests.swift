import Foundation
import Testing

@testable import RsUI

@Suite struct RangeSliderStateTests {
    @Test func clampsValuesToDomain() {
        var state = RangeSliderState(lowerValue: 25, upperValue: 75)
        var changed = state.setLower(-10)
        #expect(changed)
        #expect(state.lowerValue == 0)
        changed = state.setLower(200)
        #expect(changed)
        // lower cannot pass the current upper
        #expect(state.lowerValue == 75)
        changed = state.setLower(75)
        #expect(!changed)
        changed = state.setUpper(500)
        #expect(changed)
        #expect(state.upperValue == 100)
    }

    @Test func snapsToStepFrequency() {
        var state = RangeSliderState(stepFrequency: 5, lowerValue: 25, upperValue: 75)
        var changed = state.setLower(33)
        #expect(changed)
        #expect(state.lowerValue == 35)
        changed = state.setLower(32)
        #expect(changed)
        #expect(state.lowerValue == 30)
        // step of 0 keeps raw values
        var continuous = RangeSliderState(lowerValue: 25, upperValue: 75)
        _ = continuous.setLower(33.25)
        #expect(continuous.lowerValue == 33.25)
    }

    @Test func cleansFloatingPointNoise() {
        var state = RangeSliderState(stepFrequency: 0.1, lowerValue: 0, upperValue: 100)
        _ = state.setLower(0.30000000000000004)
        #expect(state.lowerValue == 0.3)
    }

    @Test func enforcesMinGap() {
        var state = RangeSliderState(minGap: 10, lowerValue: 25, upperValue: 75)
        var changed = state.setUpper(30)
        #expect(changed)
        #expect(state.upperValue == 35)  // lower(25) + minGap

        var other = RangeSliderState(minGap: 10, lowerValue: 25, upperValue: 75)
        changed = other.setLower(70)
        #expect(changed)
        #expect(other.lowerValue == 65)  // upper(75) - minGap
        // minGap clamped to the span pins the range to the full domain
        var tight = RangeSliderState(minimum: 0, maximum: 5, minGap: 100, lowerValue: 1, upperValue: 4)
        #expect(tight.minGap == 5)
        #expect(tight.range == 0...5)
        changed = tight.setLower(4)
        #expect(!changed)
        changed = tight.setUpper(1)
        #expect(!changed)
    }

    @Test func setRangeSwapsAndWidens() {
        var state = RangeSliderState(minGap: 10, lowerValue: 25, upperValue: 75)
        var changed = state.setRange(lower: 80, upper: 20)
        // unordered input swaps
        #expect(changed)
        #expect(state.range == 20...80)
        changed = state.setRange(lower: 40, upper: 42)
        // too narrow: anchored at lower, upper expands
        #expect(changed)
        #expect(state.range == 40...50)
        changed = state.setRange(lower: 95, upper: 97)
        // too narrow near maximum: lower is pulled back
        #expect(changed)
        #expect(state.range == 90...100)
    }

    @Test func shrinkingDomainRevalidatesInvariant() {
        var state = RangeSliderState(lowerValue: 25, upperValue: 75)
        var changed = state.setDomain(maximum: 10)
        #expect(changed)
        #expect(state.range == 10...10)

        var raised = RangeSliderState(lowerValue: 25, upperValue: 75)
        changed = raised.setDomain(minimum: 90)
        #expect(changed)
        #expect(raised.range == 90...90)

        var shrunk = RangeSliderState(lowerValue: 30, upperValue: 70)
        changed = shrunk.setDomain(minimum: 20, maximum: 50)
        #expect(changed)
        #expect(shrunk.range == 30...50)
    }

    @Test func fractionAndValueRoundTrip() {
        let state = RangeSliderState(minimum: -100, maximum: 100, lowerValue: 0, upperValue: 50)
        #expect(state.fraction(of: -100) == 0)
        #expect(state.fraction(of: 0) == 0.5)
        #expect(state.fraction(of: 300) == 1)
        #expect(state.fraction(of: 25) == 0.625)
        #expect(state.value(atFraction: 0.25) == -50)
        #expect(state.value(atFraction: 1) == 100)

        let degenerate = RangeSliderState(minimum: 5, maximum: 5, lowerValue: 5, upperValue: 5)
        #expect(degenerate.fraction(of: 5) == 0)
        #expect(degenerate.value(atFraction: 0.7) == 5)
    }
}
