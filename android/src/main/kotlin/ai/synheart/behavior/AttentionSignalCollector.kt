package ai.synheart.behavior

import android.os.Handler
import android.os.Looper

/**
 * Collects attention and multitasking signals. Tracks app lifecycle, foreground duration, and
 * session stability.
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

            // Calculate background duration
            val backgroundDuration =
                    if (backgroundStartTime > 0) {
                        now - backgroundStartTime
                    } else 0

            totalBackgroundTime += backgroundDuration

            // Emit app switch event if we had a background period
            // Note: App switch count is incremented when going to background, not when returning
            if (backgroundDuration > 0) {
                emitAppSwitchEvent(backgroundDuration)
            }
        }

        // Stability is computed in session summary, not emitted as events
    }

    fun onAppBackgrounded() {
        if (!config.enableAttentionSignals) return

        val now = System.currentTimeMillis()
        backgroundStartTime = now

        if (isInForeground) {
            isInForeground = false

            // Calculate foreground duration
            val foregroundDuration =
                    if (foregroundStartTime > 0) {
                        now - foregroundStartTime
                    } else 0

            totalForegroundTime += foregroundDuration

            // Count app switch when going to background (this is when the switch actually happens)
            // This ensures app switch is counted even if session is auto-ended while in background
            appSwitchCount++
        }

        // Stability is computed in session summary
    }

    // Expose app switch count for session tracking
    fun getAppSwitchCount(): Int {
        return appSwitchCount
    }

    // Reset app switch count for a new session
    fun resetAppSwitchCount() {
        appSwitchCount = 0
    }

    private fun emitAppSwitchEvent(backgroundDuration: Long) {
        if (eventHandler != null) {
            val instant = java.time.Instant.now()
            eventHandler?.invoke(
                    BehaviorEvent(
                            sessionId = "current",
                            timestamp = instant.toString(),
                            eventType = "app_switch",
                            metrics = mapOf("background_duration_ms" to backgroundDuration.toInt())
                    )
            )
        }
    }

    fun dispose() {
        // No callbacks to remove - stability is computed in session summary
    }
}
