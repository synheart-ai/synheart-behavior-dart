import Foundation
import UIKit

/// Main BehaviorSDK class for collecting behavioral signals on iOS.
/// Privacy-first: No text content, no PII - only timing and interaction patterns.
public class BehaviorSDK {

    private let config: BehaviorConfig
    private var eventHandler: ((BehaviorEvent) -> Void)?
    private var currentSessionId: String?
    private var sessionData: [String: SessionData] = [:]
    private let statsCollector = StatsCollector()

    // Signal collectors
    private let inputSignalCollector: InputSignalCollector
    private let attentionSignalCollector: AttentionSignalCollector
    private let gestureCollector: GestureCollector
    private let notificationCollector: NotificationCollector

    // Lifecycle tracking
    private var lastInteractionTime = Date()
    private var idleTimer: Timer?

    public init(config: BehaviorConfig) {
        self.config = config
        self.inputSignalCollector = InputSignalCollector(config: config)
        self.attentionSignalCollector = AttentionSignalCollector(config: config)
        self.gestureCollector = GestureCollector(config: config)
        self.notificationCollector = NotificationCollector(config: config)
    }

    public func initialize() {
        // Set up event handlers
        inputSignalCollector.setEventHandler { [weak self] event in
            self?.emitEvent(event)
            self?.statsCollector.recordEvent(event)
        }

        attentionSignalCollector.setEventHandler { [weak self] event in
            self?.emitEvent(event)
            self?.statsCollector.recordEvent(event)
        }

        gestureCollector.setEventHandler { [weak self] event in
            self?.emitEvent(event)
            self?.statsCollector.recordEvent(event)
        }

        notificationCollector.setEventHandler { [weak self] event in
            self?.emitEvent(event)
            self?.statsCollector.recordEvent(event)
        }

        attentionSignalCollector.startMonitoring()
        notificationCollector.startMonitoring()

        // Start idle detection
        startIdleTimer()
    }

    public func setEventHandler(_ handler: @escaping (BehaviorEvent) -> Void) {
        self.eventHandler = handler
    }

    public func startSession(sessionId: String) {
        currentSessionId = sessionId
        sessionData[sessionId] = SessionData(
            sessionId: sessionId,
            startTime: Date().timeIntervalSince1970 * 1000
        )
        lastInteractionTime = Date()
    }

    public func endSession(sessionId: String) throws -> SessionSummary {
        guard var data = sessionData[sessionId] else {
            throw NSError(domain: "BehaviorSDK", code: 404, userInfo: [NSLocalizedDescriptionKey: "Session not found"])
        }

        data.endTime = Date().timeIntervalSince1970 * 1000

        let summary = SessionSummary(
            sessionId: sessionId,
            startTimestamp: Int64(data.startTime),
            endTimestamp: Int64(data.endTime),
            duration: Int64(data.endTime - data.startTime),
            eventCount: data.eventCount,
            averageTypingCadence: data.totalKeystrokes > 0 ? Double(data.totalKeystrokes) / ((data.endTime - data.startTime) / 1000.0) : nil,
            averageScrollVelocity: data.scrollEventCount > 0 ? data.totalScrollVelocity / Double(data.scrollEventCount) : nil,
            appSwitchCount: data.appSwitchCount,
            stabilityIndex: calculateStabilityIndex(data: data),
            fragmentationIndex: calculateFragmentationIndex(data: data)
        )

        sessionData.removeValue(forKey: sessionId)
        return summary
    }

    public func getCurrentStats() -> BehaviorStats {
        return statsCollector.getCurrentStats()
    }

    public func updateConfig(_ newConfig: BehaviorConfig) {
        inputSignalCollector.updateConfig(newConfig)
        attentionSignalCollector.updateConfig(newConfig)
        gestureCollector.updateConfig(newConfig)
        notificationCollector.updateConfig(newConfig)
    }

    public func attachToView(_ view: UIView) {
        if config.enableInputSignals {
            inputSignalCollector.attachToView(view)
            gestureCollector.attachToView(view)
        }
    }

    public func dispose() {
        idleTimer?.invalidate()
        idleTimer = nil
        inputSignalCollector.dispose()
        attentionSignalCollector.dispose()
        gestureCollector.dispose()
        notificationCollector.dispose()
    }

    public func onUserInteraction() {
        lastInteractionTime = Date()
    }

