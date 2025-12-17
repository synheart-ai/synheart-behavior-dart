package ai.synheart.behavior

import android.view.MotionEvent
import android.view.View
import android.view.ViewTreeObserver
import android.widget.ScrollView
import androidx.core.widget.NestedScrollView
import androidx.recyclerview.widget.RecyclerView
import java.util.LinkedList
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Collects gesture and scroll signals. Privacy: Only timing and velocity metrics, no content or
 * coordinates.
 */
class GestureCollector(private var config: BehaviorConfig) {

    private var eventHandler: ((BehaviorEvent) -> Unit)? = null

    // Scroll tracking
    private val scrollVelocities = LinkedList<Double>()
    private var lastScrollY = 0
    private var lastScrollTime = 0L
    private var previousVelocity = 0.0

    // Tap tracking
    private val tapTimestamps = LinkedList<Long>()
    private var longPressCount = 0
    private var tapCount = 0

    // Drag tracking
    private var dragStartTime = 0L
    private var dragStartX = 0f
    private var dragStartY = 0f

    private val scrollListener = ViewTreeObserver.OnScrollChangedListener { onScroll() }

    private val touchListener =
            View.OnTouchListener { view, event ->
                handleTouchEvent(event)
                false // Don't consume the event
            }

    fun setEventHandler(handler: (BehaviorEvent) -> Unit) {
        this.eventHandler = handler
    }

