import Foundation
import UIKit

/// Collects gesture and scroll signals.
/// Privacy: Only timing and velocity metrics, no content or coordinates.
class GestureCollector: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {

    private var config: BehaviorConfig
    private var eventHandler: ((BehaviorEvent) -> Void)?

    // Scroll tracking
    private var lastScrollOffset: CGFloat = 0
    private var lastScrollTime: Double = 0
    private var previousVelocity: Double = 0
    private var lastScrollDirection: String? = nil // "up", "down", "left", "right"
    private var hasDirectionReversal = false

    // Tap tracking
    private var tapTimestamps: [Double] = []
    private var tapStartTime: Double = 0
    private var panStartTimeForTap: Double = 0 // Track pan start time for tap duration
    private let longPressThresholdMs: Double = 500.0

    // Swipe tracking
    private var swipeStartTime: Double = 0
    private var swipeStartPoint: CGPoint = .zero
    private var swipeLastPoint: CGPoint = .zero
    private var isSwipe = false
    private let swipeThresholdPx: CGFloat = 50.0
    private let tapMovementTolerancePx: CGFloat = 10.0 // Allow small movement for taps
    private var previousSwipeVelocity: Double = 0
    private var lastSwipeVelocityTime: Double = 0

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
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
        tapRecognizers.append(tapGesture)

        // Long press gesture
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.delegate = self
        longPressGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(longPressGesture)
        longPressRecognizers.append(longPressGesture)

