package ai.synheart.behavior

import android.content.Context
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import android.util.Log
import java.time.Instant

/**
 * Collects phone call signals (incoming, answered, ignored). Privacy: Only timing metrics, no phone
 * numbers or contact information.
 */
@Suppress("DEPRECATION") // PhoneStateListener is deprecated but still widely used
class CallCollector(private val context: Context, private var config: BehaviorConfig) {

    private var eventHandler: ((BehaviorEvent) -> Unit)? = null
    private var telephonyManager: TelephonyManager? = null
    private var phoneStateListener: PhoneStateListener? = null
    private var incomingCallStartTime: Long = 0
    private var isCallActive = false
    private val callIgnoredThresholdMs = 30000L // 30 seconds

    fun setEventHandler(handler: (BehaviorEvent) -> Unit) {
        this.eventHandler = handler
    }

    fun updateConfig(newConfig: BehaviorConfig) {
        config = newConfig
    }

    fun startMonitoring() {
        if (!config.enableAttentionSignals) {
            Log.d("CallCollector", "Attention signals disabled, not monitoring calls")
            return
        }

        try {
            telephonyManager =
                    context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
            if (telephonyManager == null) {
                Log.w("CallCollector", "TelephonyManager not available")
                return
            }

            phoneStateListener =
                    object : PhoneStateListener() {
                        override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                            handleCallStateChange(state)
                        }
                    }

            telephonyManager?.listen(phoneStateListener, PhoneStateListener.LISTEN_CALL_STATE)
            Log.d("CallCollector", "Call monitoring started")
        } catch (e: SecurityException) {
            Log.e("CallCollector", "Permission denied for phone state: ${e.message}")
        } catch (e: Exception) {
            Log.e("CallCollector", "Error starting call monitoring: ${e.message}")
        }
    }

    fun stopMonitoring() {
        try {
            phoneStateListener?.let { telephonyManager?.listen(it, PhoneStateListener.LISTEN_NONE) }
            phoneStateListener = null
            telephonyManager = null
            Log.d("CallCollector", "Call monitoring stopped")
        } catch (e: Exception) {
            Log.e("CallCollector", "Error stopping call monitoring: ${e.message}")
        }
    }

    private fun handleCallStateChange(state: Int) {
        Log.d(
                "CallCollector",
                "Call state changed: $state (RINGING=${TelephonyManager.CALL_STATE_RINGING}, OFFHOOK=${TelephonyManager.CALL_STATE_OFFHOOK}, IDLE=${TelephonyManager.CALL_STATE_IDLE})"
        )
        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                // Incoming call detected
                incomingCallStartTime = System.currentTimeMillis()
                isCallActive = false
                Log.d(
                        "CallCollector",
                        "Call state: RINGING - incomingCallStartTime=$incomingCallStartTime"
                )
                onIncomingCall()
            }
            TelephonyManager.CALL_STATE_OFFHOOK -> {
                // Call answered
                Log.d(
                        "CallCollector",
                        "Call state: OFFHOOK - incomingCallStartTime=$incomingCallStartTime, isCallActive=$isCallActive"
                )
                if (incomingCallStartTime > 0) {
                    onCallAnswered()
                } else {
                    Log.d("CallCollector", "OFFHOOK but no incoming call tracked (outgoing call?)")
                }
                isCallActive = true
            }
            TelephonyManager.CALL_STATE_IDLE -> {
                // Call ended or ignored
                Log.d(
                        "CallCollector",
                        "Call state: IDLE - incomingCallStartTime=$incomingCallStartTime, isCallActive=$isCallActive"
                )
                if (incomingCallStartTime > 0 && !isCallActive) {
                    // Call was never answered, so it's ignored
                    val duration = System.currentTimeMillis() - incomingCallStartTime
                    Log.d(
                            "CallCollector",
                            "Call ended without being answered. Duration: ${duration}ms - counting as ignored"
                    )
                    // Count all ignored calls, regardless of duration
                    // (Very short calls < 1 second might be accidental, but we'll track them
                    // anyway)
                    if (duration >= 1000
                    ) { // Only ignore calls that lasted at least 1 second (to filter out
                        // accidental/system calls)
                        onCallIgnored()
                    } else {
                        Log.d(
                                "CallCollector",
                                "Call duration too short (<1s) - likely accidental or system call, not tracking"
                        )
                    }
                }
                incomingCallStartTime = 0
                isCallActive = false
            }
        }
    }

    private fun getIsoTimestamp(): String {
        return Instant.now().toString()
    }

    private fun onIncomingCall() {
        Log.d("CallCollector", "INCOMING CALL DETECTED!")
        // Note: We don't emit an event for incoming calls, only for answered/ignored
        // This matches the requirement that calls should only have "action": "ignored" (or
        // answered)
    }

    private fun onCallAnswered() {
        Log.d("CallCollector", "CALL ANSWERED!")
        val event =
                BehaviorEvent(
                        sessionId = "current",
                        timestamp = getIsoTimestamp(),
                        eventType = "call",
                        metrics = mapOf("action" to "answered")
                )
        Log.d("CallCollector", "Emitting call answered event: $event")
        if (eventHandler == null) {
            Log.e("CallCollector", "ERROR: eventHandler is NULL! Call event will not be processed.")
        } else {
            eventHandler?.invoke(event)
            Log.d("CallCollector", "Call answered event emitted successfully")
        }
        incomingCallStartTime = 0 // Reset to prevent duplicate events
    }

    private fun onCallIgnored() {
        Log.d("CallCollector", "CALL IGNORED!")
        val event =
                BehaviorEvent(
                        sessionId = "current",
                        timestamp = getIsoTimestamp(),
                        eventType = "call",
                        metrics = mapOf("action" to "ignored")
                )
        Log.d("CallCollector", "Emitting call ignored event: $event")
        if (eventHandler == null) {
            Log.e("CallCollector", "ERROR: eventHandler is NULL! Call event will not be processed.")
        } else {
            eventHandler?.invoke(event)
            Log.d("CallCollector", "Call ignored event emitted successfully")
        }
        incomingCallStartTime = 0 // Reset to prevent duplicate events
    }

    fun dispose() {
        stopMonitoring()
    }
}
