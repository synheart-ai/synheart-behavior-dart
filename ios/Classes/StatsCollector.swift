import Foundation

/// Collects and maintains rolling statistics for behavioral signals.
class StatsCollector {

    private var recentEvents: [BehaviorEvent] = []
    private let maxEvents = 100
    private let queue = DispatchQueue(label: "ai.synheart.behavior.stats", attributes: .concurrent)

    // Rolling metrics
    private var latestTypingCadence: Double?
    private var latestInterKeyLatency: Double?
    private var latestBurstLength: Int?
    private var latestScrollVelocity: Double?
    private var latestScrollAcceleration: Double?
    private var latestScrollJitter: Double?
    private var latestTapRate: Double?
    private var latestForegroundDuration: Double?
    private var latestIdleGapSeconds: Double?
    private var latestStabilityIndex: Double?
    private var latestFragmentationIndex: Double?

    private var appSwitchTimestamps: [Double] = []

    func recordEvent(_ event: BehaviorEvent) {
        queue.async(flags: .barrier) {
            self.recentEvents.append(event)
            if self.recentEvents.count > self.maxEvents {
                self.recentEvents.removeFirst()
            }

            // Update metrics based on event type
            switch event.type {
            case "typingCadence":
                self.latestTypingCadence = event.payload["cadence"] as? Double
                self.latestInterKeyLatency = event.payload["inter_key_latency"] as? Double

            case "typingBurst":
                self.latestBurstLength = event.payload["burst_length"] as? Int
                self.latestInterKeyLatency = event.payload["inter_key_latency"] as? Double

            case "scrollVelocity":
                self.latestScrollVelocity = event.payload["velocity"] as? Double

            case "scrollAcceleration":
                self.latestScrollAcceleration = event.payload["acceleration"] as? Double

            case "scrollJitter":
                self.latestScrollJitter = event.payload["jitter"] as? Double

            case "tapRate":
                self.latestTapRate = event.payload["tap_rate"] as? Double

            case "foregroundDuration":
                if let durationSeconds = event.payload["duration_seconds"] as? Double {
                    self.latestForegroundDuration = durationSeconds
                } else if let durationMs = event.payload["duration_ms"] as? Double {
                    self.latestForegroundDuration = durationMs / 1000.0
                }

            case "idleGap":
                if let idleSeconds = event.payload["idle_seconds"] as? Double {
                    self.latestIdleGapSeconds = idleSeconds
                }

            case "sessionStability":
                self.latestStabilityIndex = event.payload["stability_index"] as? Double
                self.latestFragmentationIndex = event.payload["fragmentation_index"] as? Double

            case "appSwitch":
                let timestamp = Double(event.timestamp)
                self.appSwitchTimestamps.append(timestamp)

                // Keep only last minute
                let cutoff = Date().timeIntervalSince1970 * 1000 - 60000
                self.appSwitchTimestamps = self.appSwitchTimestamps.filter { $0 >= cutoff }

            default:
                break
            }
        }
    }

    func getCurrentStats() -> BehaviorStats {
        return queue.sync {
            return BehaviorStats(
                typingCadence: latestTypingCadence,
                interKeyLatency: latestInterKeyLatency,
                burstLength: latestBurstLength,
                scrollVelocity: latestScrollVelocity,
                scrollAcceleration: latestScrollAcceleration,
                scrollJitter: latestScrollJitter,
                tapRate: latestTapRate,
                appSwitchesPerMinute: appSwitchTimestamps.count,
                foregroundDuration: latestForegroundDuration,
                idleGapSeconds: latestIdleGapSeconds,
                stabilityIndex: latestStabilityIndex,
                fragmentationIndex: latestFragmentationIndex,
                timestamp: Int64(Date().timeIntervalSince1970 * 1000)
            )
        }
    }

    func clear() {
        queue.async(flags: .barrier) {
            self.recentEvents.removeAll()
            self.appSwitchTimestamps.removeAll()
            self.latestTypingCadence = nil
            self.latestInterKeyLatency = nil
            self.latestBurstLength = nil
            self.latestScrollVelocity = nil
            self.latestScrollAcceleration = nil
            self.latestScrollJitter = nil
            self.latestTapRate = nil
            self.latestForegroundDuration = nil
            self.latestIdleGapSeconds = nil
            self.latestStabilityIndex = nil
            self.latestFragmentationIndex = nil
        }
    }
}