    fun attachToView(view: View) {
        if (!config.enableInputSignals) {
            android.util.Log.d("GestureCollector", "Input signals disabled, not attaching")
            return
        }

        android.util.Log.d("GestureCollector", "Attaching to view: ${view.javaClass.simpleName}")
        // Attach touch listener for gesture detection
        view.setOnTouchListener(touchListener)
        android.util.Log.d("GestureCollector", "Touch listener attached")

        // Attach scroll listeners based on view type
        when (view) {
            is RecyclerView -> {
                view.addOnScrollListener(
                        object : RecyclerView.OnScrollListener() {
                            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                                onScrollDelta(dy)
                            }
                        }
                )
            }
            is ScrollView, is NestedScrollView -> {
                view.viewTreeObserver.addOnScrollChangedListener(scrollListener)
            }
        }
    }

    fun updateConfig(newConfig: BehaviorConfig) {
        config = newConfig
    }

    private fun handleTouchEvent(event: MotionEvent) {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                dragStartTime = System.currentTimeMillis()
                dragStartX = event.x
                dragStartY = event.y
            }
            MotionEvent.ACTION_UP -> {
                val duration = System.currentTimeMillis() - dragStartTime

                if (duration > 500) {
                    // Long press
                    longPressCount++
                    emitLongPressRate()
                } else if (duration < 200) {
                    // Quick tap
                    tapCount++
                    tapTimestamps.add(System.currentTimeMillis())
                    android.util.Log.d("GestureCollector", "TAP DETECTED! Count: $tapCount")

                    // Keep only last 50 taps
                    while (tapTimestamps.size > 50) {
                        tapTimestamps.removeFirst()
                    }

                    emitTapRate()
                }
            }
            MotionEvent.ACTION_MOVE -> {
                val duration = System.currentTimeMillis() - dragStartTime
                if (duration > 100) { // Dragging
                    val deltaX = event.x - dragStartX
                    val deltaY = event.y - dragStartY
                    val distance = sqrt(deltaX * deltaX + deltaY * deltaY)
                    val velocity = distance / duration * 1000.0 // pixels per second

                    emitDragVelocity(velocity)
                }
            }
        }
    }

    private fun onScroll() {
        onScrollDelta(0) // Delta will be calculated from position
    }

    private fun onScrollDelta(dy: Int) {
        val now = System.currentTimeMillis()

        if (lastScrollTime == 0L) {
            lastScrollTime = now
            lastScrollY = dy
            return
        }

        val timeDelta = now - lastScrollTime
        if (timeDelta == 0L) return

        // Calculate velocity (pixels per second)
        val velocity = abs(dy - lastScrollY) / timeDelta.toDouble() * 1000.0

        scrollVelocities.add(velocity)
        while (scrollVelocities.size > 20) {
            scrollVelocities.removeFirst()
        }

        // Calculate acceleration (change in velocity)
        val acceleration =
                if (previousVelocity > 0) {
                    (velocity - previousVelocity) / timeDelta * 1000.0
                } else 0.0

        // Calculate jitter (variance in velocity)
        val jitter =
                if (scrollVelocities.size > 2) {
                    val mean = scrollVelocities.average()
                    sqrt(scrollVelocities.map { (it - mean) * (it - mean) }.average())
                } else 0.0

        // Emit scroll events
        if (velocity > 10.0) { // Only emit if significant movement
            android.util.Log.d("GestureCollector", "SCROLL DETECTED! Velocity: $velocity px/s")
            emitScrollVelocity(velocity)

            if (abs(acceleration) > 100.0) {
                emitScrollAcceleration(acceleration)
            }

            if (jitter > 50.0) {
                emitScrollJitter(jitter)
            }
        } else if (previousVelocity > 10.0 && velocity < 10.0) {
            // Scroll stopped
            emitScrollStop()
        }

        previousVelocity = velocity
        lastScrollTime = now
        lastScrollY = dy
    }

    private fun emitScrollVelocity(velocity: Double) {
        eventHandler?.invoke(
                BehaviorEvent(
                        sessionId = "current",
                        timestamp = System.currentTimeMillis(),
                        type = "scrollVelocity",
                        payload = mapOf("velocity" to velocity, "unit" to "pixels_per_second")
                )
        )
    }

    private fun emitScrollAcceleration(acceleration: Double) {
        eventHandler?.invoke(
                BehaviorEvent(
                        sessionId = "current",
                        timestamp = System.currentTimeMillis(),
                        type = "scrollAcceleration",
                        payload =
                                mapOf(
                                        "acceleration" to acceleration,
                                        "unit" to "pixels_per_second_squared"
                                )
                )
        )
    }

    private fun emitScrollJitter(jitter: Double) {
        eventHandler?.invoke(
                BehaviorEvent(
                        sessionId = "current",
                        timestamp = System.currentTimeMillis(),
                        type = "scrollJitter",
                        payload = mapOf("jitter" to jitter, "sample_size" to scrollVelocities.size)
                )
        )
    }

    private fun emitScrollStop() {
        eventHandler?.invoke(
                BehaviorEvent(
                        sessionId = "current",
                        timestamp = System.currentTimeMillis(),
                        type = "scrollStop",
                        payload = mapOf("final_velocity" to previousVelocity)
                )
        )
    }

    private fun emitTapRate() {
        // Calculate taps per second over last 10 seconds
        val now = System.currentTimeMillis()
        val recentTaps = tapTimestamps.filter { it > now - 10000 }
        val tapRate = recentTaps.size / 10.0

        android.util.Log.d("GestureCollector", "Emitting tapRate event: rate=$tapRate")
        eventHandler?.invoke(
                BehaviorEvent(
                        sessionId = "current",
                        timestamp = System.currentTimeMillis(),
                        type = "tapRate",
                        payload =
                                mapOf(
                                        "tap_rate" to tapRate,
                                        "taps_in_window" to recentTaps.size,
                                        "window_seconds" to 10
                                )
                )
        )
    }

    private fun emitLongPressRate() {
        eventHandler?.invoke(
                BehaviorEvent(
                        sessionId = "current",
                        timestamp = System.currentTimeMillis(),
                        type = "longPressRate",
                        payload = mapOf("long_press_count" to longPressCount)
                )
        )
    }

    private fun emitDragVelocity(velocity: Double) {
        eventHandler?.invoke(
                BehaviorEvent(
                        sessionId = "current",
                        timestamp = System.currentTimeMillis(),
                        type = "dragVelocity",
                        payload = mapOf("velocity" to velocity, "unit" to "pixels_per_second")
                )
        )
    }

    fun dispose() {
        scrollVelocities.clear()
        tapTimestamps.clear()
    }
}
