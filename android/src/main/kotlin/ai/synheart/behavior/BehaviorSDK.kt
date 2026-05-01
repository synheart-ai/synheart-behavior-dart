package ai.synheart.behavior

import android.content.Context
import android.content.res.Configuration
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.View
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleObserver
import androidx.lifecycle.OnLifecycleEvent
import androidx.lifecycle.ProcessLifecycleOwner
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap

/**
 * Main BehaviorSDK class for collecting behavioral signals. Privacy-first: No text content, no PII
 * - only timing and interaction patterns.
 */
class BehaviorSDK(private val context: Context, private val config: BehaviorConfig) :
        LifecycleObserver {

    private var eventHandler: ((BehaviorEvent) -> Unit)? = null
    private var motionSampleBatchHandler: ((List<Map<String, Any>>) -> Unit)? = null
    private var currentSessionId: String? = null
    private val sessionData = ConcurrentHashMap<String, SessionData>()
    private val statsCollector = StatsCollector()

    // Signal collectors
    private val inputSignalCollector = InputSignalCollector(config)
    private val attentionSignalCollector = AttentionSignalCollector(config)
    private val gestureCollector = GestureCollector(config)
    private val notificationCollector = NotificationCollector(config)
    private val callCollector = CallCollector(context, config)
    private val motionSignalCollector = MotionSignalCollector(context, config)

    // Lifecycle tracking
    private var appInForeground = true
    private var lastInteractionTime = System.currentTimeMillis()
    private var lastAppUseTime: Long? = null // For session spacing calculation
    private val handler = Handler(Looper.getMainLooper())

    // Device context tracking
    private var startScreenBrightness: Float = 0f
    private var startOrientation: Int = Configuration.ORIENTATION_PORTRAIT
    private var lastOrientation: Int =
            Configuration.ORIENTATION_PORTRAIT // Track last orientation to detect all changes
    private var orientationChangeCount: Int = 0

    // System state tracking
    private var startInternetState: Boolean = false
    private var startDoNotDisturb: Boolean = false
    private var startCharging: Boolean = false
    private val idleCheckRunnable =
            object : Runnable {
                override fun run() {
                    checkIdleState()
                    checkOrientationChange() // Also check orientation changes
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
            android.util.Log.d(
                    "BehaviorSDK",
                    "InputSignalCollector event received: eventType=${event.eventType}, sessionId=${event.sessionId}, currentSessionId=$currentSessionId"
            )
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

        notificationCollector.setEventHandler { event ->
            emitEvent(event)
            statsCollector.recordEvent(event)
        }

        callCollector.setEventHandler { event ->
            emitEvent(event)
            statsCollector.recordEvent(event)
        }

        // Register notification collector for the service.
        // Multiple SDK instances (main app + background worker) can coexist,
        // so we must register/unregister without clobbering others.
        SynheartNotificationListenerService.setNotificationCollector(notificationCollector)

        android.util.Log.d(
                "BehaviorSDK",
                "Notification collector set for service. Collector instance: ${notificationCollector.hashCode()}"
        )

        // Start call monitoring
        callCollector.startMonitoring()
    }

    fun setEventHandler(handler: (BehaviorEvent) -> Unit) {
        this.eventHandler = handler
    }

    /**
     * Receive 1-second batches of raw 50 Hz accel samples for the runtime to
     * consume via `push_accel`. Each entry is
     * `{"ts_ms": Long, "ax": Double, "ay": Double, "az": Double}`. Only fires
     * when [BehaviorConfig.emitRawMotionSamples] is `true`.
     */
    fun setMotionSampleBatchHandler(handler: (List<Map<String, Any>>) -> Unit) {
        this.motionSampleBatchHandler = handler
        motionSignalCollector.setRawSampleBatchHandler { batch ->
            this.motionSampleBatchHandler?.invoke(batch)
        }
    }

    fun startSession(sessionId: String) {
        // Clear previous session data when starting a new session
        // This ensures data persists until the next session starts, allowing
        // calculateMetricsForTimeRange to access it for ended sessions
        val previousSessionId = currentSessionId
        if (previousSessionId != null && previousSessionId != sessionId) {
            sessionData.remove(previousSessionId)
        }

        currentSessionId = sessionId
        val now = System.currentTimeMillis()

        // Reset app switch count for new session
        attentionSignalCollector.resetAppSwitchCount()

        // Capture device context at session start
        startScreenBrightness = getScreenBrightness()
        startOrientation = context.resources.configuration.orientation
        lastOrientation = startOrientation // Initialize last orientation to start orientation
        orientationChangeCount = 0

        // Capture system state at session start
        startInternetState = isInternetConnected()
        startDoNotDisturb = isDoNotDisturbEnabled()
        startCharging = isCharging()

        // Calculate session spacing (time between end of previous session and start of current
        // session)
        val sessionSpacing =
                if (lastAppUseTime != null) {
                    now - lastAppUseTime!!
                } else {
                    0L
                }

        sessionData[sessionId] =
                SessionData(
                        sessionId = sessionId,
                        startTime = now,
                        sessionSpacing = sessionSpacing,
                        startScreenBrightness = startScreenBrightness,
                        startOrientation = startOrientation,
                        startInternetState = startInternetState,
                        startDoNotDisturb = startDoNotDisturb,
                        startCharging = startCharging
                )

        lastInteractionTime = now
        // Don't update lastAppUseTime here - it will be updated when session ends

        // Start motion data collection if enabled
        motionSignalCollector.startSession(now)

        // Register orientation change listener
        registerOrientationListener()
    }

    private fun getScreenBrightness(): Float {
        return try {
            val brightness =
                    Settings.System.getInt(
                            context.contentResolver,
                            Settings.System.SCREEN_BRIGHTNESS
                    )
            brightness / 255f // Normalize to 0.0-1.0
        } catch (e: Exception) {
            0.5f // Default
        }
    }

    private fun isInternetConnected(): Boolean {
        return try {
            val connectivityManager =
                    context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val network = connectivityManager.activeNetwork ?: return false
            val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        } catch (e: SecurityException) {
            // Permission not granted, return false
            android.util.Log.w(
                    "BehaviorSDK",
                    "ACCESS_NETWORK_STATE permission not granted: ${e.message}"
            )
            false
        } catch (e: Exception) {
            android.util.Log.w("BehaviorSDK", "Error checking internet connectivity: ${e.message}")
            false
        }
    }

    private fun isDoNotDisturbEnabled(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val notificationManager =
                        context.getSystemService(Context.NOTIFICATION_SERVICE) as
                                android.app.NotificationManager
                // Reading interruption filter doesn't require special permission
                // Only modifying DND requires ACCESS_NOTIFICATION_POLICY
                val filter = notificationManager.currentInterruptionFilter
                // INTERRUPTION_FILTER_NONE = DND is fully enabled (all notifications suppressed)
                // INTERRUPTION_FILTER_PRIORITY = Only priority notifications allowed (partial DND)
                // INTERRUPTION_FILTER_ALARMS = Only alarms allowed (partial DND)
                // INTERRUPTION_FILTER_ALL = No restrictions (DND off)
                filter == android.app.NotificationManager.INTERRUPTION_FILTER_NONE ||
                        filter == android.app.NotificationManager.INTERRUPTION_FILTER_PRIORITY ||
                        filter == android.app.NotificationManager.INTERRUPTION_FILTER_ALARMS
            } catch (e: Exception) {
                android.util.Log.w("BehaviorSDK", "Error checking DND status: ${e.message}")
                false
            }
        } else {
            false
        }
    }

    private fun isCharging(): Boolean {
        return try {
            val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            val status = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_STATUS)
            status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL
        } catch (e: Exception) {
            android.util.Log.w("BehaviorSDK", "Error checking charging status: ${e.message}")
            false
        }
    }

    private fun registerOrientationListener() {
        // Track orientation changes by checking periodically
        // Since we can't directly listen to configuration changes in the plugin,
        // we'll check orientation changes in the idle check runnable
        // Orientation changes will be detected when onConfigurationChanged is called
        // from the plugin, or we can check periodically
    }

    // Check orientation changes periodically (called every second from idle check)
    // This ensures we detect orientation changes even if onConfigurationChanged isn't called
    private fun checkOrientationChange() {
        val currentOrientation = context.resources.configuration.orientation
        if (currentOrientation != lastOrientation &&
                        currentOrientation != Configuration.ORIENTATION_UNDEFINED &&
                        currentSessionId != null
        ) {
            orientationChangeCount++
            lastOrientation = currentOrientation
            sessionData[currentSessionId]?.let { data ->
                data.orientationChangeCount = orientationChangeCount
            }
            android.util.Log.d(
                    "BehaviorSDK",
                    "Orientation changed: count=$orientationChangeCount, current=$currentOrientation"
            )
        }
    }

    fun onConfigurationChanged(newConfig: Configuration) {
        val currentOrientation = newConfig.orientation
        // Count orientation changes by comparing with last orientation, not just start orientation
        // This ensures we count all changes (portrait->landscape->portrait = 2 changes)
        if (currentOrientation != lastOrientation &&
                        currentOrientation != Configuration.ORIENTATION_UNDEFINED &&
                        currentSessionId != null
        ) {
            orientationChangeCount++
            lastOrientation = currentOrientation // Update last orientation
            sessionData[currentSessionId]?.let { data ->
                data.orientationChangeCount = orientationChangeCount
            }
            android.util.Log.d(
                    "BehaviorSDK",
                    "Orientation changed: count=$orientationChangeCount, current=$currentOrientation"
            )
        }
    }

    fun endSession(sessionId: String): Map<String, Any> {
        val data = sessionData[sessionId] ?: throw IllegalStateException("Session not found")

        // Sync app switch count from AttentionSignalCollector before ending session
        val currentAppSwitchCount = attentionSignalCollector.getAppSwitchCount()
        if (currentAppSwitchCount > data.appSwitchCount) {
            data.appSwitchCount = currentAppSwitchCount
        }

        data.endTime = System.currentTimeMillis()

        // Update lastAppUseTime to session end time for next session's spacing calculation
        // Session spacing = time between end_session and start_session
        lastAppUseTime = data.endTime

        val duration = data.endTime - data.startTime
        val durationSeconds = duration / 1000.0
        val microSession = durationSeconds < 30.0 // Micro session threshold: <30s

        // Get OS version
        val osVersion = "Android ${Build.VERSION.RELEASE}"

        // Get app ID (package name)
        val appId = context.packageName

        // Get app name from package manager
        val appName =
                try {
                    val packageManager = context.packageManager
                    val applicationInfo = packageManager.getApplicationInfo(appId, 0)
                    packageManager.getApplicationLabel(applicationInfo).toString()
                } catch (e: Exception) {
                    appId // Fallback to package name if unable to get app name
                }

        // Calculate average screen brightness (start + end) / 2
        val endScreenBrightness = getScreenBrightness()
        val avgScreenBrightness = (data.startScreenBrightness + endScreenBrightness) / 2.0

        // Get orientation string
        val startOrientationStr =
                when (data.startOrientation) {
                    Configuration.ORIENTATION_LANDSCAPE -> "landscape"
                    else -> "portrait"
                }

        // Get system state at end
        val endInternetState = isInternetConnected()
        val endDoNotDisturb = isDoNotDisturbEnabled()
        val endCharging = isCharging()

        // Compute notification summary from events
        val notificationEvents = data.events.filter { it.eventType == "notification" }
        val notificationCount = notificationEvents.size
        val notificationIgnored = notificationEvents.count { it.metrics["action"] == "ignored" }
        val notificationOpened = notificationEvents.count { it.metrics["action"] == "opened" }
        val notificationIgnoreRate =
                if (notificationCount > 0) {
                    notificationIgnored.toDouble() / notificationCount
                } else 0.0

        // Compute notification clustering index (simplified: based on time distribution)
        val notificationClusteringIndex = computeNotificationClusteringIndex(notificationEvents)

        // Compute call summary
        val callEvents = data.events.filter { it.eventType == "call" }
        val callCount = callEvents.size
        val callIgnored = callEvents.count { it.metrics["action"] == "ignored" }

        // Compute clipboard summary
        val clipboardEvents = data.events.filter { it.eventType == "clipboard" }
        val clipboardCount = clipboardEvents.size
        val clipboardCopyCount = clipboardEvents.count { it.metrics["action"] == "copy" }
        val clipboardPasteCount = clipboardEvents.count { it.metrics["action"] == "paste" }
        val clipboardCutCount = clipboardEvents.count { it.metrics["action"] == "cut" }

        // Compute behavioral metrics from events
        val behavioralMetrics = computeBehavioralMetricsFromEvents(data, duration, notificationCount, callCount)

        // Stop motion collection. Raw accel batches are pushed to the runtime
        // as they're collected (Phase 3); session summary no longer carries
        // motion-state or motion-feature payloads (RFC-MOTION-STATE-0001 §6.3).
        motionSignalCollector.stopSession()

        // Build comprehensive summary
        val summaryBase =
                mapOf(
                        "session_id" to sessionId,
                        "start_at" to Instant.ofEpochMilli(data.startTime).toString(),
                        "end_at" to Instant.ofEpochMilli(data.endTime).toString(),
                        "micro_session" to microSession,
                        "OS" to osVersion,
                        "app_id" to appId,
                        "app_name" to appName,
                        "session_spacing" to data.sessionSpacing,
                        "device_context" to
                                mapOf(
                                        "avg_screen_brightness" to avgScreenBrightness,
                                        "start_orientation" to startOrientationStr,
                                        "orientation_changes" to data.orientationChangeCount
                                ),
                        "activity_summary" to
                                mapOf(
                                        "total_events" to data.eventCount,
                                        "app_switch_count" to data.appSwitchCount
                                ),
                        "behavioral_metrics" to behavioralMetrics,
                        "notification_summary" to
                                mapOf(
                                        "notification_count" to notificationCount,
                                        "notification_ignored" to notificationIgnored,
                                        "notification_ignore_rate" to notificationIgnoreRate,
                                        "notification_clustering_index" to
                                                notificationClusteringIndex,
                                        "call_count" to callCount,
                                        "call_ignored" to callIgnored
                                ),
                        "clipboard_summary" to
                                mapOf(
                                        "clipboard_count" to clipboardCount,
                                        "clipboard_copy_count" to clipboardCopyCount,
                                        "clipboard_paste_count" to clipboardPasteCount,
                                        "clipboard_cut_count" to clipboardCutCount
                                ),
                        "system_state" to
                                mapOf(
                                        "internet_state" to endInternetState,
                                        "do_not_disturb" to endDoNotDisturb,
                                        "charging" to endCharging
                                )
                )

        var summary = summaryBase

        // Add typing session summary if available from behavioral metrics
        val typingSummary = behavioralMetrics["typing_session_summary"] as? Map<String, Any>
        if (typingSummary != null && typingSummary.isNotEmpty()) {
            summary = summary + mapOf("typing_session_summary" to typingSummary)
        }

        // Don't remove sessionData here - it will be cleared when the next session starts
        // This allows calculateMetricsForTimeRange to access data for ended sessions
        return summary
    }

    private fun computeNotificationClusteringIndex(
            notificationEvents: List<BehaviorEvent>
    ): Double {
        if (notificationEvents.size < 2) return 0.0

        // Compute time intervals between notifications
        val intervals = mutableListOf<Long>()
        for (i in 1 until notificationEvents.size) {
            try {
                val prevTime = Instant.parse(notificationEvents[i - 1].timestamp).toEpochMilli()
                val currTime = Instant.parse(notificationEvents[i].timestamp).toEpochMilli()
                intervals.add(currTime - prevTime)
            } catch (e: Exception) {
                // Skip invalid timestamps
            }
        }

        if (intervals.size == 0) return 0.0

        // Compute coefficient of variation (lower CV = more clustered)
        val mean = intervals.average()
        if (mean == 0.0) return 0.0

        val variance = intervals.map { (it - mean) * (it - mean) }.average()
        val stdDev = kotlin.math.sqrt(variance)
        val cv = stdDev / mean

        // Clustering index: 1 - normalized CV (higher = more clustered)
        return (1.0 - (cv / 10.0).coerceIn(0.0, 1.0)).coerceIn(0.0, 1.0)
    }

    /**
     * Compute behavioral metrics from session events.
     *
     * Returns a map of behavioral metric keys to values, computed from the raw events.
     */
    private fun computeBehavioralMetricsFromEvents(
            data: SessionData,
            durationMs: Long,
            notificationCount: Int,
            callCount: Int
    ): Map<String, Any> {
        val durationSeconds = durationMs / 1000.0
        if (durationSeconds <= 0) {
            return mapOf(
                "interaction_intensity" to 0.0,
                "task_switch_rate" to 0.0,
                "task_switch_cost" to 0,
                "idle_time_ratio" to 0.0,
                "active_time_ratio" to 0.0,
                "notification_load" to 0.0,
                "burstiness" to 0.0,
                "behavioral_distraction_score" to 0.0,
                "focus_hint" to 0.0,
                "fragmented_idle_ratio" to 0.0,
                "scroll_jitter_rate" to 0.0,
                "deep_focus_blocks" to emptyList<Map<String, Any>>()
            )
        }

        // Calculate interaction intensity from event counts
        val tapEvents = data.events.filter { it.eventType == "tap" }
        val scrollEvents = data.events.filter { it.eventType == "scroll" }
        val typingEvents = data.events.filter { it.eventType == "typing" }
        val totalInteractions = tapEvents.size + scrollEvents.size + typingEvents.size
        val interactionIntensity = (totalInteractions / durationSeconds).coerceIn(0.0, 1.0)

        // Task switch rate
        val taskSwitchRate = if (durationSeconds > 0) {
            (data.appSwitchCount / (durationSeconds / 60.0)).coerceIn(0.0, 100.0)
        } else 0.0

        // Estimate idle time from gaps between events
        val sortedEvents = data.events.sortedBy { it.timestamp }
        var totalIdleMs = 0L
        val idleThresholdMs = 5000L // 5 second idle threshold
        for (i in 1 until sortedEvents.size) {
            try {
                val prevTime = Instant.parse(sortedEvents[i - 1].timestamp).toEpochMilli()
                val currTime = Instant.parse(sortedEvents[i].timestamp).toEpochMilli()
                val gap = currTime - prevTime
                if (gap > idleThresholdMs) {
                    totalIdleMs += gap
                }
            } catch (e: Exception) {
                // Skip invalid timestamps
            }
        }
        val idleTimeRatio = if (durationMs > 0) (totalIdleMs.toDouble() / durationMs).coerceIn(0.0, 1.0) else 0.0
        val activeTimeRatio = 1.0 - idleTimeRatio

        // Notification load
        val notificationLoad = if (durationSeconds > 0) {
            (notificationCount / (durationSeconds / 60.0)).coerceIn(0.0, 1.0)
        } else 0.0

        // Burstiness: (sigma - mu) / (sigma + mu) remapped to [0,1]
        val burstiness = if (sortedEvents.size >= 2) {
            val intervals = mutableListOf<Double>()
            for (i in 1 until sortedEvents.size) {
                try {
                    val prevTime = Instant.parse(sortedEvents[i - 1].timestamp).toEpochMilli()
                    val currTime = Instant.parse(sortedEvents[i].timestamp).toEpochMilli()
                    intervals.add((currTime - prevTime).toDouble())
                } catch (e: Exception) {
                    // Skip
                }
            }
            if (intervals.isNotEmpty()) {
                val mean = intervals.average()
                val variance = intervals.map { (it - mean) * (it - mean) }.average()
                val stdDev = kotlin.math.sqrt(variance)
                if (mean + stdDev > 0) {
                    ((stdDev - mean) / (stdDev + mean) + 1.0) / 2.0 // Remap from [-1,1] to [0,1]
                } else 0.0
            } else 0.0
        } else 0.0

        // Scroll jitter rate
        val scrollJitterRate = if (scrollEvents.size >= 2) {
            val velocities = scrollEvents.mapNotNull {
                (it.metrics["velocity"] as? Number)?.toDouble()
            }
            if (velocities.size >= 2) {
                val diffs = velocities.zipWithNext().map { kotlin.math.abs(it.second - it.first) }
                val avgVelocity = velocities.average()
                if (avgVelocity > 0) (diffs.average() / avgVelocity).coerceIn(0.0, 1.0) else 0.0
            } else 0.0
        } else 0.0

        return mapOf(
            "interaction_intensity" to interactionIntensity,
            "task_switch_rate" to taskSwitchRate,
            "task_switch_cost" to 0, // Requires more sophisticated measurement
            "idle_time_ratio" to idleTimeRatio,
            "active_time_ratio" to activeTimeRatio,
            "notification_load" to notificationLoad,
            "burstiness" to burstiness,
            "behavioral_distraction_score" to 0.0, // Requires ML model
            "focus_hint" to 0.0, // Requires ML model
            "fragmented_idle_ratio" to 0.0,
            "scroll_jitter_rate" to scrollJitterRate,
            "deep_focus_blocks" to emptyList<Map<String, Any>>()
        )
    }

    fun getCurrentStats(): BehaviorStats {
        return statsCollector.getCurrentStats()
    }

    fun calculateMetricsForTimeRange(
            startTimestampMs: Long,
            endTimestampMs: Long,
            sessionId: String?
    ): Map<String, Any?> {
        // Determine which session to use
        val sessionIdToUse =
                sessionId
                        ?: currentSessionId
                                ?: throw IllegalStateException(
                                "No active session and no sessionId provided"
                        )

        // Get session data (may be null if session has ended)
        val sessionDataEntry = sessionData[sessionIdToUse]

        // Validate time range is within session duration (with 1 second tolerance)
        if (sessionDataEntry != null) {
            val sessionStartMs = sessionDataEntry.startTime
            val sessionEndMs = sessionDataEntry.endTime ?: System.currentTimeMillis()
            val toleranceMs = 1000L // 1 second tolerance

            if (startTimestampMs < (sessionStartMs - toleranceMs) ||
                            endTimestampMs > (sessionEndMs + toleranceMs)
            ) {
                throw IllegalArgumentException(
                        "Time range [$startTimestampMs, $endTimestampMs] is out of session bounds " +
                                "[$sessionStartMs, $sessionEndMs]. " +
                                "Session duration: ${sessionEndMs - sessionStartMs}ms. " +
                                "Allowed tolerance: ${toleranceMs}ms"
                )
            }
        }

        // Filter events by time range
        val filteredEvents =
                if (sessionDataEntry != null) {
                    // Session is still active - get events from session data
                    sessionDataEntry.events.filter { event ->
                        try {
                            val eventTime = Instant.parse(event.timestamp).toEpochMilli()
                            eventTime >= startTimestampMs && eventTime <= endTimestampMs
                        } catch (e: Exception) {
                            false // Skip invalid timestamps
                        }
                    }
                } else {
                    // Session has ended - events should be retrieved from EventDatabase
                    // For now, return empty list (EventDatabase integration can be added later)
                    emptyList()
                }

        // Calculate duration
        val duration = endTimestampMs - startTimestampMs
        val durationSeconds = duration / 1000.0

        // Create a temporary SessionData for calculations
        val tempData =
                SessionData(
                        sessionId = sessionIdToUse,
                        startTime = startTimestampMs,
                        endTime = endTimestampMs,
                        eventCount = filteredEvents.size,
                        appSwitchCount = filteredEvents.count { it.eventType == "app_switch" },
                        events = filteredEvents.toMutableList()
                )

        // Compute notification summary
        val notificationEvents = filteredEvents.filter { it.eventType == "notification" }
        val notificationCount = notificationEvents.size
        val notificationIgnored = notificationEvents.count { it.metrics["action"] == "ignored" }
        val notificationIgnoreRate =
                if (notificationCount > 0) {
                    notificationIgnored.toDouble() / notificationCount
                } else 0.0
        val notificationClusteringIndex = computeNotificationClusteringIndex(notificationEvents)

        // Compute call summary
        val callEvents = filteredEvents.filter { it.eventType == "call" }
        val callCount = callEvents.size
        val callIgnored = callEvents.count { it.metrics["action"] == "ignored" }

        // Compute clipboard summary
        val clipboardEvents = filteredEvents.filter { it.eventType == "clipboard" }
        val clipboardCount = clipboardEvents.size
        val clipboardCopyCount = clipboardEvents.count { it.metrics["action"] == "copy" }
        val clipboardPasteCount = clipboardEvents.count { it.metrics["action"] == "paste" }
        val clipboardCutCount = clipboardEvents.count { it.metrics["action"] == "cut" }

        // Compute behavioral metrics from events
        val allMetrics = computeBehavioralMetricsFromEvents(tempData, duration, notificationCount, callCount)

        // Separate behavioral metrics from typing summary
        val behavioralMetrics = allMetrics.filterKeys { key ->
            key != "typing_session_summary"
        }

        val typingSessionSummary = allMetrics["typing_session_summary"] as? Map<String, Any>
                ?: mapOf(
                        "typing_session_count" to 0,
                        "average_keystrokes_per_session" to 0.0,
                        "average_typing_session_duration" to 0.0,
                        "average_typing_speed" to 0.0,
                        "average_typing_gap" to 0.0,
                        "average_inter_tap_interval" to 0.0,
                        "typing_cadence_stability" to 0.0,
                        "burstiness_of_typing" to 0.0,
                        "total_typing_duration" to 0,
                        "active_typing_ratio" to 0.0,
                        "typing_contribution_to_interaction_intensity" to 0.0,
                        "deep_typing_blocks" to 0,
                        "typing_fragmentation" to 0.0,
                        "correction_rate" to 0.0,
                        "clipboard_activity_rate" to 0.0,
                        "typing_metrics" to emptyList<Map<String, Any>>()
                )

        // Motion-state classification moved to the engine runtime
        // (RFC-MOTION-STATE-0001 §6.3); per-window motion data is no longer
        // surfaced through this SDK's `calculateMetricsForTimeRange` response.

        // Get current device context and system state
        val currentScreenBrightness = getScreenBrightness()
        val currentOrientation = context.resources.configuration.orientation
        val orientationStr =
                when (currentOrientation) {
                    Configuration.ORIENTATION_LANDSCAPE -> "landscape"
                    else -> "portrait"
                }

        // Build and return metrics map
        return mapOf(
                "behavioral_metrics" to behavioralMetrics,
                "device_context" to
                        mapOf(
                                "avg_screen_brightness" to currentScreenBrightness.toDouble(),
                                "start_orientation" to orientationStr,
                                "orientation_changes" to
                                        (sessionDataEntry?.orientationChangeCount ?: 0)
                        ),
                "system_state" to
                        mapOf(
                                "internet_state" to isInternetConnected(),
                                "do_not_disturb" to isDoNotDisturbEnabled(),
                                "charging" to isCharging()
                        ),
                "activity_summary" to
                        mapOf(
                                "total_events" to filteredEvents.size,
                                "app_switch_count" to tempData.appSwitchCount
                        ),
                "notification_summary" to
                        mapOf(
                                "notification_count" to notificationCount,
                                "notification_ignored" to notificationIgnored,
                                "notification_ignore_rate" to notificationIgnoreRate,
                                "notification_clustering_index" to notificationClusteringIndex,
                                "call_count" to callCount,
                                "call_ignored" to callIgnored
                        ),
                "clipboard_summary" to
                        mapOf(
                                "clipboard_count" to clipboardCount,
                                "clipboard_copy_count" to clipboardCopyCount,
                                "clipboard_paste_count" to clipboardPasteCount,
                                "clipboard_cut_count" to clipboardCutCount
                        ),
                "typing_session_summary" to typingSessionSummary,
        )
    }

    fun updateConfig(newConfig: BehaviorConfig) {
        inputSignalCollector.updateConfig(newConfig)
        attentionSignalCollector.updateConfig(newConfig)
        gestureCollector.updateConfig(newConfig)
        notificationCollector.updateConfig(newConfig)
        callCollector.updateConfig(newConfig)
        motionSignalCollector.updateConfig(newConfig)
    }

    fun attachToView(view: View) {
        android.util.Log.d(
                "BehaviorSDK",
                "attachToView called, enableInputSignals=${config.enableInputSignals}"
        )
        if (config.enableInputSignals) {
            inputSignalCollector.attachToView(view)
            gestureCollector.attachToView(view)
            android.util.Log.d("BehaviorSDK", "Collectors attached to view")
        } else {
            android.util.Log.d("BehaviorSDK", "Input signals disabled, not attaching collectors")
        }
    }

    /**
     * Forward a Window-level touch into the gesture collector. Used by
     * `SynheartBehaviorPlugin` to capture touches that would otherwise be
     * consumed by Flutter's embedded surface before reaching a
     * view-attached OnTouchListener. Forwarding is a read-only pass — the
     * caller does NOT consume the event.
     */
    fun feedTouchEvent(event: android.view.MotionEvent) {
        gestureCollector.feedTouchEvent(event)
    }

    fun dispose() {
        handler.removeCallbacks(idleCheckRunnable)
        inputSignalCollector.dispose()
        attentionSignalCollector.dispose()
        gestureCollector.dispose()
        notificationCollector.dispose()
        callCollector.dispose()
        SynheartNotificationListenerService.removeNotificationCollector(notificationCollector)
        ProcessLifecycleOwner.get().lifecycle.removeObserver(this)
    }

    @OnLifecycleEvent(Lifecycle.Event.ON_START)
    fun onAppForegrounded() {
        appInForeground = true
        attentionSignalCollector.onAppForegrounded()
        lastAppUseTime = System.currentTimeMillis()

        // Sync app switch count from AttentionSignalCollector to session data
        currentSessionId?.let { sessionId ->
            sessionData[sessionId]?.let { data ->
                val currentAppSwitchCount = attentionSignalCollector.getAppSwitchCount()
                // Only update if the count has increased (to avoid resetting on first launch)
                if (currentAppSwitchCount > data.appSwitchCount) {
                    data.appSwitchCount = currentAppSwitchCount
                    sessionData[sessionId] = data
                }
            }
        }
    }

    @OnLifecycleEvent(Lifecycle.Event.ON_STOP)
    fun onAppBackgrounded() {
        appInForeground = false
        attentionSignalCollector.onAppBackgrounded()
        // App switches are tracked via attention signal collector
    }

    fun onUserInteraction() {
        lastInteractionTime = System.currentTimeMillis()
    }

    private fun checkIdleState() {
        val idleTime = System.currentTimeMillis() - lastInteractionTime
        val idleSeconds = idleTime / 1000.0

        // Idle is now computed from gaps between events in the feature extractor
        // No need to emit separate idle events
    }

    // Public method to receive events from Flutter (Dart side)
    fun receiveEventFromFlutter(event: BehaviorEvent) {
        emitEvent(event)
    }

    private fun emitEvent(event: BehaviorEvent) {
        // Replace "current" session ID with actual session ID
        val eventWithSessionId =
                if (event.sessionId == "current" && currentSessionId != null) {
                    BehaviorEvent(
                            eventId = event.eventId,
                            sessionId = currentSessionId!!,
                            timestamp = event.timestamp,
                            eventType = event.eventType,
                            metrics = event.metrics
                    )
                } else {
                    event
                }

        if (eventHandler != null) {
            try {
                eventHandler?.invoke(eventWithSessionId)
            } catch (e: Exception) {
                android.util.Log.e("BehaviorSDK", "ERROR calling eventHandler: ${e.message}", e)
            }
        }

        if (currentSessionId == null) {
            return // Early return if no session
        }
        val sessionId = currentSessionId!!
        val sessionDataEntry = sessionData[sessionId]
        if (sessionDataEntry == null) {
            return // Early return if session data not found
        }
        // Store the event
        sessionDataEntry.eventCount++
        sessionDataEntry.events.add(eventWithSessionId) // Store event for session metrics

        // Update session-specific metrics based on new event types
        when (eventWithSessionId.eventType) {
            "tap" -> {
                // Count taps that are not long press as keystrokes
                val longPress = eventWithSessionId.metrics["long_press"] as? Boolean ?: false
                if (!longPress) {
                    sessionDataEntry.totalKeystrokes++
                }
            }
            "scroll" -> {
                sessionDataEntry.scrollEventCount++
                val velocity =
                        (eventWithSessionId.metrics["velocity"] as? Number)?.toDouble() ?: 0.0
                sessionDataEntry.totalScrollVelocity += velocity
            }
        // App switches will be tracked separately
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
        /**
         * Emit raw 50 Hz accel batches over MethodChannel for the runtime to
         * consume (RFC-MOTION-STATE-0001 Phase 3). Independent of
         * [enableMotionLite].
         */
        val emitRawMotionSamples: Boolean = false,
        val sessionIdPrefix: String? = null,
        val eventBatchSize: Int = 10,
        val maxIdleGapSeconds: Double = 10.0
)

data class BehaviorEvent(
        val eventId: String = "evt_${System.currentTimeMillis()}",
        val sessionId: String,
        val timestamp: String, // ISO 8601 format
        val eventType: String, // scroll, tap, swipe, notification, call, typing
        val metrics: Map<String, Any>
) {
    fun toMap(): Map<String, Any> =
            mapOf(
                    "event" to
                            mapOf(
                                    "event_id" to eventId,
                                    "session_id" to sessionId,
                                    "timestamp" to timestamp,
                                    "event_type" to eventType,
                                    "metrics" to metrics
                            )
            )

    // Legacy format for backward compatibility during migration
    fun toLegacyMap(): Map<String, Any> =
            mapOf(
                    "session_id" to sessionId,
                    "timestamp" to
                            try {
                                java.time.Instant.parse(timestamp).toEpochMilli()
                            } catch (e: Exception) {
                                System.currentTimeMillis()
                            },
                    "type" to eventType,
                    "payload" to metrics
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
        var appSwitchCount: Int = 0,
        val sessionSpacing: Long = 0, // Time since last app use
        val startScreenBrightness: Float = 0f,
        val startOrientation: Int = Configuration.ORIENTATION_PORTRAIT,
        var orientationChangeCount: Int = 0,
        val startInternetState: Boolean = false,
        val startDoNotDisturb: Boolean = false,
        val startCharging: Boolean = false,
        val events: MutableList<BehaviorEvent> = mutableListOf() // Store events for session metrics
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
    fun toMap(): Map<String, Any?> =
            mapOf(
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
    fun toMap(): Map<String, Any?> =
            mapOf(
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
