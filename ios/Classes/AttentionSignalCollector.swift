import Foundation
import UIKit

/// Collects attention and multitasking signals.
/// Tracks app lifecycle, foreground duration, and session stability.
class AttentionSignalCollector {

    private var config: BehaviorConfig
    private var eventHandler: ((BehaviorEvent) -> Void)?
    private var foregroundStartTime: Double = 0
    private var backgroundStartTime: Double = 0
    private var isInForeground: Bool = true
    private var appSwitchCount: Int = 0

    private var sessionStartTime: Double = 0
    private var totalForegroundTime: Double = 0
    private var totalBackgroundTime: Double = 0

    private var stabilityTimer: Timer?

    init(config: BehaviorConfig) {
        self.config = config
    }

    func setEventHandler(_ handler: @escaping (BehaviorEvent) -> Void) {
        self.eventHandler = handler
        sessionStartTime = Date().timeIntervalSince1970 * 1000
        foregroundStartTime = sessionStartTime
    }

    func updateConfig(_ newConfig: BehaviorConfig) {
        config = newConfig
    }

    func startMonitoring() {
        guard config.enableAttentionSignals else { return }

        // Register for app lifecycle notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        // Start periodic stability checks
        startStabilityTimer()
    }

    func dispose() {
        NotificationCenter.default.removeObserver(self)
        stabilityTimer?.invalidate()
        stabilityTimer = nil
    }

    @objc private func appWillEnterForeground() {
        onAppForegrounded()
    }

    @objc private func appDidBecomeActive() {
        onAppForegrounded()
    }

    @objc private func appDidEnterBackground() {
        onAppBackgrounded()
    }

    @objc private func appWillResignActive() {
        onAppBackgrounded()
    }

    func onAppForegrounded() {
        let now = Date().timeIntervalSince1970 * 1000
        foregroundStartTime = now

        if !isInForeground {
            isInForeground = true
            
            let backgroundDuration = backgroundStartTime > 0 ? now - backgroundStartTime : 0
            totalBackgroundTime += backgroundDuration
            
            // Emit app switch event if we had a background period
            // Note: App switch count is incremented when going to background, not when returning
            if backgroundDuration > 0 {
                emitAppSwitchEvent(backgroundDuration: backgroundDuration)
            }
        }

        startStabilityTimer()
    }

    func onAppBackgrounded() {
        let now = Date().timeIntervalSince1970 * 1000
        backgroundStartTime = now

        if isInForeground {
            isInForeground = false

            let foregroundDuration = foregroundStartTime > 0 ? now - foregroundStartTime : 0
            totalForegroundTime += foregroundDuration

            // Count app switch when going to background (this is when the switch actually happens)
            // This ensures app switch is counted even if session is auto-ended while in background
            appSwitchCount += 1

            emitForegroundDuration(duration: foregroundDuration)
        }

        stabilityTimer?.invalidate()
    }

    private func startStabilityTimer() {
        stabilityTimer?.invalidate()
        stabilityTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.emitSessionStability()
        }
    }

    // Emit app switch event so it can break deep focus blocks
    private func emitAppSwitchEvent(backgroundDuration: Double) {
        guard let handler = eventHandler else { return }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        handler(BehaviorEvent(
            sessionId: "current",
            timestamp: formatter.string(from: Date()),
            eventType: "app_switch",
            metrics: [
                "background_duration_ms": Int(backgroundDuration)
            ]
        ))
    }
    
    // Legacy method - kept for compatibility but not used
    private func emitAppSwitch(direction: String, duration: Double) {
        // Use emitAppSwitchEvent instead
    }

    private func emitForegroundDuration(duration: Double) {
        // Foreground duration is computed from session data, not emitted as events
    }

    private func emitSessionStability() {
        // Session stability is computed in session summary, not emitted as events
    }
    
    // Expose app switch count for session tracking
    func getAppSwitchCount() -> Int {
        return appSwitchCount
    }
    
    // Reset app switch count for a new session
    func resetAppSwitchCount() {
        appSwitchCount = 0
    }
}
