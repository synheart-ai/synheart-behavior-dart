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
            appSwitchCount++

            // Calculate background duration
            val backgroundDuration =
                    if (backgroundStartTime > 0) {
                        now - backgroundStartTime
                    } else 0

            totalBackgroundTime += backgroundDuration

            // App switches are tracked in session data, not emitted as events
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

            // Foreground duration and app switches are tracked in session data
        }

        // Stability is computed in session summary
    }

    // Expose app switch count for session tracking
    fun getAppSwitchCount(): Int {
        return appSwitchCount
    }

    fun dispose() {
        // No callbacks to remove - stability is computed in session summary
    }
}
