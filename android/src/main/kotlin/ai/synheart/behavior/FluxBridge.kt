package ai.synheart.behavior

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

/**
 * Bridge to synheart-flux Rust library for behavioral metrics computation.
 *
 * This class provides JNI bindings to the Rust implementation of behavioral metrics,
 * ensuring consistent HSI-compliant output across all platforms.
 *
 * Note: The synheart-flux library must be built with JNI support (android feature flag)
 * for this bridge to work. Without JNI wrappers, the native methods will not be available.
 */
object FluxBridge {
    private const val TAG = "FluxBridge"
    private var libraryLoaded = false
    private var jniAvailable = false

    init {
        try {
            System.loadLibrary("synheart_flux")
            libraryLoaded = true
            Log.d(TAG, "Successfully loaded libsynheart_flux.so")

            // Test if JNI methods are actually available
            jniAvailable = testJniAvailability()
            if (jniAvailable) {
                Log.d(TAG, "JNI methods available")
            } else {
                Log.w(TAG, "Library loaded but JNI methods not available")
            }
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "Failed to load libsynheart_flux.so: ${e.message}")
            Log.w(TAG, "Falling back to Kotlin metric computation")
        }
    }

    private fun testJniAvailability(): Boolean {
        return try {
            // Try calling a native method to see if JNI is properly set up
            // This will throw UnsatisfiedLinkError if JNI methods aren't registered
            nativeProcessorNew(1)?.let { handle ->
                nativeProcessorFree(handle)
                true
            } ?: false
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "JNI methods not available: ${e.message}")
            false
        } catch (e: Exception) {
            Log.w(TAG, "Error testing JNI availability: ${e.message}")
            false
        }
    }

    /**
     * Check if the Rust library is available and JNI is properly configured.
     */
    fun isAvailable(): Boolean = libraryLoaded && jniAvailable

    /**
     * Convert behavioral session to HSI JSON (stateless, one-shot).
     *
     * @param sessionJson JSON string containing the behavioral session data
     * @return HSI JSON string, or null if computation failed
     */
    fun behaviorToHsi(sessionJson: String): String? {
        if (!initialized) {
            Log.w(TAG, "Rust library not initialized, cannot compute HSI")
            return null
        }
        return try {
            nativeBehaviorToHsi(sessionJson)
        } catch (e: Exception) {
            Log.e(TAG, "Error calling behaviorToHsi: ${e.message}")
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
        if (!initialized) return 0
        return try {
            nativeProcessorNew(baselineWindowSessions)
        } catch (e: Exception) {
            Log.e(TAG, "Error creating processor: ${e.message}")
            0
        }
    }

    /**
     * Free a processor created with createProcessor.
     */
    fun freeProcessor(handle: Long) {
        if (!initialized || handle == 0L) return
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
        if (!initialized || handle == 0L) return null
        return try {
            nativeProcessorProcess(handle, sessionJson)
        } catch (e: Exception) {
            Log.e(TAG, "Error processing session: ${e.message}")
            null
        }
    }

    /**
     * Save baselines from a processor to JSON for persistence.
     */
    fun saveBaselines(handle: Long): String? {
        if (!initialized || handle == 0L) return null
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
        if (!initialized || handle == 0L) return false
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
}

/**
 * Convert session events to synheart-flux JSON format.
 */
fun convertEventsToFluxJson(
    sessionId: String,
    deviceId: String,
    timezone: String,
    startTimeMs: Long,
    endTimeMs: Long,
    events: List<BehaviorEvent>
): String {
    val fluxEvents = JSONArray()

    for (event in events) {
        val fluxEvent = JSONObject()
        fluxEvent.put("timestamp", event.timestamp)
        fluxEvent.put("event_type", event.eventType)

        when (event.eventType) {
            "scroll" -> {
                val scroll = JSONObject()
                scroll.put("velocity", event.metrics["velocity"] ?: 0.0)
                scroll.put("direction", event.metrics["direction"] ?: "down")
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
                interruption.put("action", event.metrics["action"] ?: "ignored")
                fluxEvent.put("interruption", interruption)
            }
            "typing" -> {
                val typing = JSONObject()
                typing.put("typing_speed_cpm", event.metrics["typing_speed"] ?: 0.0)
                typing.put("cadence_stability", event.metrics["typing_cadence_stability"] ?: 0.0)
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

    val session = JSONObject()
    session.put("session_id", sessionId)
    session.put("device_id", deviceId)
    session.put("timezone", timezone)
    session.put("start_time", Instant.ofEpochMilli(startTimeMs).toString())
    session.put("end_time", Instant.ofEpochMilli(endTimeMs).toString())
    session.put("events", fluxEvents)

    return session.toString()
}

/**
 * Extract behavioral metrics from HSI JSON in the format expected by the SDK.
 */
fun extractBehavioralMetricsFromHsi(hsiJson: String): Map<String, Any>? {
    return try {
        val hsi = JSONObject(hsiJson)
        val behaviorWindows = hsi.optJSONArray("behavior_windows")
        if (behaviorWindows == null || behaviorWindows.length() == 0) return null

        val window = behaviorWindows.getJSONObject(0)
        val behavior = window.optJSONObject("behavior") ?: return null
        val baseline = window.optJSONObject("baseline")
        val eventSummary = window.optJSONObject("event_summary")

        mapOf(
            "interaction_intensity" to behavior.optDouble("interaction_intensity", 0.0),
            "task_switch_rate" to behavior.optDouble("task_switch_rate", 0.0),
            "task_switch_cost" to 0,
            "idle_time_ratio" to behavior.optDouble("idle_ratio", 0.0),
            "active_time_ratio" to (1.0 - behavior.optDouble("idle_ratio", 0.0)),
            "notification_load" to behavior.optDouble("notification_load", 0.0),
            "burstiness" to behavior.optDouble("burstiness", 0.0),
            "behavioral_distraction_score" to behavior.optDouble("distraction_score", 0.0),
            "focus_hint" to behavior.optDouble("focus_hint", 0.0),
            "fragmented_idle_ratio" to behavior.optDouble("fragmented_idle_ratio", 0.0),
            "scroll_jitter_rate" to behavior.optDouble("scroll_jitter_rate", 0.0),
            "deep_focus_blocks" to extractDeepFocusBlocks(behavior.optJSONArray("deep_focus_blocks")),
            // Baseline info
            "baseline_distraction" to baseline?.optDouble("distraction"),
            "baseline_focus" to baseline?.optDouble("focus"),
            "distraction_deviation_pct" to baseline?.optDouble("distraction_deviation_pct"),
            "sessions_in_baseline" to (baseline?.optInt("sessions_in_baseline") ?: 0)
        )
    } catch (e: Exception) {
        Log.e("FluxBridge", "Failed to extract metrics from HSI: ${e.message}")
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
