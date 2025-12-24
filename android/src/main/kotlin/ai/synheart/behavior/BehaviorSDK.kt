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
import kotlin.math.exp

/**
 * Main BehaviorSDK class for collecting behavioral signals. Privacy-first: No text content, no PII
 * - only timing and interaction patterns.
 */
class BehaviorSDK(private val context: Context, private val config: BehaviorConfig) :
        LifecycleObserver {

    private var eventHandler: ((BehaviorEvent) -> Unit)? = null
    private var currentSessionId: String? = null
    private val sessionData = ConcurrentHashMap<String, SessionData>()
    private val statsCollector = StatsCollector()

    // Signal collectors
    private val inputSignalCollector = InputSignalCollector(config)
    private val attentionSignalCollector = AttentionSignalCollector(config)
    private val gestureCollector = GestureCollector(config)
    private val notificationCollector = NotificationCollector(config)
    private val callCollector = CallCollector(context, config)

    // Lifecycle tracking
    private var appInForeground = true
    private var lastInteractionTime = System.currentTimeMillis()
    private var lastAppUseTime: Long? = null // For session spacing calculation
    private val handler = Handler(Looper.getMainLooper())

    // Device context tracking
    private var startScreenBrightness: Float = 0f
    private var startOrientation: Int = Configuration.ORIENTATION_PORTRAIT
    private var orientationChangeCount: Int = 0

    // System state tracking
    private var startInternetState: Boolean = false
    private var startDoNotDisturb: Boolean = false
    private var startCharging: Boolean = false
    private val idleCheckRunnable =
            object : Runnable {
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

        // Set notification collector for the service
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

    fun startSession(sessionId: String) {
        currentSessionId = sessionId
        val now = System.currentTimeMillis()

        // Capture device context at session start
        startScreenBrightness = getScreenBrightness()
        startOrientation = context.resources.configuration.orientation
        orientationChangeCount = 0

        // Capture system state at session start
        startInternetState = isInternetConnected()
        startDoNotDisturb = isDoNotDisturbEnabled()
        startCharging = isCharging()

        // Calculate session spacing (time since last app use)
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
        lastAppUseTime = now

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
        // Track orientation changes
        val configChangeListener =
                object : View.OnAttachStateChangeListener {
                    override fun onViewAttachedToWindow(v: View) {}
                    override fun onViewDetachedFromWindow(v: View) {}
                }
        // Orientation changes will be detected via configuration changes
    }

    fun onConfigurationChanged(newConfig: Configuration) {
        val currentOrientation = newConfig.orientation
        if (currentOrientation != startOrientation && currentSessionId != null) {
            orientationChangeCount++
            sessionData[currentSessionId]?.let { data ->
                data.orientationChangeCount = orientationChangeCount
            }
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

        // Compute behavioral metrics from events
        val behavioralMetrics =
                computeBehavioralMetrics(data, duration, notificationCount, callCount)

        // Build comprehensive summary
        val summary =
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
                        "system_state" to
                                mapOf(
                                        "internet_state" to endInternetState,
                                        "do_not_disturb" to endDoNotDisturb,
                                        "charging" to endCharging
                                )
                )

        sessionData.remove(sessionId)
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

    private fun computeBehavioralMetrics(
            data: SessionData,
            durationMs: Long,
            notificationCount: Int,
            callCount: Int
    ): Map<String, Any> {
        val durationSeconds = durationMs / 1000.0

        // Step 1: Compute inter-event times for burstiness (Barabási's burstiness index)
        val burstiness = computeBurstiness(data.events)

        // Step 2: Compute notification_load = 1 - exp(-notification_rate / λ)
        // where notification_rate = notification_count / session_duration_seconds
        // λ = 1/60 (sensitivity parameter)
        val notificationRate =
                if (durationSeconds > 0) {
                    notificationCount / durationSeconds
                } else 0.0
        val lambda = 1.0 / 60.0
        val notificationLoad =
                if (notificationRate > 0) {
                    1.0 - exp(-notificationRate / lambda)
                } else 0.0

        // Step 3: Compute task_switch_rate = 1 - exp(-task_switch_rate_raw / μ)
        // where task_switch_rate_raw = app_switch_count / session_duration
        // μ = 1/30 (task-switch tolerance)
        val taskSwitchRateRaw =
                if (durationSeconds > 0) {
                    data.appSwitchCount / durationSeconds
                } else 0.0
        val mu = 1.0 / 30.0
        val taskSwitchRate =
                if (taskSwitchRateRaw > 0) {
                    1.0 - exp(-taskSwitchRateRaw / mu)
                } else 0.0

        // Step 4: Compute task_switch_cost = session duration during app_switch
        // Since we don't track individual app switch durations, estimate as average time per switch
        val taskSwitchCost =
                if (data.appSwitchCount > 0) {
                    // Estimate: assume each app switch takes some time
                    // This should ideally be tracked from actual app switch events
                    (durationMs / data.appSwitchCount).toInt().coerceIn(0, 10000)
                } else 0

        // Step 5: Compute idle_ratio = total_idle_time / session_duration
        // where total_idle_time = Σ Δtᵢ where Δtᵢ > idle_threshold (30 seconds)
        val idleRatio = computeIdleRatio(data.events, durationMs)

        // Step 6: Compute active_interaction_time = session_duration - idle_time - task_switch_cost
        val totalIdleTimeMs = (idleRatio * durationMs).toLong()
        val activeInteractionTimeMs = durationMs - totalIdleTimeMs - taskSwitchCost
        val activeTimeRatio =
                if (durationMs > 0) {
                    (activeInteractionTimeMs.toDouble() / durationMs).coerceIn(0.0, 1.0)
                } else 0.0

        // Step 7: Compute fragmented_idle_ratio = number_of_idle_segments / session_duration
        val fragmentedIdleRatio = computeFragmentedIdleRatio(data.events, durationMs)

        // Step 8: Compute scroll_jitter_rate = direction_reversals / max(total_scroll_events - 1,
        // 1)
        val scrollJitterRate = computeScrollJitterRate(data.events)

        // Step 9: Compute distraction_score = weighted combination
        // w1=0.35, w2=0.30, w3=0.20, w4=0.15
        val w1 = 0.35
        val w2 = 0.30
        val w3 = 0.20
        val w4 = 0.15
        val behavioralDistractionScore =
                (w1 * taskSwitchRate +
                                w2 * notificationLoad +
                                w3 * fragmentedIdleRatio +
                                w4 * scrollJitterRate)
                        .coerceIn(0.0, 1.0)

        // Step 10: Compute focus_hint = 1 - distraction_score
        val focusHint = 1.0 - behavioralDistractionScore

        // Step 11: Compute interaction_intensity = total_events_except_interruptions /
        // session_duration
        // Interruptions = notifications, calls, app switches
        val interruptionCount = notificationCount + callCount + data.appSwitchCount
        val totalEventsExceptInterruptions = data.eventCount - interruptionCount
        val interactionIntensity =
                if (durationSeconds > 0) {
                    (totalEventsExceptInterruptions / durationSeconds).coerceIn(
                            0.0,
                            Double.MAX_VALUE
                    )
                } else 0.0

        // Step 12: Compute deep_focus_block = continuous app engagement ≥ 120s without
        // idle, app switch, notification or call event
        val deepFocusBlocks =
                computeDeepFocusBlocks(
                        data.events,
                        durationMs,
                        notificationCount,
                        callCount,
                        data.appSwitchCount
                )

        return mapOf(
                "interaction_intensity" to interactionIntensity,
                "task_switch_rate" to taskSwitchRate,
                "task_switch_cost" to taskSwitchCost,
                "idle_time_ratio" to idleRatio,
                "active_time_ratio" to activeTimeRatio,
                "notification_load" to notificationLoad,
                "burstiness" to burstiness,
                "behavioral_distraction_score" to behavioralDistractionScore,
                "focus_hint" to focusHint,
                "fragmented_idle_ratio" to fragmentedIdleRatio,
                "scroll_jitter_rate" to scrollJitterRate,
                "deep_focus_blocks" to deepFocusBlocks
        )
    }

    private fun computeIdleRatio(events: List<BehaviorEvent>, durationMs: Long): Double {
        if (events.size < 2) return 0.0

        val idleThresholdMs = 30000L // 30 seconds
        var totalIdleTime = 0L
        for (i in 1 until events.size) {
            try {
                val prevTime = Instant.parse(events[i - 1].timestamp).toEpochMilli()
                val currTime = Instant.parse(events[i].timestamp).toEpochMilli()
                val gap = currTime - prevTime
                if (gap > idleThresholdMs) {
                    totalIdleTime += gap - idleThresholdMs
                }
            } catch (e: Exception) {
                // Skip invalid timestamps
            }
        }

        return if (durationMs > 0) {
            (totalIdleTime.toDouble() / durationMs).coerceIn(0.0, 1.0)
        } else 0.0
    }

    private fun computeFragmentedIdleRatio(events: List<BehaviorEvent>, durationMs: Long): Double {
        if (events.size < 2) return 0.0

        val idleThresholdMs = 30000L // 30 seconds
        var numberOfIdleSegments = 0
        for (i in 1 until events.size) {
            try {
                val prevTime = Instant.parse(events[i - 1].timestamp).toEpochMilli()
                val currTime = Instant.parse(events[i].timestamp).toEpochMilli()
                val gap = currTime - prevTime
                if (gap > idleThresholdMs) {
                    numberOfIdleSegments++
                }
            } catch (e: Exception) {
                // Skip invalid timestamps
            }
        }

        val durationSeconds = durationMs / 1000.0
        return if (durationSeconds > 0) {
            (numberOfIdleSegments / durationSeconds).coerceIn(0.0, Double.MAX_VALUE)
        } else 0.0
    }

    private fun computeScrollJitterRate(events: List<BehaviorEvent>): Double {
        val scrollEvents = events.filter { it.eventType == "scroll" }
        if (scrollEvents.size < 2) return 0.0

        var directionReversals = 0
        var previousDirection: String? = null
        for (event in scrollEvents) {
            val currentDirection = event.metrics["direction"] as? String
            if (currentDirection != null &&
                            previousDirection != null &&
                            currentDirection != previousDirection
            ) {
                directionReversals++
            }
            previousDirection = currentDirection
        }

        val totalScrollEvents = scrollEvents.size
        return if (totalScrollEvents > 1) {
            (directionReversals.toDouble() / (totalScrollEvents - 1)).coerceIn(0.0, 1.0)
        } else 0.0
    }

    private fun computeBurstiness(events: List<BehaviorEvent>): Double {
        if (events.size < 2) {
            return 0.0
        }

        val intervals = mutableListOf<Long>()
        for (i in 1 until events.size) {
            try {
                val prevTime = Instant.parse(events[i - 1].timestamp).toEpochMilli()
                val currTime = Instant.parse(events[i].timestamp).toEpochMilli()
                val interval = currTime - prevTime
                intervals.add(interval)
            } catch (e: Exception) {
                // Skip invalid timestamps
            }
        }

        if (intervals.size == 0) {
            return 0.0
        }

        val mean = intervals.average()

        // If mean is 0, all intervals are 0 (events at same time) - return 0
        if (mean == 0.0) {
            return 0.0
        }

        val variance = intervals.map { (it - mean) * (it - mean) }.average()
        val stdDev = kotlin.math.sqrt(variance)

        // If stdDev is 0, all intervals are identical (perfectly regular) - burstiness should be 0
        if (stdDev == 0.0) {
            return 0.0
        }

        // Burstiness formula: (σ - μ)/(σ + μ) remapped to [0,1]
        val burstinessRaw = (stdDev - mean) / (stdDev + mean)
        val burstiness = ((burstinessRaw + 1.0) / 2.0).coerceIn(0.0, 1.0)

        return burstiness
    }

    private fun computeDeepFocusBlocks(
            events: List<BehaviorEvent>,
            durationMs: Long,
            notificationCount: Int,
            callCount: Int,
            appSwitchCount: Int
    ): List<Map<String, Any>> {
        // Deep focus block = continuous app engagement ≥ 120s without
        // idle, app switch, notification or call event
        val deepFocusBlocks = mutableListOf<Map<String, Any>>()
        val minBlockDurationMs = 120000L // 120 seconds

        if (events.size < 2) return deepFocusBlocks

        val idleThresholdMs = 30000L // 30 seconds
        var blockStart: Long? = null
        var blockEnd: Long? = null

        // Filter out interruption events (notifications, calls)
        val interruptionEventTypes = setOf("notification", "call")

        for (i in 0 until events.size) {
            try {
                val event = events[i]
                val currTime = Instant.parse(event.timestamp).toEpochMilli()

                // Check if this is an interruption event
                val isInterruption = interruptionEventTypes.contains(event.eventType)

                // Check gap from previous event
                val gap =
                        if (i > 0) {
                            val prevTime = Instant.parse(events[i - 1].timestamp).toEpochMilli()
                            currTime - prevTime
                        } else {
                            0L
                        }

                // If we hit an interruption or idle gap, end current block
                if (isInterruption || gap > idleThresholdMs) {
                    if (blockStart != null && blockEnd != null) {
                        val blockDuration = blockEnd - blockStart
                        if (blockDuration >= minBlockDurationMs) {
                            deepFocusBlocks.add(
                                    mapOf(
                                            "start_at" to
                                                    Instant.ofEpochMilli(blockStart).toString(),
                                            "end_at" to Instant.ofEpochMilli(blockEnd).toString(),
                                            "duration_ms" to blockDuration.toInt()
                                    )
                            )
                        }
                    }
                    blockStart = null
                    blockEnd = null
                } else {
                    // Continue or start a focus block
                    if (blockStart == null) {
                        blockStart = currTime
                    }
                    blockEnd = currTime
                }
            } catch (e: Exception) {
                // Skip invalid timestamps
            }
        }

        // Check final block
        if (blockStart != null && blockEnd != null) {
            val blockDuration = blockEnd - blockStart
            if (blockDuration >= minBlockDurationMs) {
                deepFocusBlocks.add(
                        mapOf(
                                "start_at" to Instant.ofEpochMilli(blockStart).toString(),
                                "end_at" to Instant.ofEpochMilli(blockEnd).toString(),
                                "duration_ms" to blockDuration.toInt()
                        )
                )
            }
        }

        return deepFocusBlocks
    }

    fun getCurrentStats(): BehaviorStats {
        return statsCollector.getCurrentStats()
    }

    fun updateConfig(newConfig: BehaviorConfig) {
        inputSignalCollector.updateConfig(newConfig)
        attentionSignalCollector.updateConfig(newConfig)
        gestureCollector.updateConfig(newConfig)
        notificationCollector.updateConfig(newConfig)
        callCollector.updateConfig(newConfig)
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

    fun dispose() {
        handler.removeCallbacks(idleCheckRunnable)
        inputSignalCollector.dispose()
        attentionSignalCollector.dispose()
        gestureCollector.dispose()
        notificationCollector.dispose()
        callCollector.dispose()
        SynheartNotificationListenerService.setNotificationCollector(null)
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
        val sessionIdPrefix: String? = null,
        val eventBatchSize: Int = 10,
        val maxIdleGapSeconds: Double = 10.0
)

data class BehaviorEvent(
        val eventId: String = "evt_${System.currentTimeMillis()}",
        val sessionId: String,
        val timestamp: String, // ISO 8601 format
        val eventType: String, // scroll, tap, swipe, notification, call
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
    fun toMap(): Map<String, Any?> =
            mapOf(
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
