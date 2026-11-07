import Foundation

/// Tunables for how a wheel notch turns into motion.
public struct ScrollConfig: Equatable {
    /// Pixels travelled per wheel notch before acceleration.
    public var stepSize: Double
    /// Roughly how long one notch takes to settle, in seconds.
    public var duration: Double
    /// 0 = every notch moves the same distance, 1 = fast spins travel up to 10x.
    public var acceleration: Double

    public init(stepSize: Double = 120, duration: Double = 0.35, acceleration: Double = 0.5) {
        self.stepSize = stepSize
        self.duration = duration
        self.acceleration = acceleration
    }

    /// Notches closer together than this count as one continuous spin.
    public static let spinWindow: Double = 0.12
}

public enum ScrollAxis { case vertical, horizontal }

/// Pure scrolling physics: wheel notches in, per-frame pixel deltas out.
/// No CoreGraphics here so it can be unit tested without an event tap.
public struct ScrollAnimator {
    private var remaining = (x: 0.0, y: 0.0)
    private var carry = (x: 0.0, y: 0.0)
    private var lastNotch: (time: Double, axis: ScrollAxis, direction: Int)?
    private(set) public var accelerationFactor = 1.0

    public init() {}

    public var isIdle: Bool { remaining.x == 0 && remaining.y == 0 }

    /// Pixels still to be emitted on each axis (for tests and diagnostics).
    public var pending: (x: Double, y: Double) { remaining }

    /// Registers one wheel notch. `direction` is +1 or -1 in CGEvent sign
    /// convention (positive = content moves down/right, i.e. scroll up/left).
    public mutating func notch(axis: ScrollAxis, direction: Int, at time: Double, config: ScrollConfig) {
        guard direction != 0 else { return }
        let dir = direction > 0 ? 1 : -1

        if let last = lastNotch, last.axis == axis, last.direction == dir,
           time - last.time < ScrollConfig.spinWindow, config.acceleration > 0 {
            // Faster spins accelerate harder.
            let speed = (ScrollConfig.spinWindow - (time - last.time)) / ScrollConfig.spinWindow
            let ceiling = 1 + config.acceleration * 9
            accelerationFactor = min(accelerationFactor + speed * config.acceleration * 1.5, ceiling)
        } else {
            accelerationFactor = 1
        }
        lastNotch = (time, axis, dir)

        let distance = Double(dir) * config.stepSize * accelerationFactor
        switch axis {
        case .vertical:
            // Turning the wheel the other way stops the current glide at once.
            if remaining.y != 0, (remaining.y > 0) != (distance > 0) { remaining.y = 0; carry.y = 0 }
            remaining.y += distance
        case .horizontal:
            if remaining.x != 0, (remaining.x > 0) != (distance > 0) { remaining.x = 0; carry.x = 0 }
            remaining.x += distance
        }
    }

    /// Cancels any motion in flight.
    public mutating func stop() {
        remaining = (0, 0)
        carry = (0, 0)
    }

    /// Advances by `dt` seconds and returns whole pixels to post this frame.
    /// Exponential ease-out: fast at first, settling over `config.duration`.
    public mutating func frame(dt: Double, config: ScrollConfig) -> (dx: Int, dy: Int) {
        // After `duration`, e^-4.6 ≈ 1% of the distance is left.
        let tau = max(config.duration, 0.03) / 4.6
        let k = 1 - exp(-max(dt, 0) / tau)
        let dy = Self.advance(&remaining.y, &carry.y, k)
        let dx = Self.advance(&remaining.x, &carry.x, k)
        return (dx, dy)
    }

    private static func advance(_ remaining: inout Double, _ carry: inout Double, _ k: Double) -> Int {
        guard remaining != 0 else { return 0 }
        var d = remaining * k
        if abs(remaining) <= 1 || abs(d) >= abs(remaining) { d = remaining }
        remaining -= d
        // Posted deltas are integers: carry the fraction so nothing is lost.
        carry += d
        let whole = carry.rounded(.towardZero)
        carry -= whole
        if remaining == 0 {
            // Flush the tail so the total always equals what was asked for.
            let tail = carry.rounded()
            carry = 0
            return Int(whole + tail)
        }
        return Int(whole)
    }
}
