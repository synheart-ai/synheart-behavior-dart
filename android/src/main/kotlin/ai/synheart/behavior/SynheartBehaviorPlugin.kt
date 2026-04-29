package ai.synheart.behavior

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.view.ActionMode
import android.view.KeyEvent
import android.view.Menu
import android.view.MenuItem
import android.view.MotionEvent
import android.view.SearchEvent
import android.view.View
import android.view.Window
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
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
    // Original Window.Callback owned by the Activity; we wrap it with
    // TouchForwardingCallback so we can observe every touch at the window
    // level (before Flutter's surface consumes it). Restored on detach.
    private var originalWindowCallback: Window.Callback? = null

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
            "calculateMetricsForTimeRange" -> {
                @Suppress("UNCHECKED_CAST")
                val args = (call.arguments as? Map<String, Any>) ?: emptyMap()
                val startTimestampMs = args["startTimestampMs"] as? Long ?: 0L
                val endTimestampMs = args["endTimestampMs"] as? Long ?: 0L
                val sessionId = args["sessionId"] as? String
                try {
                    val metrics =
                            calculateMetricsForTimeRange(
                                    startTimestampMs = startTimestampMs,
                                    endTimestampMs = endTimestampMs,
                                    sessionId = sessionId
                            )
                    result.success(metrics)
                } catch (e: Exception) {
                    result.error("CALCULATION_ERROR", e.message, null)
                }
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
                        emitRawMotionSamples = config["emitRawMotionSamples"] as? Boolean ?: false,
                        sessionIdPrefix = config["sessionIdPrefix"] as? String,
                        eventBatchSize = config["eventBatchSize"] as? Int ?: 10,
                        maxIdleGapSeconds = config["maxIdleGapSeconds"] as? Double ?: 10.0
                )

        behaviorSDK = BehaviorSDK(context!!, behaviorConfig)
        behaviorSDK?.initialize()
        behaviorSDK?.setEventHandler { event -> emitEvent(event.toMap()) }
        behaviorSDK?.setMotionSampleBatchHandler { batch ->
            channel.invokeMethod("onMotionSampleBatch", mapOf("samples" to batch))
        }

        // Activity may have already attached BEFORE Dart called initialize()
        // — FlutterPlugin lifecycle on Android fires `onAttachedToActivity`
        // before the Dart isolate sends `initialize`. In that window the SDK
        // didn't exist yet, so the earlier `behaviorSDK?.attachToView(...)`
        // call in onAttachedToActivity no-op'd. Re-attach here so the
        // `GestureCollector` / `InputSignalCollector` OnTouchListeners land
        // on the root view and taps actually reach `emitEvent`. Without
        // this, the Android pipeline is silent while iOS works (iOS captures
        // via UIWindow-level hooks that don't have this ordering race).
        rootView?.let { view ->
            android.util.Log.d(
                "SynheartBehaviorPlugin",
                "initialize(): re-attaching SDK to rootView=${view.javaClass.simpleName}"
            )
            behaviorSDK?.attachToView(view)
        } ?: android.util.Log.w(
            "SynheartBehaviorPlugin",
            "initialize(): no rootView yet — SDK will attach in onAttachedToActivity"
        )
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
                        emitRawMotionSamples = config["emitRawMotionSamples"] as? Boolean ?: false,
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

    private fun calculateMetricsForTimeRange(
            startTimestampMs: Long,
            endTimestampMs: Long,
            sessionId: String?
    ): Map<String, Any?> {
        val behaviorSDK = this.behaviorSDK ?: throw Exception("SDK not initialized")
        return behaviorSDK.calculateMetricsForTimeRange(
                startTimestampMs = startTimestampMs,
                endTimestampMs = endTimestampMs,
                sessionId = sessionId
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        rootView = activity?.window?.decorView?.rootView

        // Install the Window.Callback wrap once we have an activity. Touches
        // captured here flow THROUGH the wrap to Flutter unchanged — we only
        // read them. This is the reliable capture path in a Flutter host;
        // the view-attached OnTouchListener route only fires when no child
        // consumed, which Flutter's embedded surface always does.
        installWindowCallbackWrap()

        // Attach SDK to root view for signal collection.
        // Note: `behaviorSDK` may still be null here — FlutterPlugin fires
        // this before Dart has a chance to call `initialize`. The matching
        // re-attach in `initialize()` covers that case.
        if (behaviorSDK != null) {
            rootView?.let { view ->
                android.util.Log.d(
                    "SynheartBehaviorPlugin",
                    "onAttachedToActivity: attaching SDK to ${view.javaClass.simpleName}"
                )
                behaviorSDK?.attachToView(view)
            }
        } else {
            android.util.Log.d(
                "SynheartBehaviorPlugin",
                "onAttachedToActivity: SDK not initialized yet — deferring attach to initialize()"
            )
        }

        // Register for configuration changes to track orientation
        // We'll check orientation changes periodically since ActivityPluginBinding
        // doesn't have a direct configuration change listener
        // The BehaviorSDK will check orientation on its own via a different mechanism
    }

    /**
     * Wrap `activity.window.callback` so every touch dispatched to the
     * window flows through our forwarding callback — before Flutter's
     * embedded surface consumes it. Idempotent: if the current callback
     * is already our wrap, we no-op.
     */
    private fun installWindowCallbackWrap() {
        val a = activity ?: return
        val current = a.window.callback
        if (current is TouchForwardingCallback) {
            android.util.Log.d(
                "SynheartBehaviorPlugin",
                "installWindowCallbackWrap: already installed"
            )
            return
        }
        originalWindowCallback = current
        a.window.callback = TouchForwardingCallback(current) { event ->
            behaviorSDK?.feedTouchEvent(event)
        }
        android.util.Log.d(
            "SynheartBehaviorPlugin",
            "installWindowCallbackWrap: installed over ${current?.javaClass?.simpleName}"
        )
    }

    private fun restoreWindowCallback() {
        val a = activity ?: return
        val current = a.window.callback
        if (current is TouchForwardingCallback && originalWindowCallback != null) {
            a.window.callback = originalWindowCallback
            android.util.Log.d(
                "SynheartBehaviorPlugin",
                "restoreWindowCallback: restored ${originalWindowCallback?.javaClass?.simpleName}"
            )
        }
        originalWindowCallback = null
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        rootView = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        rootView = activity?.window?.decorView?.rootView
        installWindowCallbackWrap()
    }

    override fun onDetachedFromActivity() {
        restoreWindowCallback()
        activity = null
        rootView = null
    }

    /**
     * Window.Callback wrapper that forwards every touch event to
     * [onTouchReceived] (a non-consuming observer) and then delegates the
     * full Window.Callback surface to the original callback Android installed.
     *
     * Delegating the entire interface — not just `dispatchTouchEvent` — is
     * important: Flutter's embedding and the Android platform both depend
     * on dozens of callbacks firing correctly (menu, action mode, window
     * focus, etc.). Forwarding every method keeps the host indistinguishable
     * from the un-wrapped state, so installing this wrap has no functional
     * side effects beyond the extra read.
     */
    private class TouchForwardingCallback(
        private val delegate: Window.Callback?,
        private val onTouchReceived: (MotionEvent) -> Unit,
    ) : Window.Callback {

        override fun dispatchKeyEvent(event: KeyEvent): Boolean =
            delegate?.dispatchKeyEvent(event) ?: false

        override fun dispatchKeyShortcutEvent(event: KeyEvent): Boolean =
            delegate?.dispatchKeyShortcutEvent(event) ?: false

        override fun dispatchTouchEvent(event: MotionEvent): Boolean {
            try {
                onTouchReceived(event)
            } catch (e: Exception) {
                android.util.Log.w(
                    "SynheartBehaviorPlugin",
                    "TouchForwardingCallback observer threw: ${e.message}",
                    e
                )
            }
            return delegate?.dispatchTouchEvent(event) ?: false
        }

        override fun dispatchTrackballEvent(event: MotionEvent): Boolean =
            delegate?.dispatchTrackballEvent(event) ?: false

        override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean =
            delegate?.dispatchGenericMotionEvent(event) ?: false

        override fun dispatchPopulateAccessibilityEvent(
            event: AccessibilityEvent
        ): Boolean =
            delegate?.dispatchPopulateAccessibilityEvent(event) ?: false

        override fun onCreatePanelView(featureId: Int): View? =
            delegate?.onCreatePanelView(featureId)

        override fun onCreatePanelMenu(featureId: Int, menu: Menu): Boolean =
            delegate?.onCreatePanelMenu(featureId, menu) ?: false

        override fun onPreparePanel(featureId: Int, view: View?, menu: Menu): Boolean =
            delegate?.onPreparePanel(featureId, view, menu) ?: false

        override fun onMenuOpened(featureId: Int, menu: Menu): Boolean =
            delegate?.onMenuOpened(featureId, menu) ?: false

        override fun onMenuItemSelected(featureId: Int, item: MenuItem): Boolean =
            delegate?.onMenuItemSelected(featureId, item) ?: false

        override fun onWindowAttributesChanged(attrs: WindowManager.LayoutParams) {
            delegate?.onWindowAttributesChanged(attrs)
        }

        override fun onContentChanged() {
            delegate?.onContentChanged()
        }

        override fun onWindowFocusChanged(hasFocus: Boolean) {
            delegate?.onWindowFocusChanged(hasFocus)
        }

        override fun onAttachedToWindow() {
            delegate?.onAttachedToWindow()
        }

        override fun onDetachedFromWindow() {
            delegate?.onDetachedFromWindow()
        }

        override fun onPanelClosed(featureId: Int, menu: Menu) {
            delegate?.onPanelClosed(featureId, menu)
        }

        override fun onSearchRequested(): Boolean =
            delegate?.onSearchRequested() ?: false

        override fun onSearchRequested(searchEvent: SearchEvent): Boolean =
            delegate?.onSearchRequested(searchEvent) ?: false

        override fun onWindowStartingActionMode(callback: ActionMode.Callback): ActionMode? =
            delegate?.onWindowStartingActionMode(callback)

        override fun onWindowStartingActionMode(
            callback: ActionMode.Callback,
            type: Int
        ): ActionMode? =
            delegate?.onWindowStartingActionMode(callback, type)

        override fun onActionModeStarted(mode: ActionMode) {
            delegate?.onActionModeStarted(mode)
        }

        override fun onActionModeFinished(mode: ActionMode) {
            delegate?.onActionModeFinished(mode)
        }
    }
}
