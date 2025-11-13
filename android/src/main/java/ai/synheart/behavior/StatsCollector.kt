package ai.synheart.behavior

import java.util.concurrent.ConcurrentHashMap
import java.util.LinkedList

/**
 * Collects and maintains rolling statistics for behavioral signals.
 */
class StatsCollector {

    private val recentEvents = LinkedList<BehaviorEvent>()
    private val maxEvents = 100

    // Rolling metrics
    private var latestTypingCadence: Double? = null
    private var latestInterKeyLatency: Double? = null
    private var latestBurstLength: Int? = null
    private var latestScrollVelocity: Double? = null
    private var latestScrollAcceleration: Double? = null
    private var latestScrollJitter: Double? = null
    private var latestTapRate: Double? = null
    private var latestForegroundDuration: Double? = null
    private var latestIdleGapSeconds: Double? = null
    private var latestStabilityIndex: Double? = null
    private var latestFragmentationIndex: Double? = null

    private val appSwitchTimestamps = LinkedList<Long>()

    @Synchronized
    fun recordEvent(event: BehaviorEvent) {
        recentEvents.add(event)
        while (recentEvents.size > maxEvents) {
            recentEvents.removeFirst()
        }

        // Update metrics based on event type
        when (event.type) {
            "typingCadence" -> {
                latestTypingCadence = event.payload["cadence"] as? Double
                latestInterKeyLatency = event.payload["inter_key_latency"] as? Double
            }
            "typingBurst" -> {
                latestBurstLength = event.payload["burst_length"] as? Int
                latestInterKeyLatency = event.payload["inter_key_latency"] as? Double
            }
            "scrollVelocity" -> {
                latestScrollVelocity = event.payload["velocity"] as? Double
            }
            "scrollAcceleration" -> {
                latestScrollAcceleration = event.payload["acceleration"] as? Double
            }
            "scrollJitter" -> {
                latestScrollJitter = event.payload["jitter"] as? Double
            }
            "tapRate" -> {
                latestTapRate = event.payload["tap_rate"] as? Double
            }
            "foregroundDuration" -> {
                latestForegroundDuration = (event.payload["duration_seconds"] as? Number)?.toDouble()
            }
            "idleGap" -> {
                latestIdleGapSeconds = (event.payload["idle_seconds"] as? Number)?.toDouble()
            }
            "sessionStability" -> {
                latestStabilityIndex = event.payload["stability_index"] as? Double
                latestFragmentationIndex = event.payload["fragmentation_index"] as? Double
            }
            "appSwitch" -> {
                appSwitchTimestamps.add(event.timestamp)
                // Keep only last minute
                val cutoff = System.currentTimeMillis() - 60000
                while (appSwitchTimestamps.isNotEmpty() && appSwitchTimestamps.first() < cutoff) {
                    appSwitchTimestamps.removeFirst()
                }
            }
        }
    }

    @Synchronized
    fun getCurrentStats(): BehaviorStats {
        return BehaviorStats(
            typingCadence = latestTypingCadence,
            interKeyLatency = latestInterKeyLatency,
            burstLength = latestBurstLength,
            scrollVelocity = latestScrollVelocity,
            scrollAcceleration = latestScrollAcceleration,
            scrollJitter = latestScrollJitter,
            tapRate = latestTapRate,
            appSwitchesPerMinute = appSwitchTimestamps.size,
            foregroundDuration = latestForegroundDuration,
            idleGapSeconds = latestIdleGapSeconds,
            stabilityIndex = latestStabilityIndex,
            fragmentationIndex = latestFragmentationIndex,
            timestamp = System.currentTimeMillis()
        )
    }

    @Synchronized
    fun clear() {
        recentEvents.clear()
        appSwitchTimestamps.clear()
        latestTypingCadence = null
        latestInterKeyLatency = null
        latestBurstLength = null
        latestScrollVelocity = null
        latestScrollAcceleration = null
        latestScrollJitter = null
        latestTapRate = null
        latestForegroundDuration = null
        latestIdleGapSeconds = null
        latestStabilityIndex = null
        latestFragmentationIndex = null
    }
}
