package ai.synheart.behavior

import android.util.Log
import java.time.Instant
import org.json.JSONArray
import org.json.JSONObject

/**
 * Bridge to synheart-flux Rust library for behavioral metrics computation.
 *
 * This class provides JNI bindings to the Rust implementation of behavioral metrics, ensuring
 * consistent HSI-compliant output across all platforms.
 *
 * Note: The synheart-flux library must be built with JNI support (android feature flag) for this
 * bridge to work. Without JNI wrappers, the native methods will not be available.
 */
object FluxBridge {
    private const val TAG = "FluxBridge"
    private var libraryLoaded = false
    private var jniAvailable = false

    init {
        try {
            // First load the Rust library (libsynheart_flux.so)
            System.loadLibrary("synheart_flux")
            Log.d(TAG, "Successfully loaded libsynheart_flux.so")

            // Then load the JNI bridge library (libflux_jni_bridge.so)
            // This library links against libsynheart_flux.so and provides JNI functions
            System.loadLibrary("flux_jni_bridge")
            libraryLoaded = true
            Log.d(TAG, "Successfully loaded libflux_jni_bridge.so")

            // Test if JNI methods are actually available
            jniAvailable = testJniAvailability()
            if (jniAvailable) {
                Log.d(TAG, "JNI methods available")
            } else {
                Log.w(TAG, "Library loaded but JNI methods not available")
            }
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "Failed to load native libraries: ${e.message}")
            Log.w(TAG, "Falling back to Kotlin metric computation")
        }
    }

    private fun testJniAvailability(): Boolean {
        return try {
            // Try calling a native method to see if JNI is properly set up
            // This will throw UnsatisfiedLinkError if JNI methods aren't registered
            val handle = nativeProcessorNew(1)
            if (handle != 0L) {
                nativeProcessorFree(handle)
                true
            } else {
                false
            }
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "JNI methods not available: ${e.message}")
            false
        } catch (e: Exception) {
            Log.w(TAG, "Error testing JNI availability: ${e.message}")
            false
        }
    }

    /** Check if the Rust library is available and JNI is properly configured. */
    fun isAvailable(): Boolean = libraryLoaded && jniAvailable

    /**
     * Convert behavioral session to HSI JSON (stateless, one-shot).
     *
     * @param sessionJson JSON string containing the behavioral session data
     * @return HSI JSON string, or null if computation failed
     */
    fun behaviorToHsi(sessionJson: String): String? {
        if (!isAvailable()) {
            Log.w(TAG, "Rust library not initialized, cannot compute HSI")
            return null
        }
        return try {
            Log.d(TAG, "Calling nativeBehaviorToHsi with JSON length: ${sessionJson.length}")
            val result = nativeBehaviorToHsi(sessionJson)
            if (result == null) {
                // Get error message from Rust
                try {
                    val errorMsg = nativeLastError()
                    Log.w(
                            TAG,
                            "Rust computation returned null. Error: ${errorMsg ?: "Unknown error (error message also null)"}"
                    )
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to get error message from Rust: ${e.message}")
                }
                Log.d(TAG, "Input JSON (first 500 chars): ${sessionJson.take(500)}")
            } else {
                Log.d(TAG, "Rust computation succeeded, result length: ${result.length}")
            }
            result
        } catch (e: Exception) {
            Log.e(TAG, "Exception calling behaviorToHsi: ${e.message}", e)
            null
        }
    }

    /**
     * Create a stateful behavioral processor with the specified baseline window.
     *
     * @param baselineWindowSessions Number of sessions in the rolling baseline
     * @return Processor handle, or 0 if creation failed
     */
    fun createProcessor(baselineWindowSessions: Int = 20): Long {
        if (!isAvailable()) return 0
        return try {
            nativeProcessorNew(baselineWindowSessions)
        } catch (e: Exception) {
            Log.e(TAG, "Error creating processor: ${e.message}")
            0
        }
    }

    /** Free a processor created with createProcessor. */
    fun freeProcessor(handle: Long) {
        if (!isAvailable() || handle == 0L) return
        try {
            nativeProcessorFree(handle)
        } catch (e: Exception) {
            Log.e(TAG, "Error freeing processor: ${e.message}")
        }
    }

    /**
     * Process a behavioral session with the stateful processor.
     *
     * @param handle Processor handle from createProcessor
     * @param sessionJson JSON string containing the behavioral session data
     * @return HSI JSON string, or null if computation failed
     */
    fun processSession(handle: Long, sessionJson: String): String? {
        if (!isAvailable() || handle == 0L) return null
        return try {
            nativeProcessorProcess(handle, sessionJson)
        } catch (e: Exception) {
            Log.e(TAG, "Error processing session: ${e.message}")
            null
        }
    }

    /** Save baselines from a processor to JSON for persistence. */
    fun saveBaselines(handle: Long): String? {
        if (!isAvailable() || handle == 0L) return null
        return try {
            nativeProcessorSaveBaselines(handle)
        } catch (e: Exception) {
            Log.e(TAG, "Error saving baselines: ${e.message}")
            null
        }
    }

    /**
     * Load baselines into a processor from JSON.
     *
     * @return true if loading succeeded, false otherwise
     */
    fun loadBaselines(handle: Long, baselinesJson: String): Boolean {
        if (!isAvailable() || handle == 0L) return false
        return try {
            nativeProcessorLoadBaselines(handle, baselinesJson) == 0
        } catch (e: Exception) {
            Log.e(TAG, "Error loading baselines: ${e.message}")
            false
        }
    }

    // Native method declarations
    private external fun nativeBehaviorToHsi(sessionJson: String): String?
    private external fun nativeProcessorNew(baselineWindowSessions: Int): Long
    private external fun nativeProcessorFree(handle: Long)
    private external fun nativeProcessorProcess(handle: Long, sessionJson: String): String?
    private external fun nativeProcessorSaveBaselines(handle: Long): String?
    private external fun nativeProcessorLoadBaselines(handle: Long, baselinesJson: String): Int
    private external fun nativeLastError(): String?
}

