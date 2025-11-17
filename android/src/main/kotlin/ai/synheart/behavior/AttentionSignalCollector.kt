package ai.synheart.behavior

import android.os.Handler
import android.os.Looper

/**
 * Collects attention and multitasking signals.
 * Tracks app lifecycle, foreground duration, and session stability.
 */
class AttentionSignalCollector(private var config: BehaviorConfig) {

    private var eventHandler: ((BehaviorEvent) -> Unit)? = null
    private var foregroundStartTime: Long = 0
    private var backgroundStartTime: Long = 0
    private var isInForeground = true
    private var appSwitchCount = 0
    private val handler = Handler(Looper.getMainLooper())

    private var sessionStartTime: Long = 0
    private var totalForegroundTime: Long = 0
    private var totalBackgroundTime: Long = 0

    fun setEventHandler(handler: (BehaviorEvent) -> Unit) {
        this.eventHandler = handler
        sessionStartTime = System.currentTimeMillis()
        foregroundStartTime = sessionStartTime
    }

    fun updateConfig(newConfig: BehaviorConfig) {
        config = newConfig
    }

    fun onAppForegrounded() {
        if (!config.enableAttentionSignals) return

        val now = System.currentTimeMillis()
        foregroundStartTime = now

        if (!isInForeground) {
            isInForeground = true
            appSwitchCount++

            // Calculate background duration
            val backgroundDuration = if (backgroundStartTime > 0) {
                now - backgroundStartTime
            } else 0

            totalBackgroundTime += backgroundDuration

            emitAppSwitch("foreground", backgroundDuration)
        }

        // Start periodic stability checks
        handler.postDelayed(stabilityCheckRunnable, 60000) // Check every minute
    }

    fun onAppBackgrounded() {
        if (!config.enableAttentionSignals) return

        val now = System.currentTimeMillis()
        backgroundStartTime = now

        if (isInForeground) {
            isInForeground = false

            // Calculate foreground duration
            val foregroundDuration = if (foregroundStartTime > 0) {
                now - foregroundStartTime
            } else 0

            totalForegroundTime += foregroundDuration

            emitForegroundDuration(foregroundDuration)
            emitAppSwitch("background", foregroundDuration)
        }

        // Stop stability checks
        handler.removeCallbacks(stabilityCheckRunnable)
    }

    private val stabilityCheckRunnable = object : Runnable {
        override fun run() {
            emitSessionStability()
            handler.postDelayed(this, 60000) // Check again in 1 minute
        }
    }

    private fun emitAppSwitch(direction: String, duration: Long) {
        eventHandler?.invoke(
            BehaviorEvent(
                sessionId = "current",
                timestamp = System.currentTimeMillis(),
                type = "appSwitch",
                payload = mapOf(
                    "direction" to direction,
                    "previous_duration_ms" to duration,
                    "switch_count" to appSwitchCount
                )
            )
        )
    }

    private fun emitForegroundDuration(duration: Long) {
        eventHandler?.invoke(
            BehaviorEvent(
                sessionId = "current",
                timestamp = System.currentTimeMillis(),
                type = "foregroundDuration",
                payload = mapOf(
                    "duration_ms" to duration,
                    "duration_seconds" to duration / 1000.0
                )
            )
        )
    }

    private fun emitSessionStability() {
        val now = System.currentTimeMillis()
        val totalSessionDuration = now - sessionStartTime
        val sessionMinutes = totalSessionDuration / 60000.0

        if (sessionMinutes == 0.0) return

        // Stability index: higher is more stable (fewer switches)
        val stabilityIndex = (1.0 - (appSwitchCount / (sessionMinutes * 10.0))).coerceIn(0.0, 1.0)

        // Fragmentation index: based on background/foreground ratio
        val foregroundRatio = if (totalSessionDuration > 0) {
            totalForegroundTime.toDouble() / totalSessionDuration
        } else 1.0

        val fragmentationIndex = (1.0 - foregroundRatio).coerceIn(0.0, 1.0)

        eventHandler?.invoke(
            BehaviorEvent(
                sessionId = "current",
                timestamp = System.currentTimeMillis(),
                type = "sessionStability",
                payload = mapOf(
                    "stability_index" to stabilityIndex,
                    "fragmentation_index" to fragmentationIndex,
                    "app_switches" to appSwitchCount,
                    "session_minutes" to sessionMinutes,
                    "foreground_ratio" to foregroundRatio
                )
            )
        )
    }

    fun dispose() {
        handler.removeCallbacks(stabilityCheckRunnable)
    }
}
