package ai.synheart.behavior

import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import java.util.LinkedList

/**
 * Collects input signals like keystroke timing.
 * Privacy: NO text content is collected, only timing metrics.
 */
class InputSignalCollector(private var config: BehaviorConfig) {

    private var eventHandler: ((BehaviorEvent) -> Unit)? = null
    private val keystrokeTimestamps = LinkedList<Long>()
    private var lastKeystrokeTime: Long = 0
    private var currentBurstLength = 0
    private val maxBurstGap = 2000L // 2 seconds between keystrokes to be in same burst

    private val textWatcher = object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}

        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
            if (count > 0) { // Character added
                onKeystroke()
            }
        }

        override fun afterTextChanged(s: Editable?) {}
    }

    fun setEventHandler(handler: (BehaviorEvent) -> Unit) {
        this.eventHandler = handler
    }

    fun attachToView(view: View) {
        if (!config.enableInputSignals) return

        when (view) {
            is EditText -> {
                view.addTextChangedListener(textWatcher)
            }
            is ViewGroup -> {
                // Recursively attach to all EditText children
                for (i in 0 until view.childCount) {
                    attachToView(view.getChildAt(i))
                }
            }
        }
    }

    fun updateConfig(newConfig: BehaviorConfig) {
        config = newConfig
    }

    private fun onKeystroke() {
        val now = System.currentTimeMillis()
        keystrokeTimestamps.add(now)

        // Keep only last 100 keystrokes
        while (keystrokeTimestamps.size > 100) {
            keystrokeTimestamps.removeFirst()
        }

        // Check if part of current burst
        if (lastKeystrokeTime > 0 && (now - lastKeystrokeTime) < maxBurstGap) {
            currentBurstLength++
        } else {
            // New burst
            if (currentBurstLength > 0) {
                emitTypingBurst(currentBurstLength)
            }
            currentBurstLength = 1
        }

        // Calculate inter-key latency
        if (lastKeystrokeTime > 0) {
            val latency = now - lastKeystrokeTime
            emitTypingCadence(latency)
        }

        lastKeystrokeTime = now
    }

    private fun emitTypingCadence(interKeyLatency: Long) {
        // Calculate rolling cadence (keys per second)
        val recentKeys = keystrokeTimestamps.filter { it > System.currentTimeMillis() - 5000 }
        val cadence = if (recentKeys.size > 1) {
            val timeSpan = recentKeys.last() - recentKeys.first()
            if (timeSpan > 0) (recentKeys.size - 1) * 1000.0 / timeSpan else 0.0
        } else {
            0.0
        }

        eventHandler?.invoke(
            BehaviorEvent(
                sessionId = "current", // Will be set by SDK
                timestamp = System.currentTimeMillis(),
                type = "typingCadence",
                payload = mapOf(
                    "cadence" to cadence,
                    "inter_key_latency" to interKeyLatency,
                    "keys_in_window" to recentKeys.size
                )
            )
        )
    }

    private fun emitTypingBurst(burstLength: Int) {
        if (burstLength < 3) return // Only emit significant bursts

        val recentLatencies = mutableListOf<Long>()
        for (i in 1 until keystrokeTimestamps.size.coerceAtMost(burstLength)) {
            recentLatencies.add(keystrokeTimestamps[i] - keystrokeTimestamps[i - 1])
        }

        val avgLatency = if (recentLatencies.isNotEmpty()) {
            recentLatencies.average()
        } else 0.0

        val variance = if (recentLatencies.size > 1) {
            val mean = recentLatencies.average()
            recentLatencies.map { (it - mean) * (it - mean) }.average()
        } else 0.0

        eventHandler?.invoke(
            BehaviorEvent(
                sessionId = "current",
                timestamp = System.currentTimeMillis(),
                type = "typingBurst",
                payload = mapOf(
                    "burst_length" to burstLength,
                    "inter_key_latency" to avgLatency,
                    "variance" to variance
                )
            )
        )
    }

    fun dispose() {
        keystrokeTimestamps.clear()
    }
}