    private func startIdleTimer() {
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkIdleState()
        }
    }

    private func checkIdleState() {
        let idleTime = Date().timeIntervalSince(lastInteractionTime)

        if idleTime > config.maxIdleGapSeconds, let sessionId = currentSessionId {
            let idleType: String
            if idleTime < 3.0 {
                idleType = "microIdle"
            } else if idleTime < 10.0 {
                idleType = "midIdle"
            } else {
                idleType = "taskDropIdle"
            }

            emitEvent(BehaviorEvent(
                sessionId: sessionId,
                timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                type: "idleGap",
                payload: [
                    "idle_seconds": idleTime,
                    "idle_type": idleType
                ]
            ))
        }
    }

    private func emitEvent(_ event: BehaviorEvent) {
        eventHandler?(event)

        if let sessionId = currentSessionId, var data = sessionData[sessionId] {
            data.eventCount += 1

            // Update session-specific metrics
            switch event.type {
            case "typingCadence", "typingBurst":
                if let burstLength = event.payload["burst_length"] as? Int {
                    data.totalKeystrokes += burstLength
                } else {
                    data.totalKeystrokes += 1
                }
            case "scrollVelocity":
                data.scrollEventCount += 1
                if let velocity = event.payload["velocity"] as? Double {
                    data.totalScrollVelocity += velocity
                }
            case "appSwitch":
                data.appSwitchCount += 1
            default:
                break
            }

            sessionData[sessionId] = data
        }
    }

    private func calculateStabilityIndex(data: SessionData) -> Double {
        let durationMinutes = (data.endTime - data.startTime) / 60000.0
        if durationMinutes == 0.0 { return 1.0 }
        let normalized = 1.0 - (Double(data.appSwitchCount) / (durationMinutes * 10.0))
        return max(0.0, min(1.0, normalized))
    }

    private func calculateFragmentationIndex(data: SessionData) -> Double {
        let durationMinutes = (data.endTime - data.startTime) / 60000.0
        if durationMinutes == 0.0 { return 0.0 }
        return max(0.0, min(1.0, Double(data.eventCount) / (durationMinutes * 20.0)))
    }
}

// MARK: - Configuration

public struct BehaviorConfig {
    public let enableInputSignals: Bool
    public let enableAttentionSignals: Bool
    public let enableMotionLite: Bool
    public let sessionIdPrefix: String?
    public let eventBatchSize: Int
    public let maxIdleGapSeconds: Double

    public init(
        enableInputSignals: Bool = true,
        enableAttentionSignals: Bool = true,
        enableMotionLite: Bool = false,
        sessionIdPrefix: String? = nil,
        eventBatchSize: Int = 10,
        maxIdleGapSeconds: Double = 10.0
    ) {
        self.enableInputSignals = enableInputSignals
        self.enableAttentionSignals = enableAttentionSignals
        self.enableMotionLite = enableMotionLite
        self.sessionIdPrefix = sessionIdPrefix
        self.eventBatchSize = eventBatchSize
        self.maxIdleGapSeconds = maxIdleGapSeconds
    }
}

// MARK: - Data Models

public struct BehaviorEvent {
    public let sessionId: String
    public let timestamp: Int64
    public let type: String
    public let payload: [String: Any]

    public func toDictionary() -> [String: Any] {
        return [
            "session_id": sessionId,
            "timestamp": timestamp,
            "type": type,
            "payload": payload
        ]
    }
}

struct SessionData {
    let sessionId: String
    let startTime: Double
    var endTime: Double = 0
    var eventCount: Int = 0
    var totalKeystrokes: Int = 0
    var scrollEventCount: Int = 0
    var totalScrollVelocity: Double = 0.0
    var appSwitchCount: Int = 0
}

public struct SessionSummary {
    public let sessionId: String
    public let startTimestamp: Int64
    public let endTimestamp: Int64
    public let duration: Int64
    public let eventCount: Int
    public let averageTypingCadence: Double?
    public let averageScrollVelocity: Double?
    public let appSwitchCount: Int
    public let stabilityIndex: Double
    public let fragmentationIndex: Double

    public func toDictionary() -> [String: Any?] {
        return [
            "session_id": sessionId,
            "start_timestamp": startTimestamp,
            "end_timestamp": endTimestamp,
            "duration": duration,
            "event_count": eventCount,
            "average_typing_cadence": averageTypingCadence,
            "average_scroll_velocity": averageScrollVelocity,
            "app_switch_count": appSwitchCount,
            "stability_index": stabilityIndex,
            "fragmentation_index": fragmentationIndex
        ]
    }
}

public struct BehaviorStats {
    public let typingCadence: Double?
    public let interKeyLatency: Double?
    public let burstLength: Int?
    public let scrollVelocity: Double?
    public let scrollAcceleration: Double?
    public let scrollJitter: Double?
    public let tapRate: Double?
    public let appSwitchesPerMinute: Int
    public let foregroundDuration: Double?
    public let idleGapSeconds: Double?
    public let stabilityIndex: Double?
    public let fragmentationIndex: Double?
    public let timestamp: Int64

    public func toDictionary() -> [String: Any?] {
        return [
            "typing_cadence": typingCadence,
            "inter_key_latency": interKeyLatency,
            "burst_length": burstLength,
            "scroll_velocity": scrollVelocity,
            "scroll_acceleration": scrollAcceleration,
            "scroll_jitter": scrollJitter,
            "tap_rate": tapRate,
            "app_switches_per_minute": appSwitchesPerMinute,
            "foreground_duration": foregroundDuration,
            "idle_gap_seconds": idleGapSeconds,
            "stability_index": stabilityIndex,
            "fragmentation_index": fragmentationIndex,
            "timestamp": timestamp
        ]
    }
}
