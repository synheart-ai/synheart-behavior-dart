package ai.synheart.behavior

import java.time.Instant
import java.util.LinkedList

/** Collects and maintains rolling statistics for behavioral signals. */
class StatsCollector {

    private val recentEvents = LinkedList<BehaviorEvent>()
    private val maxEvents = 100

    // Rolling metrics
    // Typing metrics are now tracked as separate events, not rolling stats
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

        // Update metrics based on new event types
        when (event.eventType) {
            "tap" -> {
                // Tap events - extract tap rate from metrics
                val tapDuration = (event.metrics["tap_duration_ms"] as? Number)?.toInt() ?: 0
                // Calculate tap rate from recent tap events
                val recentTaps = recentEvents.filter { it.eventType == "tap" }
                if (recentTaps.size > 1) {
                    try {
                        val firstTapTime =
                                Instant.parse(recentTaps.first().timestamp).toEpochMilli()
                        val lastTapTime = Instant.parse(recentTaps.last().timestamp).toEpochMilli()
                        val timeSpan = (lastTapTime - firstTapTime) / 1000.0
                        latestTapRate = if (timeSpan > 0) recentTaps.size / timeSpan else null
                    } catch (e: Exception) {
                        latestTapRate = null
                    }
                }
            }
            "scroll" -> {
                latestScrollVelocity = (event.metrics["velocity"] as? Number)?.toDouble()
                latestScrollAcceleration = (event.metrics["acceleration"] as? Number)?.toDouble()
            }
            "swipe" -> {
                // Swipe events - similar to scroll
                latestScrollVelocity = (event.metrics["velocity"] as? Number)?.toDouble()
            }
            "notification" -> {
                // Track notification events
            }
            "call" -> {
                // Track call events
            }
            "typing" -> {
                // Typing events are tracked separately in session summaries
                // No rolling stats needed for typing
            }
        }
    }

    @Synchronized
    fun getCurrentStats(): BehaviorStats {
        return BehaviorStats(
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
