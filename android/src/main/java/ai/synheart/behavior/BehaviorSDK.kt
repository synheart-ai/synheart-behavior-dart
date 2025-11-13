package ai.synheart.behavior

import android.app.Activity
import android.content.Context
import android.view.View
import android.view.ViewTreeObserver
import android.view.MotionEvent
import android.os.Handler
import android.os.Looper
import android.view.inputmethod.InputMethodManager
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleObserver
import androidx.lifecycle.OnLifecycleEvent
import androidx.lifecycle.ProcessLifecycleOwner
import java.util.concurrent.ConcurrentHashMap

/**
 * Main BehaviorSDK class for collecting behavioral signals.
 * Privacy-first: No text content, no PII - only timing and interaction patterns.
 */
class BehaviorSDK(
    private val context: Context,
    private val config: BehaviorConfig
) : LifecycleObserver {

    private var eventHandler: ((BehaviorEvent) -> Unit)? = null
    private var currentSessionId: String? = null
    private val sessionData = ConcurrentHashMap<String, SessionData>()
    private val statsCollector = StatsCollector()

    // Signal collectors
    private val inputSignalCollector = InputSignalCollector(config)
    private val attentionSignalCollector = AttentionSignalCollector(config)
    private val gestureCollector = GestureCollector(config)

    // Lifecycle tracking
    private var appInForeground = true
    private var lastInteractionTime = System.currentTimeMillis()
    private val handler = Handler(Looper.getMainLooper())
    private val idleCheckRunnable = object : Runnable {
        override fun run() {
            checkIdleState()
            handler.postDelayed(this, 1000) // Check every second
        }
    }

    init {
        ProcessLifecycleOwner.get().lifecycle.addObserver(this)
    }

    fun initialize() {
        // Start idle detection
        handler.post(idleCheckRunnable)

        // Set up event handlers
        inputSignalCollector.setEventHandler { event ->
            emitEvent(event)
            statsCollector.recordEvent(event)
        }

        attentionSignalCollector.setEventHandler { event ->
            emitEvent(event)
            statsCollector.recordEvent(event)
        }

        gestureCollector.setEventHandler { event ->
            emitEvent(event)
            statsCollector.recordEvent(event)
        }
    }

    fun setEventHandler(handler: (BehaviorEvent) -> Unit) {
        this.eventHandler = handler
    }

    fun startSession(sessionId: String) {
        currentSessionId = sessionId
        sessionData[sessionId] = SessionData(
            sessionId = sessionId,
            startTime = System.currentTimeMillis()
        )
        lastInteractionTime = System.currentTimeMillis()
    }

    fun endSession(sessionId: String): SessionSummary {
        val data = sessionData[sessionId] ?: throw IllegalStateException("Session not found")
        data.endTime = System.currentTimeMillis()

        val summary = SessionSummary(
            sessionId = sessionId,
            startTimestamp = data.startTime,
            endTimestamp = data.endTime,
            duration = data.endTime - data.startTime,
            eventCount = data.eventCount,
            averageTypingCadence = data.totalKeystrokes.toDouble() / ((data.endTime - data.startTime) / 1000.0),
            averageScrollVelocity = if (data.scrollEventCount > 0) data.totalScrollVelocity / data.scrollEventCount else null,
            appSwitchCount = data.appSwitchCount,
            stabilityIndex = calculateStabilityIndex(data),
            fragmentationIndex = calculateFragmentationIndex(data)
        )

        sessionData.remove(sessionId)
        return summary
    }

    fun getCurrentStats(): BehaviorStats {
        return statsCollector.getCurrentStats()
    }

    fun updateConfig(newConfig: BehaviorConfig) {
        inputSignalCollector.updateConfig(newConfig)
        attentionSignalCollector.updateConfig(newConfig)
        gestureCollector.updateConfig(newConfig)
    }

    fun attachToView(view: View) {
        if (config.enableInputSignals) {
            inputSignalCollector.attachToView(view)
            gestureCollector.attachToView(view)
        }
    }

    fun dispose() {
        handler.removeCallbacks(idleCheckRunnable)
        inputSignalCollector.dispose()
        attentionSignalCollector.dispose()
        gestureCollector.dispose()
        ProcessLifecycleOwner.get().lifecycle.removeObserver(this)
    }

    @OnLifecycleEvent(Lifecycle.Event.ON_START)
    fun onAppForegrounded() {
        appInForeground = true
        attentionSignalCollector.onAppForegrounded()

        currentSessionId?.let { sessionId ->
            emitEvent(BehaviorEvent(
                sessionId = sessionId,
                timestamp = System.currentTimeMillis(),
                type = "appSwitch",
                payload = mapOf("event" to "foreground")
            ))
        }
    }

    @OnLifecycleEvent(Lifecycle.Event.ON_STOP)
    fun onAppBackgrounded() {
        appInForeground = false
        attentionSignalCollector.onAppBackgrounded()

        currentSessionId?.let { sessionId ->
            emitEvent(BehaviorEvent(
                sessionId = sessionId,
                timestamp = System.currentTimeMillis(),
                type = "appSwitch",
                payload = mapOf("event" to "background")
            ))
        }
    }

    fun onUserInteraction() {
        lastInteractionTime = System.currentTimeMillis()
    }

    private fun checkIdleState() {
        val idleTime = System.currentTimeMillis() - lastInteractionTime
        val idleSeconds = idleTime / 1000.0

        if (idleSeconds > config.maxIdleGapSeconds && currentSessionId != null) {
            val idleType = when {
                idleSeconds < 3.0 -> "microIdle"
                idleSeconds < 10.0 -> "midIdle"
                else -> "taskDropIdle"
            }

            emitEvent(BehaviorEvent(
                sessionId = currentSessionId!!,
                timestamp = System.currentTimeMillis(),
                type = "idleGap",
                payload = mapOf(
                    "idle_seconds" to idleSeconds,
                    "idle_type" to idleType
                )
            ))
        }
    }

    private fun emitEvent(event: BehaviorEvent) {
        eventHandler?.invoke(event)

        currentSessionId?.let { sessionId ->
            sessionData[sessionId]?.let { data ->
                data.eventCount++

                // Update session-specific metrics
                when (event.type) {
                    "typingCadence", "typingBurst" -> {
                        data.totalKeystrokes += (event.payload["burst_length"] as? Number)?.toInt() ?: 1
                    }
                    "scrollVelocity" -> {
                        data.scrollEventCount++
                        data.totalScrollVelocity += (event.payload["velocity"] as? Number)?.toDouble() ?: 0.0
                    }
                    "appSwitch" -> {
                        data.appSwitchCount++
                    }
                }
            }
        }
    }

    private fun calculateStabilityIndex(data: SessionData): Double {
        // Stability = 1 - (switches / (duration_in_minutes * 10))
        val durationMinutes = (data.endTime - data.startTime) / 60000.0
        if (durationMinutes == 0.0) return 1.0
        val normalized = 1.0 - (data.appSwitchCount / (durationMinutes * 10.0))
        return normalized.coerceIn(0.0, 1.0)
    }

    private fun calculateFragmentationIndex(data: SessionData): Double {
        // Fragmentation based on idle gaps and interruptions
        val totalIdleEvents = data.eventCount // Simplified
        val durationMinutes = (data.endTime - data.startTime) / 60000.0
        if (durationMinutes == 0.0) return 0.0
        return (totalIdleEvents / (durationMinutes * 20.0)).coerceIn(0.0, 1.0)
    }
}

