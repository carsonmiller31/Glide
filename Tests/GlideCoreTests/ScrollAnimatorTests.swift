import XCTest
@testable import GlideCore

final class ScrollAnimatorTests: XCTestCase {
    private let config = ScrollConfig(stepSize: 120, duration: 0.35, acceleration: 0.5)

    private func run(_ a: inout ScrollAnimator, seconds: Double, fps: Double = 120) -> (x: Int, y: Int, frames: [Int]) {
        var x = 0, y = 0, frames: [Int] = []
        for _ in 0..<Int(seconds * fps) {
            let d = a.frame(dt: 1 / fps, config: config)
            x += d.dx; y += d.dy; frames.append(d.dy)
        }
        return (x, y, frames)
    }

    func testOneNotchTravelsExactlyOneStepAndSettles() {
        var a = ScrollAnimator()
        a.notch(axis: .vertical, direction: 1, at: 0, config: config)
        let r = run(&a, seconds: 1)
        XCTAssertEqual(r.y, 120)
        XCTAssertEqual(r.x, 0)
        XCTAssertTrue(a.isIdle)
    }

    func testMotionEasesOut() {
        var a = ScrollAnimator()
        a.notch(axis: .vertical, direction: -1, at: 0, config: config)
        let frames = run(&a, seconds: 1).frames
        XCTAssertLessThan(frames[0], 0)
        XCTAssertGreaterThan(abs(frames[0]), abs(frames[10]))
        XCTAssertGreaterThan(abs(frames[10]), abs(frames[30]))
    }

    func testMostDistanceCoveredWithinDuration() {
        var a = ScrollAnimator()
        a.notch(axis: .vertical, direction: 1, at: 0, config: config)
        let r = run(&a, seconds: config.duration)
        XCTAssertGreaterThanOrEqual(r.y, 115)
    }

    func testReversingStopsCurrentGlide() {
        var a = ScrollAnimator()
        a.notch(axis: .vertical, direction: 1, at: 0, config: config)
        _ = a.frame(dt: 1 / 120, config: config)
        a.notch(axis: .vertical, direction: -1, at: 0.5, config: config)
        XCTAssertEqual(a.pending.y, -120)
    }

    func testFastSpinAccelerates() {
        var a = ScrollAnimator()
        for i in 0..<8 { a.notch(axis: .vertical, direction: 1, at: Double(i) * 0.02, config: config) }
        XCTAssertGreaterThan(a.accelerationFactor, 3)
        XCTAssertLessThanOrEqual(a.accelerationFactor, 1 + config.acceleration * 9)
    }

    func testSlowNotchesDoNotAccelerate() {
        var a = ScrollAnimator()
        for i in 0..<5 { a.notch(axis: .vertical, direction: 1, at: Double(i) * 0.5, config: config) }
        XCTAssertEqual(a.accelerationFactor, 1)
    }

    func testAccelerationOff() {
        var a = ScrollAnimator()
        let flat = ScrollConfig(stepSize: 100, duration: 0.3, acceleration: 0)
        for i in 0..<10 { a.notch(axis: .vertical, direction: 1, at: Double(i) * 0.01, config: flat) }
        XCTAssertEqual(a.pending.y, 1000)
    }

    func testHorizontalIsIndependent() {
        var a = ScrollAnimator()
        a.notch(axis: .horizontal, direction: -1, at: 0, config: config)
        let r = run(&a, seconds: 1)
        XCTAssertEqual(r.x, -120)
        XCTAssertEqual(r.y, 0)
    }

    func testNoDriftAt60Hz() {
        var a = ScrollAnimator()
        for i in 0..<3 { a.notch(axis: .vertical, direction: 1, at: Double(i) * 0.3, config: config) }
        let r = run(&a, seconds: 2, fps: 60)
        XCTAssertEqual(r.y, 360)
    }
}