/** Convert session events to synheart-flux JSON format. */
fun convertEventsToFluxJson(
        sessionId: String,
        deviceId: String,
        timezone: String,
        startTimeMs: Long,
        endTimeMs: Long,
        events: List<BehaviorEvent>
): String {
    val fluxEvents = JSONArray()

    // DEBUG: Count scroll events being sent to Flux
    var scrollEventCount = 0
    var scrollEventsWithReversal = 0
    var scrollEventsWithoutReversal = 0
    var scrollEventsWithoutScrollData = 0

    for (event in events) {
        val fluxEvent = JSONObject()
        fluxEvent.put("timestamp", event.timestamp)
        fluxEvent.put("event_type", event.eventType)

        when (event.eventType) {
            "scroll" -> {
                scrollEventCount++
                val hasReversal = event.metrics["direction_reversal"] as? Boolean ?: false
                val hasScrollData = event.metrics.containsKey("direction_reversal")

                if (hasScrollData) {
                    if (hasReversal) {
                        scrollEventsWithReversal++
                    } else {
                        scrollEventsWithoutReversal++
                    }
                } else {
                    scrollEventsWithoutScrollData++
                }

                val scroll = JSONObject()
                scroll.put("velocity", event.metrics["velocity"] ?: 0.0)
                scroll.put("direction", event.metrics["direction"] ?: "down")
                // Include direction_reversal if available (Flux accepts this field)
                val directionReversal = event.metrics["direction_reversal"]
                if (directionReversal != null) {
                    scroll.put("direction_reversal", directionReversal as? Boolean ?: false)
                }
                fluxEvent.put("scroll", scroll)
            }
            "tap" -> {
                val tap = JSONObject()
                tap.put("tap_duration_ms", event.metrics["tap_duration_ms"] ?: 0)
                tap.put("long_press", event.metrics["long_press"] ?: false)
                fluxEvent.put("tap", tap)
            }
            "swipe" -> {
                val swipe = JSONObject()
                swipe.put("velocity", event.metrics["velocity"] ?: 0.0)
                swipe.put("direction", event.metrics["direction"] ?: "unknown")
                fluxEvent.put("swipe", swipe)
            }
            "notification", "call" -> {
                val interruption = JSONObject()
                // Map action values to valid Rust enum values
                // Rust only accepts: ignored, opened, answered, dismissed
                val action =
                        when (event.metrics["action"]?.toString()?.lowercase()) {
                            "opened", "open" -> "opened"
                            "answered", "answer" -> "answered"
                            "dismissed", "dismiss" -> "dismissed"
                            "received" ->
                                    "ignored" // Map "received" to "ignored" since it hasn't been
                            // acted upon
                            "ignored",
                            "ignore" -> "ignored"
                            else -> "ignored" // Default to "ignored" for unknown values
                        }
                interruption.put("action", action)
                // Include source_app_id if available (Flux accepts this field)
                val sourceAppId = event.metrics["source_app_id"]
                if (sourceAppId != null) {
                    interruption.put("source_app_id", sourceAppId.toString())
                }
                fluxEvent.put("interruption", interruption)
            }
            "typing" -> {
                val typing = JSONObject()
                typing.put("typing_speed_cpm", event.metrics["typing_speed"] ?: 0.0)
                typing.put("cadence_stability", event.metrics["typing_cadence_stability"] ?: 0.0)
                // Include duration_sec if available (Flux accepts this field)
                val duration = event.metrics["duration"]
                if (duration != null) {
                    // Convert to seconds if it's in seconds, or keep as-is if already a number
                    val durationSec =
                            when (duration) {
                                is Number -> duration.toDouble()
                                is String -> duration.toDoubleOrNull() ?: 0.0
                                else -> 0.0
                            }
                    typing.put("duration_sec", durationSec)
                }
                // Include pause_count if available (Flux accepts this field)
                // Map typing_gap_count to pause_count as they represent the same concept
                val pauseCount = event.metrics["pause_count"] ?: event.metrics["typing_gap_count"]
                if (pauseCount != null) {
                    val pauseCountValue =
                            when (pauseCount) {
                                is Number -> pauseCount.toInt()
                                is String -> pauseCount.toIntOrNull() ?: 0
                                else -> 0
                            }
                    typing.put("pause_count", pauseCountValue)
                }
                // Include detailed typing metrics that Flux uses for aggregation
                // These are needed for Flux to calculate average_keystrokes_per_session,
                // average_typing_gap, average_inter_tap_interval, and burstiness_of_typing
                val typingTapCount = event.metrics["typing_tap_count"]
                android.util.Log.d(
                        "FluxBridge",
                        "Typing event - typing_tap_count in metrics: ${event.metrics.containsKey("typing_tap_count")}, value: $typingTapCount"
                )
                if (typingTapCount != null) {
                    val tapCountValue =
                            when (typingTapCount) {
                                is Number -> typingTapCount.toInt()
                                is String -> typingTapCount.toIntOrNull() ?: 0
                                else -> 0
                            }
                    typing.put("typing_tap_count", tapCountValue)
                    android.util.Log.d(
                            "FluxBridge",
                            "Added typing_tap_count to Flux JSON: $tapCountValue"
                    )
                } else {
                    android.util.Log.d(
                            "FluxBridge",
                            "WARNING: typing_tap_count not found in typing event metrics. Available keys: ${event.metrics.keys}"
                    )
                }
                val meanInterTapInterval = event.metrics["mean_inter_tap_interval_ms"]
                android.util.Log.d(
                        "FluxBridge",
                        "Typing event - mean_inter_tap_interval_ms in metrics: ${event.metrics.containsKey("mean_inter_tap_interval_ms")}, value: $meanInterTapInterval"
                )
                if (meanInterTapInterval != null) {
                    val itiValue =
                            when (meanInterTapInterval) {
                                is Number -> meanInterTapInterval.toDouble()
                                is String -> meanInterTapInterval.toDoubleOrNull() ?: 0.0
                                else -> 0.0
                            }
                    typing.put("mean_inter_tap_interval_ms", itiValue)
                    android.util.Log.d(
                            "FluxBridge",
                            "Added mean_inter_tap_interval_ms to Flux JSON: $itiValue"
                    )
                } else {
                    android.util.Log.d(
                            "FluxBridge",
                            "WARNING: mean_inter_tap_interval_ms not found in typing event metrics. Available keys: ${event.metrics.keys}"
                    )
                }
                val typingBurstiness = event.metrics["typing_burstiness"]
                android.util.Log.d(
                        "FluxBridge",
                        "Typing event - typing_burstiness in metrics: ${event.metrics.containsKey("typing_burstiness")}, value: $typingBurstiness"
                )
                if (typingBurstiness != null) {
                    val burstValue =
                            when (typingBurstiness) {
                                is Number -> typingBurstiness.toDouble()
                                is String -> typingBurstiness.toDoubleOrNull() ?: 0.0
                                else -> 0.0
                            }
                    typing.put("typing_burstiness", burstValue)
                    android.util.Log.d(
                            "FluxBridge",
                            "Added typing_burstiness to Flux JSON: $burstValue"
                    )
                } else {
                    android.util.Log.d(
                            "FluxBridge",
                            "WARNING: typing_burstiness not found in typing event metrics. Available keys: ${event.metrics.keys}"
                    )
                }
                // Include session boundaries if available
                val startAt = event.metrics["start_at"]
                if (startAt != null) {
                    typing.put("start_at", startAt.toString())
                }
                val endAt = event.metrics["end_at"]
                if (endAt != null) {
                    typing.put("end_at", endAt.toString())
                }
                fluxEvent.put("typing", typing)
            }
            "app_switch" -> {
                val appSwitch = JSONObject()
                appSwitch.put("from_app_id", event.metrics["from_app_id"] ?: "")
                appSwitch.put("to_app_id", event.metrics["to_app_id"] ?: "")
                fluxEvent.put("app_switch", appSwitch)
            }
        }

        fluxEvents.put(fluxEvent)
    }

    // DEBUG: Log what we're sending to Flux
    android.util.Log.d("FluxBridge", "=== CONVERTING TO FLUX JSON ===")
    android.util.Log.d("FluxBridge", "Total scroll events being sent: $scrollEventCount")
    android.util.Log.d("FluxBridge", "  - With reversal=true: $scrollEventsWithReversal")
    android.util.Log.d("FluxBridge", "  - With reversal=false: $scrollEventsWithoutReversal")
    android.util.Log.d(
            "FluxBridge",
            "  - Without direction_reversal field: $scrollEventsWithoutScrollData"
    )
    android.util.Log.d("FluxBridge", "=== END CONVERSION DEBUG ===")

    val session = JSONObject()
    session.put("session_id", sessionId)
    session.put("device_id", deviceId)
    session.put("timezone", timezone)
    session.put("start_time", Instant.ofEpochMilli(startTimeMs).toString())
    session.put("end_time", Instant.ofEpochMilli(endTimeMs).toString())
    session.put("events", fluxEvents)

    return session.toString()
}

