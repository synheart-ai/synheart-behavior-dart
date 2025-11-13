import Foundation
import UIKit

/// Collects gesture and scroll signals.
/// Privacy: Only timing and velocity metrics, no content or coordinates.
class GestureCollector: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {

    private var config: BehaviorConfig
    private var eventHandler: ((BehaviorEvent) -> Void)?

    // Scroll tracking
    private var scrollVelocities: [Double] = []
    private var lastScrollOffset: CGFloat = 0
    private var lastScrollTime: Double = 0
    private var previousVelocity: Double = 0

    // Tap tracking
    private var tapTimestamps: [Double] = []
    private var longPressCount: Int = 0

    // Gesture recognizers
    private var tapRecognizers: [UITapGestureRecognizer] = []
    private var longPressRecognizers: [UILongPressGestureRecognizer] = []
    private var panRecognizers: [UIPanGestureRecognizer] = []

    init(config: BehaviorConfig) {
        self.config = config
    }

    func setEventHandler(_ handler: @escaping (BehaviorEvent) -> Void) {
        self.eventHandler = handler
    }

    func attachToView(_ view: UIView) {
        guard config.enableInputSignals else { return }

        // Attach scroll delegate if it's a scroll view
        if let scrollView = view as? UIScrollView {
            scrollView.delegate = self
        }

        // Add gesture recognizers
        addGestureRecognizers(to: view)

        // Recursively attach to subviews
        for subview in view.subviews {
            attachToView(subview)
        }
    }

    func updateConfig(_ newConfig: BehaviorConfig) {
        config = newConfig
    }

    func dispose() {
        scrollVelocities.removeAll()
        tapTimestamps.removeAll()
        tapRecognizers.forEach { $0.view?.removeGestureRecognizer($0) }
        longPressRecognizers.forEach { $0.view?.removeGestureRecognizer($0) }
        panRecognizers.forEach { $0.view?.removeGestureRecognizer($0) }
        tapRecognizers.removeAll()
        longPressRecognizers.removeAll()
        panRecognizers.removeAll()
    }

    private func addGestureRecognizers(to view: UIView) {
        // Tap gesture
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
        tapRecognizers.append(tapGesture)

        // Long press gesture
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.delegate = self
        view.addGestureRecognizer(longPressGesture)
        longPressRecognizers.append(longPressGesture)

        // Pan gesture for drag detection
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
        panRecognizers.append(panGesture)
    }

    // MARK: - Gesture Handlers

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let now = Date().timeIntervalSince1970 * 1000
        tapTimestamps.append(now)

        // Keep only last 50 taps
        if tapTimestamps.count > 50 {
            tapTimestamps.removeFirst()
        }

        emitTapRate()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            longPressCount += 1
            emitLongPressRate()
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view else { return }

        if gesture.state == .changed {
            let velocity = gesture.velocity(in: view)
            let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
            emitDragVelocity(velocity: Double(speed))
        }
    }

    // MARK: - UIScrollViewDelegate

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let now = Date().timeIntervalSince1970 * 1000

        if lastScrollTime == 0 {
            lastScrollTime = now
            lastScrollOffset = scrollView.contentOffset.y
            return
        }

        let timeDelta = now - lastScrollTime
        guard timeDelta > 0 else { return }

        let offsetDelta = abs(scrollView.contentOffset.y - lastScrollOffset)
        let velocity = Double(offsetDelta) / timeDelta * 1000.0 // pixels per second

        scrollVelocities.append(velocity)
        if scrollVelocities.count > 20 {
            scrollVelocities.removeFirst()
        }

        // Calculate acceleration
        let acceleration = previousVelocity > 0 ? (velocity - previousVelocity) / timeDelta * 1000.0 : 0.0

        // Calculate jitter
        let jitter: Double
        if scrollVelocities.count > 2 {
            let mean = scrollVelocities.reduce(0, +) / Double(scrollVelocities.count)
            let squaredDiffs = scrollVelocities.map { pow($0 - mean, 2) }
            jitter = sqrt(squaredDiffs.reduce(0, +) / Double(squaredDiffs.count))
        } else {
            jitter = 0.0
        }

        // Emit scroll events
        if velocity > 10.0 {
            emitScrollVelocity(velocity: velocity)

            if abs(acceleration) > 100.0 {
                emitScrollAcceleration(acceleration: acceleration)
            }

            if jitter > 50.0 {
                emitScrollJitter(jitter: jitter)
            }
        } else if previousVelocity > 10.0 && velocity < 10.0 {
            emitScrollStop()
        }

        previousVelocity = velocity
        lastScrollTime = now
        lastScrollOffset = scrollView.contentOffset.y
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            emitScrollStop()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        emitScrollStop()
    }

    // MARK: - Event Emitters

    private func emitScrollVelocity(velocity: Double) {
        eventHandler?(BehaviorEvent(
            sessionId: "current",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            type: "scrollVelocity",
            payload: [
                "velocity": velocity,
                "unit": "pixels_per_second"
            ]
        ))
    }

    private func emitScrollAcceleration(acceleration: Double) {
        eventHandler?(BehaviorEvent(
            sessionId: "current",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            type: "scrollAcceleration",
            payload: [
                "acceleration": acceleration,
                "unit": "pixels_per_second_squared"
            ]
        ))
    }

    private func emitScrollJitter(jitter: Double) {
        eventHandler?(BehaviorEvent(
            sessionId: "current",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            type: "scrollJitter",
            payload: [
                "jitter": jitter,
                "sample_size": scrollVelocities.count
            ]
        ))
    }

    private func emitScrollStop() {
        eventHandler?(BehaviorEvent(
            sessionId: "current",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            type: "scrollStop",
            payload: [
                "final_velocity": previousVelocity
            ]
        ))
        previousVelocity = 0
    }

    private func emitTapRate() {
        let now = Date().timeIntervalSince1970 * 1000
        let recentTaps = tapTimestamps.filter { $0 > now - 10000 }
        let tapRate = Double(recentTaps.count) / 10.0

        eventHandler?(BehaviorEvent(
            sessionId: "current",
            timestamp: Int64(now),
            type: "tapRate",
            payload: [
                "tap_rate": tapRate,
                "taps_in_window": recentTaps.count,
                "window_seconds": 10
            ]
        ))
    }

    private func emitLongPressRate() {
        eventHandler?(BehaviorEvent(
            sessionId: "current",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            type: "longPressRate",
            payload: [
                "long_press_count": longPressCount
            ]
        ))
    }

    private func emitDragVelocity(velocity: Double) {
        eventHandler?(BehaviorEvent(
            sessionId: "current",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            type: "dragVelocity",
            payload: [
                "velocity": velocity,
                "unit": "pixels_per_second"
            ]
        ))
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true // Allow multiple gestures to be recognized simultaneously
    }
}
