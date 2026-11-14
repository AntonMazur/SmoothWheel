import Foundation

/// Conserves wheel distance, cancels old momentum on reversal, and uses elapsed time.
public struct ScrollSmoother {
    public private(set) var remaining = 0.0
    private var carry = 0.0
    private var velocity = 0.0
    private var landingTime = 0.0
    public init() {}
    public mutating func reset() { remaining = 0; carry = 0; velocity = 0; landingTime = 0 }
    public mutating func add(_ distance: Double) {
        guard distance.isFinite, distance != 0 else { return }
        if remaining * distance < 0 { reset() }
        landingTime = 0
        let starting = remaining == 0
        remaining = min(2400, max(-2400, remaining + distance))
        // A small initial response keeps first input/reversal responsive. Further
        // same-direction notches preserve velocity instead of restarting it.
        if starting { velocity = remaining * 4 }
    }
    public mutating func step(seconds: Double, smoothing: Double) -> Int32 {
        guard remaining != 0, seconds > 0, seconds.isFinite else { return 0 }
        let dt = min(seconds, 1 / 30)
        // Integer pixel events cannot represent an indefinitely shrinking velocity.
        // Finish the last three pixels over a bounded, steady landing instead of
        // separating single-pixel packets by increasingly long pauses.
        if landingTime == 0 && abs(remaining) <= 3 { landingTime = 0.06 }
        if landingTime > 0 {
            let fraction = min(1, dt / landingTime)
            let amount = remaining * fraction
            velocity = remaining / landingTime
            remaining -= amount
            carry += amount
            landingTime = max(0, landingTime - dt)
            if landingTime < 0.0000001 {
                let pixels = (carry + remaining).rounded()
                reset()
                return Int32(pixels)
            }
            let pixels = carry.rounded(.towardZero)
            carry -= pixels
            return Int32(pixels)
        }
        let tau = 0.035 + min(1, max(0, smoothing)) * 0.18
        let omega = 2 / tau
        let decay = exp(-omega * dt)
        let accelerationTerm = omega * remaining - velocity
        let nextRemaining = (remaining + accelerationTerm * dt) * decay
        velocity = (velocity + omega * accelerationTerm * dt) * decay
        carry += remaining - nextRemaining
        remaining = nextRemaining
        let pixels: Double
        // Finish once less than half a pixel remains. Emit the rounded residual
        // once, rather than waking the frame timer through an invisible tail.
        if abs(remaining) < 0.5 {
            pixels = (carry + remaining).rounded()
            reset()
        } else {
            pixels = carry.rounded(.towardZero)
            carry -= pixels
        }
        return Int32(pixels)
    }
}