        // Pan gesture for drag detection
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        panGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(panGesture)
        panRecognizers.append(panGesture)
    }

    // MARK: - Gesture Handlers

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let now = Date().timeIntervalSince1970 * 1000
        tapStartTime = now
        
        // Use actual duration from pan gesture if available, otherwise estimate
        // UITapGestureRecognizer doesn't provide duration, so we use pan gesture timing
        let actualDuration: Int
        if panStartTimeForTap > 0 {
            actualDuration = Int(now - panStartTimeForTap)
            panStartTimeForTap = 0 // Reset
        } else {
            // Fallback: estimate based on typical tap duration (50-100ms)
            actualDuration = 75
        }
        
        emitTapEvent(tapDurationMs: actualDuration, longPress: false)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            tapStartTime = Date().timeIntervalSince1970 * 1000
        } else if gesture.state == .ended {
            let duration = Date().timeIntervalSince1970 * 1000 - tapStartTime
            emitTapEvent(tapDurationMs: Int(duration), longPress: true)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view else { return }
        
        if gesture.state == .began {
            let now = Date().timeIntervalSince1970 * 1000
            swipeStartTime = now
            panStartTimeForTap = now // Track start time for tap duration measurement
            swipeStartPoint = gesture.location(in: view)
            swipeLastPoint = swipeStartPoint
            isSwipe = false
            previousSwipeVelocity = 0
            lastSwipeVelocityTime = now
        } else if gesture.state == .changed {
            swipeLastPoint = gesture.location(in: view)
            let deltaX = swipeLastPoint.x - swipeStartPoint.x
            let deltaY = swipeLastPoint.y - swipeStartPoint.y
            let distance = sqrt(deltaX * deltaX + deltaY * deltaY)
            
            if distance > swipeThresholdPx {
                isSwipe = true
                
                // Track velocity changes during the gesture for acceleration calculation
                let now = Date().timeIntervalSince1970 * 1000
                let nativeVelocity = gesture.velocity(in: view)
                let currentVelocityX = nativeVelocity.x
                let currentVelocityY = nativeVelocity.y
                let currentVelocity = sqrt(currentVelocityX * currentVelocityX + currentVelocityY * currentVelocityY)
                
                if lastSwipeVelocityTime > 0 && now > lastSwipeVelocityTime {
                    let timeDelta = (now - lastSwipeVelocityTime) / 1000.0
                    if timeDelta > 0 {
                        previousSwipeVelocity = currentVelocity
                    }
                }
                lastSwipeVelocityTime = now
            }
        } else if gesture.state == .ended {
            let duration = Date().timeIntervalSince1970 * 1000 - swipeStartTime
            let deltaX = swipeLastPoint.x - swipeStartPoint.x
            let deltaY = swipeLastPoint.y - swipeStartPoint.y
            let distance = sqrt(deltaX * deltaX + deltaY * deltaY)
            
            // Determine if it's a swipe or tap
            // A swipe requires: significant movement (> threshold) AND sufficient duration (>= 100ms)
            // A tap is: small movement OR very quick gesture (< 100ms)
            let isSwipeGesture = distance > swipeThresholdPx && duration >= 100
            
            if isSwipe && isSwipeGesture && duration > 0 {
                    // Use native velocity from UIPanGestureRecognizer (in points per second)
                    let nativeVelocity = gesture.velocity(in: view)
                    let velocityX = nativeVelocity.x
                    let velocityY = nativeVelocity.y
                    let velocity = sqrt(velocityX * velocityX + velocityY * velocityY)
                    
                    // Calculate acceleration as change in velocity over time
                    let acceleration: Double
                    if duration > 50 && previousSwipeVelocity > 0 {
                        // Use velocity change if we tracked it
                        acceleration = (velocity - previousSwipeVelocity) / (duration / 1000.0)
                    } else if duration > 50 {
                        // Fallback: average acceleration assuming constant acceleration from rest
                        // a = 2 * distance / t² (from d = 0.5 * a * t²)
                        let distance = sqrt(deltaX * deltaX + deltaY * deltaY)
                        let durationSeconds = duration / 1000.0
                        acceleration = (2.0 * Double(distance)) / (durationSeconds * durationSeconds)
                    } else {
                        acceleration = 0.0
                    }
                    
                    // Determine swipe direction
                    let direction: String
                    if abs(deltaX) > abs(deltaY) {
                        direction = deltaX > 0 ? "right" : "left"
                    } else {
                        direction = deltaY > 0 ? "down" : "up"
                    }
                    
                    emitSwipeEvent(
                        direction: direction,
                        distancePx: Double(distance),
                        durationMs: Int(duration),
                        velocity: Double(velocity),
                        acceleration: acceleration
                    )
            } else {
                // It's a tap - use actual measured duration from pan gesture
                let tapDuration = Int(duration)
                let longPress = tapDuration >= Int(longPressThresholdMs)
                emitTapEvent(tapDurationMs: tapDuration, longPress: longPress)
            }
            // Reset pan start time
            panStartTimeForTap = 0
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

        let offsetDelta = scrollView.contentOffset.y - lastScrollOffset
        
        // Use native scroll velocity if available (iOS 13+), otherwise calculate from delta
        let velocity: Double
        if #available(iOS 13.0, *) {
            // Use native velocity from scroll view's pan gesture recognizer
            // panGestureRecognizer is non-optional, so we can use it directly
            let panGesture = scrollView.panGestureRecognizer
            let nativeVelocity = panGesture.velocity(in: scrollView)
            velocity = abs(nativeVelocity.y)
        } else {
            velocity = abs(offsetDelta) / timeDelta * 1000.0
        }

        // Calculate acceleration (change in velocity over time)
        let acceleration = previousVelocity > 0 && timeDelta > 0 ? (velocity - previousVelocity) / (timeDelta / 1000.0) : 0.0

        // Determine scroll direction
        let direction: String
        if offsetDelta > 0 {
            direction = "down"
        } else if offsetDelta < 0 {
            direction = "up"
        } else {
            direction = lastScrollDirection ?? "down"
        }

        // Check for direction reversal
        if let lastDir = lastScrollDirection, lastDir != direction {
            hasDirectionReversal = true
        }

        // Emit scroll events
        if velocity > 10.0 {
            emitScrollEvent(
                velocity: velocity,
                acceleration: acceleration,
                direction: direction,
                directionReversal: hasDirectionReversal
            )
            
            hasDirectionReversal = false
        }

        previousVelocity = velocity
        lastScrollTime = now
        lastScrollOffset = scrollView.contentOffset.y
        lastScrollDirection = direction
    }

    // MARK: - Event Emitters

    private func emitScrollEvent(velocity: Double, acceleration: Double, direction: String, directionReversal: Bool) {
        eventHandler?(BehaviorEvent(
            sessionId: "current",
            eventType: "scroll",
            metrics: [
                "velocity": velocity,
                "acceleration": acceleration,
                "direction": direction,
                "direction_reversal": directionReversal
            ]
        ))
    }

    private func emitTapEvent(tapDurationMs: Int, longPress: Bool) {
        tapTimestamps.append(Date().timeIntervalSince1970 * 1000)
        if tapTimestamps.count > 50 {
            tapTimestamps.removeFirst()
        }

        eventHandler?(BehaviorEvent(
            sessionId: "current",
            eventType: "tap",
            metrics: [
                "tap_duration_ms": tapDurationMs,
                "long_press": longPress
            ]
        ))
    }

    private func emitSwipeEvent(direction: String, distancePx: Double, durationMs: Int, velocity: Double, acceleration: Double) {
        eventHandler?(BehaviorEvent(
            sessionId: "current",
            eventType: "swipe",
            metrics: [
                "direction": direction,
                "distance_px": distancePx,
                "duration_ms": durationMs,
                "velocity": velocity,
                "acceleration": acceleration
            ]
        ))
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true // Allow multiple gestures to be recognized simultaneously
    }
}
