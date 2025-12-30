import Foundation
import UIKit

/// Collects gesture and scroll signals.
/// Privacy: Only timing and velocity metrics, no content or coordinates.
class GestureCollector: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {

    private var config: BehaviorConfig
    private var eventHandler: ((BehaviorEvent) -> Void)?

    // Scroll tracking - wait until scroll stops before calculating
    private var scrollStartTime: Double = 0
    private var scrollStartPosition: CGFloat = 0
    private var scrollEndPosition: CGFloat = 0
    private var lastScrollPosition: CGFloat = 0
    private var lastScrollTime: Double = 0
    private var lastScrollDirection: String? = nil // "up", "down", "left", "right"
    private var hasDirectionReversal = false
    private var scrollStopTimer: Timer? = nil
    private let scrollStopThresholdMs: Double = 1000 // Wait 1000ms (1s) after last scroll update
    
    // Velocity tracking for scroll
    private var lastScrollVelocityTime: Double = 0
    private var lastScrollPositionDelta: CGFloat = 0
    private var nativeScrollVelocity: Double = 0 // Store native velocity from iOS when available

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
        let currentPosition = scrollView.contentOffset.y

        // If this is the start of a new scroll, initialize tracking
        if scrollStartTime == 0 {
            scrollStartTime = now
            scrollStartPosition = currentPosition
            scrollEndPosition = currentPosition
            lastScrollPosition = currentPosition
            lastScrollTime = now
            hasDirectionReversal = false
            // Determine initial direction (will be updated on first movement)
            lastScrollDirection = "down"
            // Initialize velocity tracking
            lastScrollVelocityTime = now
            lastScrollPositionDelta = 0
        } else {
            // For subsequent updates, determine direction from position change
            let positionChange = currentPosition - lastScrollPosition
            let newDirection: String
            if positionChange > 0 {
                newDirection = "down"
            } else if positionChange < 0 {
                newDirection = "up"
            } else {
                newDirection = lastScrollDirection ?? "down"
            }

            // Check for direction reversal
            if let lastDir = lastScrollDirection, lastDir != newDirection {
                hasDirectionReversal = true
            }

            // Update direction and end position
            if abs(positionChange) > 1.0 {
                lastScrollDirection = newDirection
                lastScrollPosition = currentPosition
            }
            scrollEndPosition = currentPosition
            lastScrollTime = now
            
            // Calculate instantaneous velocity from position change (native-like calculation)
            // This is how iOS calculates velocity internally: delta position / delta time
            if lastScrollVelocityTime > 0 {
                let timeDelta = now - lastScrollVelocityTime
                if timeDelta > 0 && abs(positionChange) > 0.1 {
                    // Instantaneous velocity in pixels per second (native calculation)
                    let instantaneousVelocity = abs(positionChange) / (timeDelta / 1000.0)
                    // Store for use in final calculation
                    lastScrollPositionDelta = positionChange
                }
            }
            lastScrollVelocityTime = now
        }

        // Cancel previous timer and start a new one
        scrollStopTimer?.invalidate()
        scrollStopTimer = Timer.scheduledTimer(withTimeInterval: scrollStopThresholdMs / 1000.0, repeats: false) { [weak self] _ in
            self?.finalizeScroll()
        }
    }
    
    // Get native velocity when user lifts finger (iOS provides this)
    // This is the ONLY place iOS provides native scroll velocity
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        // Store native velocity from iOS (in points per second)
        // This is the actual native velocity API iOS provides
        nativeScrollVelocity = abs(velocity.y)
    }

    private func finalizeScroll() {
        guard scrollStartTime > 0 else { return }

        let now = Date().timeIntervalSince1970 * 1000
        let durationMs = now - scrollStartTime
        let distancePx = abs(scrollEndPosition - scrollStartPosition)

        if durationMs > 0 && distancePx > 0 {
            // Calculate velocity in pixels per second
            // Note: iOS provides native velocity in scrollViewWillEndDragging, but only when
            // the user lifts their finger. For continuous scrolling, we calculate velocity
            // the same way native systems do internally: velocity = distance / time
            // If native velocity is available (from scrollViewWillEndDragging), prefer it
            let velocity: Double
            if nativeScrollVelocity > 0 {
                // Use native velocity from iOS (more accurate for momentum scrolling)
                velocity = min(max(nativeScrollVelocity, 0.0), 10000.0)
            } else {
                // Calculate average velocity (distance / time) - same method native systems use
                velocity = min(max((distancePx / durationMs * 1000.0), 0.0), 10000.0)
            }

            // Calculate acceleration using proper physics formula
            // For constant acceleration from rest: a = 2d/t²
            // where d = distance (pixels), t = time (seconds)
            let durationSeconds = durationMs / 1000.0
            let acceleration = durationSeconds > 0.1
                ? (2.0 * distancePx) / (durationSeconds * durationSeconds)
                : 0.0
            let clampedAcceleration = min(max(acceleration, 0.0), 50000.0)

            // Emit scroll event with calculated metrics
            emitScrollEvent(
                velocity: velocity,
                acceleration: clampedAcceleration,
                direction: lastScrollDirection ?? "down",
                directionReversal: hasDirectionReversal
            )
        }
        
        // Reset velocity tracking
        lastScrollVelocityTime = 0
        lastScrollPositionDelta = 0
        nativeScrollVelocity = 0 // Reset native velocity

        // Reset scroll tracking
        scrollStartTime = 0
        scrollStartPosition = 0
        scrollEndPosition = 0
        lastScrollPosition = 0
        lastScrollTime = 0
        lastScrollDirection = nil
        hasDirectionReversal = false
        scrollStopTimer = nil
        // Reset velocity tracking
        lastScrollVelocityTime = 0
        lastScrollPositionDelta = 0
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