/** Extract behavioral metrics from HSI JSON in the format expected by the SDK. */
fun extractBehavioralMetricsFromHsi(hsiJson: String): Map<String, Any>? {
    return try {
        val hsi = JSONObject(hsiJson)

        // HSI 1.0 format: axes.behavior.readings array
        val axes = hsi.optJSONObject("axes") ?: return null
        val behavior = axes.optJSONObject("behavior") ?: return null
        val readings = behavior.optJSONArray("readings") ?: return null

        // Extract metrics from axis readings
        val metricsMap = mutableMapOf<String, Double>()
        for (i in 0 until readings.length()) {
            val reading = readings.getJSONObject(i)
            val axis = reading.optString("axis", "")
            val score = reading.optDouble("score", Double.NaN)
            if (!score.isNaN()) {
                metricsMap[axis] = score
            }
        }

        // Extract meta information
        val meta = hsi.optJSONObject("meta")

        // DEBUG: Log scroll jitter rate from Flux
        val scrollJitterFromFlux = metricsMap["scroll_jitter_rate"] ?: 0.0
        android.util.Log.d("FluxBridge", "=== FLUX SCROLL JITTER DEBUG ===")
        android.util.Log.d("FluxBridge", "Scroll jitter rate from Flux: $scrollJitterFromFlux")

        // Try to extract meta info for scroll events count
        val totalEvents = meta?.optInt("total_events") ?: -1
        android.util.Log.d("FluxBridge", "Total events in Flux meta: $totalEvents")

        // Try to find scroll_events in meta or calculate from readings
        // Note: Flux doesn't expose scroll_events count directly, but we can infer from the
        // calculation
        // scroll_jitter_rate = reversals / (scroll_events - 1)
        // If we had reversals count, we could calculate: scroll_events = reversals /
        // scroll_jitter_rate + 1
        android.util.Log.d("FluxBridge", "=== END FLUX SCROLL JITTER DEBUG ===")

        // DEBUG: Log deep focus blocks information
        android.util.Log.d("FluxBridge", "=== FLUX DEEP FOCUS BLOCKS DEBUG ===")
        val deepFocusBlocksCount = meta?.optInt("deep_focus_blocks") ?: 0
        android.util.Log.d("FluxBridge", "Deep focus blocks count from Flux: $deepFocusBlocksCount")

        // Log session duration
        val sessionDurationSec = meta?.optDouble("duration_sec") ?: 0.0
        android.util.Log.d("FluxBridge", "Session duration (seconds): $sessionDurationSec")

        // Log deep focus blocks detail if available
        val deepFocusDetail = meta?.optJSONArray("deep_focus_blocks_detail")
        if (deepFocusDetail != null && deepFocusDetail.length() > 0) {
            android.util.Log.d(
                    "FluxBridge",
                    "Deep focus blocks detail found: ${deepFocusDetail.length()} blocks"
            )
            for (i in 0 until deepFocusDetail.length()) {
                val block = deepFocusDetail.getJSONObject(i)
                val startAt = block.optString("start_at", "")
                val endAt = block.optString("end_at", "")
                val durationMs = block.optInt("duration_ms", 0)
                android.util.Log.d(
                        "FluxBridge",
                        "  Block[$i]: start=$startAt, end=$endAt, duration=${durationMs}ms (${durationMs / 1000.0}s)"
                )
            }
        } else {
            android.util.Log.d("FluxBridge", "No deep focus blocks detail found in meta")
            android.util.Log.d(
                    "FluxBridge",
                    "This means no engagement segments >= 120 seconds were detected"
            )
        }

        // Log all meta keys for debugging
        if (meta != null) {
            val metaKeys = meta.keys()
            val keysList = mutableListOf<String>()
            while (metaKeys.hasNext()) {
                keysList.add(metaKeys.next())
            }
            android.util.Log.d("FluxBridge", "Available meta keys: ${keysList.joinToString(", ")}")
        }

        android.util.Log.d("FluxBridge", "=== END FLUX DEEP FOCUS BLOCKS DEBUG ===")

        // Build result map with SDK-expected field names
        val result = mutableMapOf<String, Any>()
        result["interaction_intensity"] = metricsMap["interaction_intensity"] ?: 0.0
        result["task_switch_rate"] = metricsMap["task_switch_rate"] ?: 0.0
        // Flux outputs task_switch_cost as normalized 0-1 in HSI, but SDK expects raw ms
        // For now, we'll extract the normalized value (0-1) from Flux
        // Note: Kotlin calculates raw ms (0-10000), Flux calculates normalized (0-1)
        val taskSwitchCostNormalized = metricsMap["task_switch_cost"] ?: 0.0
        // Convert normalized back to raw ms for SDK compatibility: normalized * 10000
        result["task_switch_cost"] = (taskSwitchCostNormalized * 10000.0).toInt()
        result["idle_time_ratio"] = metricsMap["idle_ratio"] ?: 0.0
        // Flux outputs active_time_ratio directly in HSI readings
        result["active_time_ratio"] =
                metricsMap["active_time_ratio"] ?: (1.0 - (metricsMap["idle_ratio"] ?: 0.0))
        result["notification_load"] = metricsMap["notification_load"] ?: 0.0
        result["burstiness"] = metricsMap["burstiness"] ?: 0.0
        result["behavioral_distraction_score"] = metricsMap["distraction"] ?: 0.0
        result["focus_hint"] = metricsMap["focus"] ?: 0.0
        result["fragmented_idle_ratio"] = metricsMap["fragmented_idle_ratio"] ?: 0.0
        result["scroll_jitter_rate"] = metricsMap["scroll_jitter_rate"] ?: 0.0
        // Extract deep focus blocks detail as a List (matching Kotlin's format)
        // Kotlin returns List<Map<String, Any>>, so we need to match that format
        val deepFocusBlocksDetail = meta?.optJSONArray("deep_focus_blocks_detail")
        result["deep_focus_blocks"] =
                if (deepFocusBlocksDetail != null) {
                    extractDeepFocusBlocks(deepFocusBlocksDetail)
                } else {
                    emptyList<Map<String, Any>>()
                }
        result["sessions_in_baseline"] = meta?.optInt("sessions_in_baseline") ?: 0

        // Add baseline info from meta if available
        meta?.optDouble("baseline_distraction")?.let { result["baseline_distraction"] = it }
        meta?.optDouble("baseline_focus")?.let { result["baseline_focus"] = it }
        meta?.optDouble("distraction_deviation_pct")?.let {
            result["distraction_deviation_pct"] = it
        }

        // Extract typing session summary from Flux's meta
        // Always extract and add it (even if all zeros) so we can compare with Calculation
        val typingSummary = extractTypingSessionSummary(meta)
        android.util.Log.d(
                "FluxBridge",
                "Extracted typing summary: keys=${typingSummary.keys}, typing_session_count=${typingSummary["typing_session_count"]}"
        )
        result["typing_session_summary"] = typingSummary
        android.util.Log.d("FluxBridge", "Added typing_session_summary to result map")

        result
    } catch (e: Exception) {
        Log.e("FluxBridge", "Failed to extract metrics from HSI: ${e.message}", e)
        null
    }
}

