package ai.synheart.behavior

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.view.View
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class SynheartBehaviorPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var rootView: View? = null
    private var context: Context? = null
    private var behaviorSDK: BehaviorSDK? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "ai.synheart.behavior")
        channel.setMethodCallHandler(this)
        context = binding.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> {
                @Suppress("UNCHECKED_CAST")
                val config = (call.arguments as? Map<String, Any>) ?: emptyMap()
                initialize(config)
                result.success(null)
            }
            "startSession" -> {
                @Suppress("UNCHECKED_CAST")
                val args = (call.arguments as? Map<String, Any>) ?: emptyMap()
                val sessionId = args["sessionId"] as? String ?: generateSessionId()
                startSession(sessionId)
                result.success(null)
            }
            "getCurrentStats" -> {
                val stats = getCurrentStats()
                result.success(stats)
            }
            "endSession" -> {
                @Suppress("UNCHECKED_CAST")
                val args = (call.arguments as? Map<String, Any>) ?: emptyMap()
                val sessionId = args["sessionId"] as? String ?: ""
                val summary = endSession(sessionId)
                result.success(summary)
            }
            "updateConfig" -> {
                @Suppress("UNCHECKED_CAST")
                val config = (call.arguments as? Map<String, Any>) ?: emptyMap()
                updateConfig(config)
                result.success(null)
            }
            "dispose" -> {
                dispose()
                result.success(null)
            }
            "checkNotificationPermission" -> {
                val hasPermission = checkNotificationPermission()
                result.success(hasPermission)
            }
            "requestNotificationPermission" -> {
                requestNotificationPermission()
                result.success(null)
            }
            "checkCallPermission" -> {
                val hasPermission = checkCallPermission()
                result.success(hasPermission)
            }
            "requestCallPermission" -> {
                requestCallPermission()
                result.success(null)
            }
            "sendEvent" -> {
                @Suppress("UNCHECKED_CAST")
                val eventData = (call.arguments as? Map<String, Any>) ?: emptyMap()
                sendEvent(eventData)
                result.success(null)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun initialize(config: Map<String, Any>) {
        val behaviorConfig =
                BehaviorConfig(
                        enableInputSignals = config["enableInputSignals"] as? Boolean ?: true,
                        enableAttentionSignals = config["enableAttentionSignals"] as? Boolean
                                        ?: true,
                        enableMotionLite = config["enableMotionLite"] as? Boolean ?: false,
                        sessionIdPrefix = config["sessionIdPrefix"] as? String,
                        eventBatchSize = config["eventBatchSize"] as? Int ?: 10,
                        maxIdleGapSeconds = config["maxIdleGapSeconds"] as? Double ?: 10.0
                )

        behaviorSDK = BehaviorSDK(context!!, behaviorConfig)
        behaviorSDK?.initialize()
        behaviorSDK?.setEventHandler { event -> emitEvent(event.toMap()) }
    }

    private fun startSession(sessionId: String) {
        behaviorSDK?.startSession(sessionId)
    }

    private fun getCurrentStats(): Map<String, Any?> {
        return behaviorSDK?.getCurrentStats()?.toMap()
                ?: mapOf(
                        "timestamp" to System.currentTimeMillis(),
                        "typing_cadence" to null,
                        "inter_key_latency" to null,
                        "burst_length" to null,
                        "scroll_velocity" to null,
                        "scroll_acceleration" to null,
                        "scroll_jitter" to null,
                        "tap_rate" to null,
                        "app_switches_per_minute" to 0,
                        "foreground_duration" to null,
                        "idle_gap_seconds" to null,
                        "stability_index" to null,
                        "fragmentation_index" to null,
                )
    }

    private fun endSession(sessionId: String): Map<String, Any?> {
        return try {
            behaviorSDK?.endSession(sessionId)
                    ?: mapOf(
                            "session_id" to sessionId,
                            "start_at" to java.time.Instant.now().toString(),
                            "end_at" to java.time.Instant.now().toString(),
                            "micro_session" to false,
                            "OS" to "Android",
                            "session_spacing" to 0,
                            "device_context" to
                                    mapOf(
                                            "avg_screen_brightness" to 0.0,
                                            "start_orientation" to "portrait",
                                            "orientation_changes" to 0
                                    ),
                            "activity_summary" to
                                    mapOf("total_events" to 0, "app_switch_count" to 0),
                            "behavioral_metrics" to mapOf<String, Any>(),
                            "notification_summary" to mapOf<String, Any>(),
                            "system_state" to mapOf<String, Any>()
                    )
        } catch (e: Exception) {
            mapOf(
                    "session_id" to sessionId,
                    "start_at" to java.time.Instant.now().toString(),
                    "end_at" to java.time.Instant.now().toString(),
                    "micro_session" to false,
                    "OS" to "Android",
                    "session_spacing" to 0,
                    "device_context" to
                            mapOf(
                                    "avg_screen_brightness" to 0.0,
                                    "start_orientation" to "portrait",
                                    "orientation_changes" to 0
                            ),
                    "activity_summary" to mapOf("total_events" to 0, "app_switch_count" to 0),
                    "behavioral_metrics" to mapOf<String, Any>(),
                    "notification_summary" to mapOf<String, Any>(),
                    "system_state" to mapOf<String, Any>()
            )
        }
    }

    private fun updateConfig(config: Map<String, Any>) {
        val behaviorConfig =
                BehaviorConfig(
                        enableInputSignals = config["enableInputSignals"] as? Boolean ?: true,
                        enableAttentionSignals = config["enableAttentionSignals"] as? Boolean
                                        ?: true,
                        enableMotionLite = config["enableMotionLite"] as? Boolean ?: false,
                        sessionIdPrefix = config["sessionIdPrefix"] as? String,
                        eventBatchSize = config["eventBatchSize"] as? Int ?: 10,
                        maxIdleGapSeconds = config["maxIdleGapSeconds"] as? Double ?: 10.0
                )
        behaviorSDK?.updateConfig(behaviorConfig)
    }

    private fun dispose() {
        behaviorSDK?.dispose()
        behaviorSDK = null
    }

    private fun emitEvent(event: Map<String, Any>) {
        android.util.Log.d("SynheartBehaviorPlugin", "emitEvent called, sending to Flutter channel")
        try {
            channel.invokeMethod("onEvent", event)
            android.util.Log.d(
                    "SynheartBehaviorPlugin",
                    "Event sent to Flutter channel successfully"
            )
        } catch (e: Exception) {
            android.util.Log.e(
                    "SynheartBehaviorPlugin",
                    "ERROR sending event to Flutter: ${e.message}",
                    e
            )
        }
    }

    private fun generateSessionId(): String {
        return "SESS-${System.currentTimeMillis()}"
    }

    private fun checkNotificationPermission(): Boolean {
        val context = this.context ?: return false
        val enabledListeners =
                Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
                        ?: return false

        val packageName = context.packageName
        return enabledListeners.contains(packageName)
    }

    private fun requestNotificationPermission() {
        val activity = this.activity ?: return
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        activity.startActivity(intent)
    }

    private fun checkCallPermission(): Boolean {
        val context = this.context ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ContextCompat.checkSelfPermission(
                    context,
                    android.Manifest.permission.READ_PHONE_STATE
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            // Permission granted by default on older Android versions
            true
        }
    }

    private fun requestCallPermission() {
        val activity = this.activity ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!checkCallPermission()) {
                ActivityCompat.requestPermissions(
                        activity,
                        arrayOf(android.Manifest.permission.READ_PHONE_STATE),
                        1001 // Request code for call permission
                )
            }
        }
    }

    private fun sendEvent(eventData: Map<String, Any>) {
        val behaviorSDK = this.behaviorSDK ?: return

        try {
            // Parse event data from Dart
            // Format: {"event": {"event_id": "...", "session_id": "...", "timestamp": "...",
            // "event_type": "...", "metrics": {...}}}
            val eventMap = eventData["event"] as? Map<String, Any> ?: eventData
            val eventId = eventMap["event_id"] as? String ?: "evt_${System.currentTimeMillis()}"
            val sessionId = eventMap["session_id"] as? String ?: "current"
            val timestamp = eventMap["timestamp"] as? String ?: java.time.Instant.now().toString()
            val eventType = eventMap["event_type"] as? String ?: "tap"
            @Suppress("UNCHECKED_CAST")
            val metrics = eventMap["metrics"] as? Map<String, Any> ?: emptyMap()

            val event =
                    BehaviorEvent(
                            eventId = eventId,
                            sessionId = sessionId,
                            timestamp = timestamp,
                            eventType = eventType,
                            metrics = metrics
                    )

            // Use reflection or make emitEvent public - for now, let's create a public method
            // Actually, we need to add a public method to BehaviorSDK to receive events from
            // Flutter
            behaviorSDK.receiveEventFromFlutter(event)
        } catch (e: Exception) {
            android.util.Log.e(
                    "SynheartBehaviorPlugin",
                    "Error parsing event from Flutter: ${e.message}",
                    e
            )
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        rootView = activity?.window?.decorView?.rootView

        // Attach SDK to root view for signal collection
        rootView?.let { view -> behaviorSDK?.attachToView(view) }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        rootView = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        rootView = activity?.window?.decorView?.rootView
    }

    override fun onDetachedFromActivity() {
        activity = null
        rootView = null
    }
}
