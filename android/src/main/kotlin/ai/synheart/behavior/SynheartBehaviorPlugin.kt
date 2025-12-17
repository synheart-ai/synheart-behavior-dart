package ai.synheart.behavior

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.view.View
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
            behaviorSDK?.endSession(sessionId)?.toMap()
                    ?: mapOf(
                            "session_id" to sessionId,
                            "start_timestamp" to System.currentTimeMillis(),
                            "end_timestamp" to System.currentTimeMillis(),
                            "duration" to 0,
                            "event_count" to 0,
                            "average_typing_cadence" to null,
                            "average_scroll_velocity" to null,
                            "app_switch_count" to 0,
                            "stability_index" to null,
                            "fragmentation_index" to null,
                    )
        } catch (e: Exception) {
            mapOf(
                    "session_id" to sessionId,
                    "start_timestamp" to System.currentTimeMillis(),
                    "end_timestamp" to System.currentTimeMillis(),
                    "duration" to 0,
                    "event_count" to 0,
                    "average_typing_cadence" to null,
                    "average_scroll_velocity" to null,
                    "app_switch_count" to 0,
                    "stability_index" to null,
                    "fragmentation_index" to null,
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
        channel.invokeMethod("onEvent", event)
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