data class BehaviorConfig(
    val enableInputSignals: Boolean = true,
    val enableAttentionSignals: Boolean = true,
    val enableMotionLite: Boolean = false,
    val sessionIdPrefix: String? = null,
    val eventBatchSize: Int = 10,
    val maxIdleGapSeconds: Double = 10.0
)

data class BehaviorEvent(
    val sessionId: String,
    val timestamp: Long,
    val type: String,
    val payload: Map<String, Any>
) {
    fun toMap(): Map<String, Any> = mapOf(
        "session_id" to sessionId,
        "timestamp" to timestamp,
        "type" to type,
        "payload" to payload
    )
}

data class SessionData(
    val sessionId: String,
    val startTime: Long,
    var endTime: Long = 0,
    var eventCount: Int = 0,
    var totalKeystrokes: Int = 0,
    var scrollEventCount: Int = 0,
    var totalScrollVelocity: Double = 0.0,
    var appSwitchCount: Int = 0
)

data class SessionSummary(
    val sessionId: String,
    val startTimestamp: Long,
    val endTimestamp: Long,
    val duration: Long,
    val eventCount: Int,
    val averageTypingCadence: Double?,
    val averageScrollVelocity: Double?,
    val appSwitchCount: Int,
    val stabilityIndex: Double,
    val fragmentationIndex: Double
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "session_id" to sessionId,
        "start_timestamp" to startTimestamp,
        "end_timestamp" to endTimestamp,
        "duration" to duration,
        "event_count" to eventCount,
        "average_typing_cadence" to averageTypingCadence,
        "average_scroll_velocity" to averageScrollVelocity,
        "app_switch_count" to appSwitchCount,
        "stability_index" to stabilityIndex,
        "fragmentation_index" to fragmentationIndex
    )
}

data class BehaviorStats(
    val typingCadence: Double? = null,
    val interKeyLatency: Double? = null,
    val burstLength: Int? = null,
    val scrollVelocity: Double? = null,
    val scrollAcceleration: Double? = null,
    val scrollJitter: Double? = null,
    val tapRate: Double? = null,
    val appSwitchesPerMinute: Int = 0,
    val foregroundDuration: Double? = null,
    val idleGapSeconds: Double? = null,
    val stabilityIndex: Double? = null,
    val fragmentationIndex: Double? = null,
    val timestamp: Long = System.currentTimeMillis()
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "typing_cadence" to typingCadence,
        "inter_key_latency" to interKeyLatency,
        "burst_length" to burstLength,
        "scroll_velocity" to scrollVelocity,
        "scroll_acceleration" to scrollAcceleration,
        "scroll_jitter" to scrollJitter,
        "tap_rate" to tapRate,
        "app_switches_per_minute" to appSwitchesPerMinute,
        "foreground_duration" to foregroundDuration,
        "idle_gap_seconds" to idleGapSeconds,
        "stability_index" to stabilityIndex,
        "fragmentation_index" to fragmentationIndex,
        "timestamp" to timestamp
    )
}