private fun extractDeepFocusBlocks(blocks: JSONArray?): List<Map<String, Any>> {
    if (blocks == null) return emptyList()
    return (0 until blocks.length()).map { i ->
        val block = blocks.getJSONObject(i)
        mapOf(
                "start_at" to block.optString("start_at", ""),
                "end_at" to block.optString("end_at", ""),
                "duration_ms" to block.optInt("duration_ms", 0)
        )
    }
}

/** Extract typing session summary from Flux's meta section. */
private fun extractTypingSessionSummary(meta: JSONObject?): Map<String, Any> {
    if (meta == null) {
        android.util.Log.d("FluxBridge", "extractTypingSessionSummary: meta is null")
        return emptyMap()
    }

    val typingSessionCount = meta.optInt("typing_session_count") ?: 0
    android.util.Log.d(
            "FluxBridge",
            "extractTypingSessionSummary: typing_session_count=$typingSessionCount"
    )

    // Always return the map (even if all zeros) so we can compare with Calculation
    return mapOf(
            "typing_session_count" to typingSessionCount,
            "average_keystrokes_per_session" to
                    (meta.optDouble("average_keystrokes_per_session") ?: 0.0),
            "average_typing_session_duration" to
                    (meta.optDouble("average_typing_session_duration") ?: 0.0),
            "average_typing_speed" to (meta.optDouble("average_typing_speed") ?: 0.0),
            "average_typing_gap" to (meta.optDouble("average_typing_gap") ?: 0.0),
            "average_inter_tap_interval" to (meta.optDouble("average_inter_tap_interval") ?: 0.0),
            "typing_cadence_stability" to (meta.optDouble("typing_cadence_stability") ?: 0.0),
            "burstiness_of_typing" to (meta.optDouble("burstiness_of_typing") ?: 0.0),
            "total_typing_duration" to (meta.optInt("total_typing_duration") ?: 0),
            "active_typing_ratio" to (meta.optDouble("active_typing_ratio") ?: 0.0),
            "typing_contribution_to_interaction_intensity" to
                    (meta.optDouble("typing_contribution_to_interaction_intensity") ?: 0.0),
            "deep_typing_blocks" to (meta.optInt("deep_typing_blocks") ?: 0),
            "typing_fragmentation" to (meta.optDouble("typing_fragmentation") ?: 0.0),
            "typing_metrics" to extractTypingMetrics(meta.optJSONArray("typing_metrics"))
    )
}

