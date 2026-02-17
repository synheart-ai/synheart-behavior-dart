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
    private var currentSessionId: String? = null
    private val sessionData = ConcurrentHashMap<String, SessionData>()
    private val sessionMotionData =
            ConcurrentHashMap<String, List<MotionSignalCollector.MotionDataPoint>>()
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
        // Clear previous session data when starting a new session
        // This ensures data persists until the next session starts, allowing
        // calculateMetricsForTimeRange to access it for ended sessions
        val previousSessionId = currentSessionId
        if (previousSessionId != null && previousSessionId != sessionId) {
            sessionData.remove(previousSessionId)
            sessionMotionData.remove(previousSessionId)
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

        // Compute clipboard summary (counts only; correction_rate and clipboard_activity_rate come from Flux)
        val clipboardEvents = data.events.filter { it.eventType == "clipboard" }
        val clipboardCount = clipboardEvents.size
        val clipboardCopyCount = clipboardEvents.count { it.metrics["action"] == "copy" }
        val clipboardPasteCount = clipboardEvents.count { it.metrics["action"] == "paste" }
        val clipboardCutCount = clipboardEvents.count { it.metrics["action"] == "cut" }

        // Compute behavioral metrics from events
        // Use only Flux (Rust) calculations - native Kotlin calculations commented out
        val (calculationMetrics, fluxMetrics, performanceInfo) =
                computeBehavioralMetricsWithFlux(data, duration, notificationCount, callCount)

        // Require Flux metrics - fail if not available
        if (fluxMetrics == null) {
            throw Exception("Flux is required but metrics are not available")
        }

        // Compute typing session summary
        // Native Kotlin typing summary calculation commented out - using Flux typing summary
        // instead
        // val typingSessionSummary = computeTypingSessionSummary(data, duration)

        // Collect motion data if enabled
        val motionData = motionSignalCollector.stopSession()

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
                        "behavioral_metrics" to fluxMetrics!!, // Use Flux (Rust) results as primary
                        // "behavioral_metrics_flux" removed - Flux is now the primary source
                        "performance_info" to performanceInfo,
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

        // Add typing session summary from Flux (primary source)
        var summary = summaryBase
        // Native typing summary commented out - using Flux typing summary instead
        // if (typingSessionSummary.isNotEmpty()) {
        //     summary = summary + mapOf("typing_session_summary" to typingSessionSummary)
        // }

        // Extract Flux typing session summary (now primary source)
        android.util.Log.d("BehaviorSDK", "=== FLUX TYPING SUMMARY EXTRACTION ===")
        android.util.Log.d("BehaviorSDK", "fluxMetrics is null: ${fluxMetrics == null}")
        if (fluxMetrics != null) {
            android.util.Log.d("BehaviorSDK", "Flux metrics keys: ${fluxMetrics.keys}")
            val typingSummaryRaw = fluxMetrics["typing_session_summary"]
            android.util.Log.d("BehaviorSDK", "typing_session_summary raw value: $typingSummaryRaw")
            android.util.Log.d(
                    "BehaviorSDK",
                    "typing_session_summary type: ${typingSummaryRaw?.javaClass?.simpleName}"
            )
        }
        var fluxTypingSummary = fluxMetrics.get("typing_session_summary") as? Map<String, Any>
        android.util.Log.d("BehaviorSDK", "fluxTypingSummary after cast: $fluxTypingSummary")
        android.util.Log.d(
                "BehaviorSDK",
                "fluxTypingSummary is null: ${fluxTypingSummary == null}, isEmpty: ${fluxTypingSummary?.isEmpty()}"
        )
        if (fluxTypingSummary != null && fluxTypingSummary.isNotEmpty()) {
            // correction_rate and clipboard_activity_rate come from Flux (no manual override)
            android.util.Log.d(
                    "BehaviorSDK",
                    "Adding Flux typing summary to session result with keys: ${fluxTypingSummary.keys}"
            )
            summary = summary + mapOf("typing_session_summary" to fluxTypingSummary)
        } else {
            android.util.Log.d(
                    "BehaviorSDK",
                    "Flux typing summary not available or empty - NOT adding to summary"
            )
        }
        android.util.Log.d("BehaviorSDK", "=== END FLUX TYPING SUMMARY EXTRACTION ===")

        // Add motion data if available
        if (motionData.isNotEmpty()) {
            val motionDataJson =
                    motionData.map { dataPoint ->
                        mapOf("timestamp" to dataPoint.timestamp, "features" to dataPoint.features)
                    }
            summary = summary + mapOf("motion_data" to motionDataJson)

            // Store motion data for on-demand queries (will be cleared when next session starts)
            sessionMotionData[sessionId] = motionData
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
     * Compute behavioral metrics using Flux (Rust).
     *
     * Returns a Triple of (calculationMetrics, fluxMetrics, performanceInfo) where:
     * - calculationMetrics: Empty map (not used, kept for API compatibility)
     * - fluxMetrics: Results from Rust (synheart-flux), or null if Flux is unavailable/failed
     * - performanceInfo: Contains execution time for Flux computation
     */
    private fun computeBehavioralMetricsWithFlux(
            data: SessionData,
            durationMs: Long,
            notificationCount: Int,
            callCount: Int
    ): Triple<Map<String, Any>, Map<String, Any>?, Map<String, Any>> {
        // Native Kotlin calculation commented out - using only Flux
        // val kotlinStartTime = System.nanoTime()
        // val kotlinMetrics = computeBehavioralMetrics(data, durationMs, notificationCount,
        // callCount)
        // val kotlinTimeMs = (System.nanoTime() - kotlinStartTime) / 1_000_000
        // android.util.Log.d(
        //         "BehaviorSDK",
        //         "Computed metrics using Kotlin (Calculation) - ${kotlinTimeMs}ms"
        // )

        // Compute Flux (Rust) - required, fail if unavailable
        var fluxMetrics: Map<String, Any>? = null
        var fluxTimeMs: Long = 0
        val fluxAvailable = FluxBridge.isAvailable()

        if (fluxAvailable) {
            try {
                val fluxStartTime = System.nanoTime()

                // Convert events to synheart-flux JSON format
                val fluxJson =
                        convertEventsToFluxJson(
                    sessionId = data.sessionId,
                    deviceId = "android-device", // TODO: Get actual device ID
                    timezone = java.util.TimeZone.getDefault().id,
                    startTimeMs = data.startTime,
                    endTimeMs = data.endTime,
                    events = data.events
                )

                android.util.Log.d(
                        "BehaviorSDK",
                        "Calling FluxBridge.behaviorToHsi with JSON length: ${fluxJson.length}"
                )

                // DEBUG: Log the JSON being sent to Flux (first 1000 chars)
                val jsonPreview =
                        if (fluxJson.length > 1000) {
                            fluxJson.substring(0, 1000) + "..."
                } else {
                            fluxJson
                        }
                android.util.Log.d("BehaviorSDK", "Flux JSON preview: $jsonPreview")

                val hsiJson = FluxBridge.behaviorToHsi(fluxJson)
                if (hsiJson != null) {
                    android.util.Log.d(
                            "BehaviorSDK",
                            "Got HSI JSON from Rust, length: ${hsiJson.length}"
                    )

                    // DEBUG: Log HSI JSON preview to see scroll jitter calculation
                    val hsiPreview =
                            if (hsiJson.length > 2000) {
                                hsiJson.substring(0, 2000) + "..."
                        } else {
                                hsiJson
                            }
                    android.util.Log.d("BehaviorSDK", "HSI JSON preview: $hsiPreview")
                    val metrics = extractBehavioralMetricsFromHsi(hsiJson)
                    if (metrics != null) {
                        fluxTimeMs = (System.nanoTime() - fluxStartTime) / 1_000_000
                        fluxMetrics = metrics
                        android.util.Log.d(
                                "BehaviorSDK",
                                "Successfully computed metrics using synheart-flux (Flux) - ${fluxTimeMs}ms"
                        )
                } else {
                        fluxTimeMs = (System.nanoTime() - fluxStartTime) / 1_000_000
                        android.util.Log.w("BehaviorSDK", "Failed to extract metrics from HSI JSON")
                    }
                        } else {
                    fluxTimeMs = (System.nanoTime() - fluxStartTime) / 1_000_000
                    android.util.Log.w(
                            "BehaviorSDK",
                            "Rust computation returned null (took ${fluxTimeMs}ms)"
                    )
                }
            } catch (e: Exception) {
                android.util.Log.w("BehaviorSDK", "Flux computation failed: ${e.message}")
                // Don't throw - just log the error and continue with Calculation results
            }
                    } else {
            android.util.Log.d("BehaviorSDK", "Flux is not available - skipping Flux computation")
        }

        // Build performance info with Flux execution time only
        val performanceInfo = mutableMapOf<String, Any>()
        if (fluxMetrics != null) {
            performanceInfo["flux_execution_time_ms"] = fluxTimeMs
            android.util.Log.i(
                    "BehaviorSDK",
                    "Computed metrics using Flux (Rust) - ${fluxTimeMs}ms"
            )
        }

        // Return empty map for calculationMetrics (not used anymore)
        return Triple(mapOf<String, Any>(), fluxMetrics, performanceInfo)
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

        // Compute clipboard summary (counts only; correction_rate and clipboard_activity_rate come from Flux)
        val clipboardEvents = filteredEvents.filter { it.eventType == "clipboard" }
        val clipboardCount = clipboardEvents.size
        val clipboardCopyCount = clipboardEvents.count { it.metrics["action"] == "copy" }
        val clipboardPasteCount = clipboardEvents.count { it.metrics["action"] == "paste" }
        val clipboardCutCount = clipboardEvents.count { it.metrics["action"] == "cut" }

        // Compute behavioral metrics using Flux (Rust) - same as endSession()
        val (_, fluxMetrics, _) =
                computeBehavioralMetricsWithFlux(tempData, duration, notificationCount, callCount)

        // Require Flux metrics - fail if not available
        if (fluxMetrics == null) {
            throw Exception(
                    "Flux is required but metrics are not available for time range calculation"
            )
        }

        // Extract behavioral metrics from Flux results
        val behavioralMetrics =
                fluxMetrics.filterKeys { key ->
                    key != "typing_session_summary" // Separate typing summary
                }

        // Extract typing session summary from Flux results (correction_rate and clipboard_activity_rate from Flux)
        val typingSessionSummary =
                fluxMetrics["typing_session_summary"] as? Map<String, Any>
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

        // Get motion data for the time range
        val allMotionData: List<MotionSignalCollector.MotionDataPoint> =
                if (sessionDataEntry != null) {
                    // Session is still active - get current motion data from collector
                    val currentMotionData: List<MotionSignalCollector.MotionDataPoint> =
                            motionSignalCollector.getCurrentMotionData()
                    currentMotionData.filter { dataPoint: MotionSignalCollector.MotionDataPoint ->
                        try {
                            val dataPointTime = Instant.parse(dataPoint.timestamp).toEpochMilli()
                            dataPointTime >= startTimestampMs && dataPointTime <= endTimestampMs
                        } catch (e: Exception) {
                            false // Skip invalid timestamps
                        }
                    }
                } else {
                    // Session has ended - motion data should be retrieved from stored data
                    // For now, return empty list (motion data persistence can be added later)
                    emptyList<MotionSignalCollector.MotionDataPoint>()
                }

        // Convert motion data to map format
        val motionDataList: List<Map<String, Any>> =
                allMotionData.map { dataPoint: MotionSignalCollector.MotionDataPoint ->
                    mapOf("timestamp" to dataPoint.timestamp, "features" to dataPoint.features)
                }

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
                "motion_data" to motionDataList
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
