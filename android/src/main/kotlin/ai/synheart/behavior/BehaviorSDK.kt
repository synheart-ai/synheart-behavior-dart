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

        // Compute behavioral metrics from events
        val behavioralMetrics =
                computeBehavioralMetrics(data, duration, notificationCount, callCount)

        // Compute typing session summary
        val typingSessionSummary = computeTypingSessionSummary(data, duration)

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
                        "system_state" to
                                mapOf(
                                        "internet_state" to endInternetState,
                                        "do_not_disturb" to endDoNotDisturb,
                                        "charging" to endCharging
                                )
                )

        // Add typing session summary if available
        val summary =
                if (typingSessionSummary.isNotEmpty()) {
                    summaryBase + mapOf("typing_session_summary" to typingSessionSummary)
                } else {
                    summaryBase
                }

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

        // Step 11: Compute interaction_intensity = [total events except interruptions and typing +
        // (Typing durations/10s)] / session_duration
        // Interruptions = notifications, calls, app switches
        // Typing events are handled separately: we add (total_typing_duration_seconds / 10) instead
        // of counting typing events
        val interruptionCount = notificationCount + callCount + data.appSwitchCount

        // Count typing events to exclude them from event count
        val typingEvents = data.events.filter { it.eventType == "typing" }
        val typingEventCount = typingEvents.size

        // Calculate total typing duration in seconds (sum of all typing session durations)
        val totalTypingDurationSeconds =
                if (typingEvents.isNotEmpty()) {
                    typingEvents
                            .mapNotNull { event -> (event.metrics["duration"] as? Number)?.toInt() }
                            .sum()
                            .toDouble()
                } else {
                    0.0
                }

        // Total events excluding interruptions and typing events
        val totalEventsExceptInterruptionsAndTyping =
                data.eventCount - interruptionCount - typingEventCount

        // Interaction intensity = [non-interruption non-typing events + (typing_duration/10)] /
        // session_duration
        val interactionIntensity =
                if (durationSeconds > 0) {
                    val typingContribution = totalTypingDurationSeconds / 10.0
                    ((totalEventsExceptInterruptionsAndTyping + typingContribution) /
                                    durationSeconds)
                            .coerceIn(0.0, Double.MAX_VALUE)
                } else 0.0

        // Step 12: Compute deep_focus_block = continuous app engagement ≥ 120s without
        // idle, app switch, notification or call event
        val deepFocusBlocks =
                computeDeepFocusBlocks(
                        data.events,
                        durationMs,
                        data.startTime,
                        data.endTime,
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

        // Step 1: Calculate all inter-event gaps
        val gaps = mutableListOf<Pair<Long, Boolean>>() // (gap, involvesTyping)
        for (i in 1 until events.size) {
            try {
                val prevTime = Instant.parse(events[i - 1].timestamp).toEpochMilli()
                val currTime = Instant.parse(events[i].timestamp).toEpochMilli()
                val gap = currTime - prevTime

                // Check if this gap involves typing (either previous or current event is typing)
                val prevIsTyping = events[i - 1].eventType == "typing"
                val currIsTyping = events[i].eventType == "typing"
                val involvesTyping = prevIsTyping || currIsTyping

                gaps.add(Pair(gap, involvesTyping))
            } catch (e: Exception) {
                // Skip invalid timestamps
            }
        }

        if (gaps.isEmpty()) {
            return 0.0
        }

        // Step 2: Find max gap excluding gaps that involve typing
        val maxNonTypingGap =
                gaps
                        .filter { !it.second } // Only non-typing gaps
                        .map { it.first } // Get gap values
                        .maxOrNull()
                        ?: 0L

        // Step 3: Cap typing gaps at max non-typing gap
        // If maxNonTypingGap is 0 (no non-typing events), use the gaps as-is
        val cappedGaps =
                if (maxNonTypingGap > 0) {
                    gaps.map { (gap, involvesTyping) ->
                        if (involvesTyping) {
                            // Cap typing gaps at max non-typing gap
                            minOf(gap, maxNonTypingGap)
                        } else {
                            gap
                        }
                    }
                } else {
                    // If all events are typing or no non-typing gaps found, use gaps as-is
                    gaps.map { it.first }
                }

        // Step 4: Calculate mean and standard deviation using capped gaps
        val mean = cappedGaps.average()

        // If mean is 0, all intervals are 0 (events at same time) - return 0
        if (mean == 0.0) {
            return 0.0
        }

        val variance = cappedGaps.map { (it - mean) * (it - mean) }.average()
        val stdDev = kotlin.math.sqrt(variance)

        // If stdDev is 0, all intervals are identical (perfectly regular) - burstiness should be 0
        if (stdDev == 0.0) {
            return 0.0
        }

        // Step 5: Apply Barabási's burstiness formula: (σ - μ)/(σ + μ) remapped to [0,1]
        val burstinessRaw = (stdDev - mean) / (stdDev + mean)
        val burstiness = ((burstinessRaw + 1.0) / 2.0).coerceIn(0.0, 1.0)

        return burstiness
    }

    private fun computeDeepFocusBlocks(
            events: List<BehaviorEvent>,
            durationMs: Long, // Unused but kept for API consistency
            sessionStartTime: Long,
            sessionEndTime: Long,
            notificationCount: Int, // Unused but kept for API consistency
            callCount: Int, // Unused but kept for API consistency
            appSwitchCount: Int // Unused but kept for API consistency
    ): List<Map<String, Any>> {
        // Deep focus block = continuous app engagement ≥ 120s without
        // idle, app switch, notification or call event
        val deepFocusBlocks = mutableListOf<Map<String, Any>>()
        val minBlockDurationMs = 120000L // 120 seconds

        if (events.size < 2) return deepFocusBlocks

        val idleThresholdMs = 30000L // 30 seconds
        var blockStart: Long? = null
        var blockEnd: Long? = null
        var lastBlockEndTime: Long? = null // Track when last block ended

        // Filter out interruption events (notifications, calls, app switches)
        val interruptionEventTypes = setOf("notification", "call", "app_switch")

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
                            // First event - check gap from session start
                            currTime - sessionStartTime
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
                    lastBlockEndTime = if (isInterruption) currTime else blockEnd
                    blockStart = null
                    blockEnd = null
                } else {
                    // Continue or start a focus block
                    if (blockStart == null) {
                        // Starting a new block - check if we should start from session start or
                        // previous block end
                        if (i == 0 && gap <= idleThresholdMs) {
                            // First event and close to session start - start from session start
                            blockStart = sessionStartTime
                        } else if (lastBlockEndTime != null &&
                                        (currTime - lastBlockEndTime) <= idleThresholdMs
                        ) {
                            // Close to previous block end - start from previous block end
                            blockStart = lastBlockEndTime
                        } else {
                            // Start from current event time
                            blockStart = currTime
                        }
                    }
                    blockEnd = currTime
                }
            } catch (e: Exception) {
                // Skip invalid timestamps
            }
        }

        // Check final block - include time from last event to session end if recent
        if (blockStart != null && blockEnd != null) {
            // Get the last event time in the block
            val lastEventTime = blockEnd

            // If last event was recent (within idle threshold of session end), extend to session
            // end
            // This ensures we count engagement time even if no events were generated at the end
            val timeFromLastEventToSessionEnd = sessionEndTime - lastEventTime
            val finalBlockEnd =
                    if (timeFromLastEventToSessionEnd <= idleThresholdMs) {
                        // Last event was recent, include time up to session end
                        sessionEndTime
                    } else {
                        // Last event was too long ago, use event timestamp
                        blockEnd
                    }

            val blockDuration = finalBlockEnd - blockStart
            if (blockDuration >= minBlockDurationMs) {
                deepFocusBlocks.add(
                        mapOf(
                                "start_at" to Instant.ofEpochMilli(blockStart).toString(),
                                "end_at" to Instant.ofEpochMilli(finalBlockEnd).toString(),
                                "duration_ms" to blockDuration.toInt()
                        )
                )
            }
        }

        return deepFocusBlocks
    }

    private fun computeTypingSessionSummary(data: SessionData, durationMs: Long): Map<String, Any> {
        // Extract all typing events
        val typingEvents = data.events.filter { it.eventType == "typing" }

        if (typingEvents.isEmpty()) {
            return mapOf(
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
                    "typing_metrics" to emptyList<Map<String, Any>>()
            )
        }

        // Each typing event represents one typing session (from Flutter BehaviorTextField)
        val typingSessionCount = typingEvents.size

        // Extract metrics from each typing event
        val sessionMetrics =
                typingEvents.map { event ->
                    mapOf(
                            "typing_tap_count" to
                                    ((event.metrics["typing_tap_count"] as? Number)?.toInt() ?: 0),
                            "typing_speed" to
                                    ((event.metrics["typing_speed"] as? Number)?.toDouble() ?: 0.0),
                            "duration" to ((event.metrics["duration"] as? Number)?.toInt() ?: 0),
                            "mean_inter_tap_interval_ms" to
                                    ((event.metrics["mean_inter_tap_interval_ms"] as? Number)
                                            ?.toDouble()
                                            ?: 0.0),
                            "typing_cadence_stability" to
                                    ((event.metrics["typing_cadence_stability"] as? Number)
                                            ?.toDouble()
                                            ?: 0.0),
                            "typing_gap_ratio" to
                                    ((event.metrics["typing_gap_ratio"] as? Number)?.toDouble()
                                            ?: 0.0),
                            "typing_burstiness" to
                                    ((event.metrics["typing_burstiness"] as? Number)?.toDouble()
                                            ?: 0.0),
                            "deep_typing" to (event.metrics["deep_typing"] as? Boolean ?: false),
                            "start_at" to (event.metrics["start_at"] as? String ?: ""),
                            "end_at" to (event.metrics["end_at"] as? String ?: "")
                    )
                }

        // Aggregate metrics
        val averageKeystrokesPerSession =
                sessionMetrics.map { it["typing_tap_count"] as Int }.average()
        val averageTypingSessionDuration = sessionMetrics.map { it["duration"] as Int }.average()
        val averageTypingSpeed = sessionMetrics.map { it["typing_speed"] as Double }.average()

        // Calculate average typing gap from mean_inter_tap_interval_ms
        val averageTypingGap =
                sessionMetrics.map { it["mean_inter_tap_interval_ms"] as Double }.average()

        // Calculate average inter-tap interval across all sessions
        // This is the average of mean_inter_tap_interval_ms for each session
        val averageInterTapInterval =
                if (sessionMetrics.isNotEmpty()) {
                    sessionMetrics.map { it["mean_inter_tap_interval_ms"] as Double }.average()
                } else {
                    0.0
                }

        // Average cadence stability across sessions
        val typingCadenceStability =
                sessionMetrics.map { it["typing_cadence_stability"] as Double }.average()

        // Average burstiness across sessions
        val burstinessOfTyping = sessionMetrics.map { it["typing_burstiness"] as Double }.average()

        // Total typing duration (sum of all session durations)
        val totalTypingDuration = sessionMetrics.map { it["duration"] as Int }.sum()

        // Active typing ratio = total typing duration / session duration
        val activeTypingRatio =
                if (durationMs > 0) {
                    (totalTypingDuration * 1000.0 / durationMs).coerceIn(0.0, 1.0)
                } else 0.0

        // Typing contribution to interaction intensity = typing events / total events
        val typingContributionToInteractionIntensity =
                if (data.eventCount > 0) {
                    typingEvents.size.toDouble() / data.eventCount
                } else 0.0

        // Deep typing blocks = sessions with deep_typing == true
        val deepTypingBlocks = sessionMetrics.count { it["deep_typing"] as Boolean }

        // Typing fragmentation = average gap ratio across sessions
        val typingFragmentation = sessionMetrics.map { it["typing_gap_ratio"] as Double }.average()

        // Individual typing session metrics (for detailed breakdown)
        val individualMetrics =
                typingEvents.map { event ->
                    mapOf(
                            "start_at" to (event.metrics["start_at"] as? String ?: ""),
                            "end_at" to (event.metrics["end_at"] as? String ?: ""),
                            "duration" to ((event.metrics["duration"] as? Number)?.toInt() ?: 0),
                            "deep_typing" to (event.metrics["deep_typing"] as? Boolean ?: false),
                            "typing_tap_count" to
                                    ((event.metrics["typing_tap_count"] as? Number)?.toInt() ?: 0),
                            "typing_speed" to
                                    ((event.metrics["typing_speed"] as? Number)?.toDouble() ?: 0.0),
                            "mean_inter_tap_interval_ms" to
                                    ((event.metrics["mean_inter_tap_interval_ms"] as? Number)
                                            ?.toDouble()
                                            ?: 0.0),
                            "typing_cadence_variability" to
                                    ((event.metrics["typing_cadence_variability"] as? Number)
                                            ?.toDouble()
                                            ?: 0.0),
                            "typing_cadence_stability" to
                                    ((event.metrics["typing_cadence_stability"] as? Number)
                                            ?.toDouble()
                                            ?: 0.0),
                            "typing_gap_count" to
                                    ((event.metrics["typing_gap_count"] as? Number)?.toInt() ?: 0),
                            "typing_gap_ratio" to
                                    ((event.metrics["typing_gap_ratio"] as? Number)?.toDouble()
                                            ?: 0.0),
                            "typing_burstiness" to
                                    ((event.metrics["typing_burstiness"] as? Number)?.toDouble()
                                            ?: 0.0),
                            "typing_activity_ratio" to
                                    ((event.metrics["typing_activity_ratio"] as? Number)?.toDouble()
                                            ?: 0.0),
                            "typing_interaction_intensity" to
                                    ((event.metrics["typing_interaction_intensity"] as? Number)
                                            ?.toDouble()
                                            ?: 0.0)
                    )
                }

        return mapOf(
                "typing_session_count" to typingSessionCount,
                "average_keystrokes_per_session" to averageKeystrokesPerSession,
                "average_typing_session_duration" to averageTypingSessionDuration,
                "average_typing_speed" to averageTypingSpeed,
                "average_typing_gap" to averageTypingGap,
                "average_inter_tap_interval" to averageInterTapInterval,
                "typing_cadence_stability" to typingCadenceStability,
                "burstiness_of_typing" to burstinessOfTyping,
                "total_typing_duration" to totalTypingDuration,
                "active_typing_ratio" to activeTypingRatio,
                "typing_contribution_to_interaction_intensity" to
                        typingContributionToInteractionIntensity,
                "deep_typing_blocks" to deepTypingBlocks,
                "typing_fragmentation" to typingFragmentation,
                "typing_metrics" to individualMetrics
        )
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