/** Extract individual typing session metrics from Flux's typing_metrics array. */
private fun extractTypingMetrics(metricsArray: JSONArray?): List<Map<String, Any>> {
    if (metricsArray == null) return emptyList()
    return (0 until metricsArray.length()).map { i ->
        val metric = metricsArray.getJSONObject(i)
        mapOf(
                "start_at" to metric.optString("start_at", ""),
                "end_at" to metric.optString("end_at", ""),
                "duration" to metric.optInt("duration", 0),
                "deep_typing" to (metric.optBoolean("deep_typing") ?: false),
                "typing_tap_count" to metric.optInt("typing_tap_count", 0),
                "typing_speed" to metric.optDouble("typing_speed", 0.0),
                "mean_inter_tap_interval_ms" to metric.optDouble("mean_inter_tap_interval_ms", 0.0),
                "typing_cadence_variability" to metric.optDouble("typing_cadence_variability", 0.0),
                "typing_cadence_stability" to metric.optDouble("typing_cadence_stability", 0.0),
                "typing_gap_count" to metric.optInt("typing_gap_count", 0),
                "typing_gap_ratio" to metric.optDouble("typing_gap_ratio", 0.0),
                "typing_burstiness" to metric.optDouble("typing_burstiness", 0.0),
                "typing_activity_ratio" to metric.optDouble("typing_activity_ratio", 0.0),
                "typing_interaction_intensity" to
                        metric.optDouble("typing_interaction_intensity", 0.0)
        )
    }
}
