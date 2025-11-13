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
            appSwitchCount += 1

            let backgroundDuration = backgroundStartTime > 0 ? now - backgroundStartTime : 0
            totalBackgroundTime += backgroundDuration

            emitAppSwitch(direction: "foreground", duration: backgroundDuration)
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

            emitForegroundDuration(duration: foregroundDuration)
            emitAppSwitch(direction: "background", duration: foregroundDuration)
        }

        stabilityTimer?.invalidate()
    }

    private func startStabilityTimer() {
        stabilityTimer?.invalidate()
        stabilityTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.emitSessionStability()
        }
    }

    private func emitAppSwitch(direction: String, duration: Double) {
        eventHandler?(BehaviorEvent(
            sessionId: "current",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            type: "appSwitch",
            payload: [
                "direction": direction,
                "previous_duration_ms": duration,
                "switch_count": appSwitchCount
            ]
        ))
    }

    private func emitForegroundDuration(duration: Double) {
        eventHandler?(BehaviorEvent(
            sessionId: "current",
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            type: "foregroundDuration",
            payload: [
                "duration_ms": duration,
                "duration_seconds": duration / 1000.0
            ]
        ))
    }

    private func emitSessionStability() {
        let now = Date().timeIntervalSince1970 * 1000
        let totalSessionDuration = now - sessionStartTime
        let sessionMinutes = totalSessionDuration / 60000.0

        guard sessionMinutes > 0 else { return }

        // Stability index: higher is more stable (fewer switches)
        let stabilityIndex = max(0.0, min(1.0, 1.0 - (Double(appSwitchCount) / (sessionMinutes * 10.0))))

        // Fragmentation index: based on background/foreground ratio
        let foregroundRatio = totalSessionDuration > 0 ? totalForegroundTime / totalSessionDuration : 1.0
        let fragmentationIndex = max(0.0, min(1.0, 1.0 - foregroundRatio))

        eventHandler?(BehaviorEvent(
            sessionId: "current",
            timestamp: Int64(now),
            type: "sessionStability",
            payload: [
                "stability_index": stabilityIndex,
                "fragmentation_index": fragmentationIndex,
                "app_switches": appSwitchCount,
                "session_minutes": sessionMinutes,
                "foreground_ratio": foregroundRatio
            ]
        ))
    }
}
