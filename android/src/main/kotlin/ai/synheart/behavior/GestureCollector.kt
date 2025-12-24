package ai.synheart.behavior

import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.ViewTreeObserver
import android.widget.ScrollView
import androidx.core.widget.NestedScrollView
import androidx.recyclerview.widget.RecyclerView
import java.time.Instant
import java.util.LinkedList
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * Collects gesture and scroll signals. Privacy: Only timing and velocity metrics, no content or
 * coordinates.
 */
class GestureCollector(private var config: BehaviorConfig) {

    private var eventHandler: ((BehaviorEvent) -> Unit)? = null

    // Scroll tracking - using native scroll velocity
    private var lastScrollY = 0
    private var lastScrollTime = 0L
    private var previousVelocity = 0.0
    private var lastScrollDirection: String? = null // "up", "down", "left", "right"
    private var hasDirectionReversal = false

    // Tap tracking
    private val tapTimestamps = LinkedList<Long>()
    private var tapStartTime = 0L
    private val longPressThresholdMs = 500L

    // Swipe tracking - using VelocityTracker for native velocity
    private var velocityTracker: VelocityTracker? = null
    private var swipeStartTime = 0L
    private var swipeStartX = 0f
    private var swipeStartY = 0f
    private var swipeLastX = 0f
    private var swipeLastY = 0f
    private var isSwipe = false
    private val swipeThresholdPx = 50.0f
    private val tapMovementTolerancePx = 10.0f // Allow small movement for taps
    private var previousSwipeVelocity = 0.0
    private var lastSwipeVelocityTime = 0L

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
                tapStartTime = System.currentTimeMillis()
                swipeStartTime = System.currentTimeMillis()
                swipeStartX = event.x
                swipeStartY = event.y
                swipeLastX = event.x
                swipeLastY = event.y
                isSwipe = false
                previousSwipeVelocity = 0.0
                lastSwipeVelocityTime = swipeStartTime

                // Initialize VelocityTracker for native velocity tracking
                velocityTracker?.recycle()
                velocityTracker = VelocityTracker.obtain()
                velocityTracker?.addMovement(event)
            }
            MotionEvent.ACTION_MOVE -> {
                velocityTracker?.addMovement(event)
                swipeLastX = event.x
                swipeLastY = event.y
                val deltaX = swipeLastX - swipeStartX
                val deltaY = swipeLastY - swipeStartY
                val distance = sqrt(deltaX * deltaX + deltaY * deltaY)

                // If movement is significant, treat as swipe
                if (distance > swipeThresholdPx) {
                    isSwipe = true

                    // Track velocity changes during the gesture for acceleration calculation
                    val now = System.currentTimeMillis()
                    velocityTracker?.computeCurrentVelocity(1000)
                    val currentVelocityX = velocityTracker?.xVelocity ?: 0f
                    val currentVelocityY = velocityTracker?.yVelocity ?: 0f
                    val currentVelocity =
                            sqrt(
                                            currentVelocityX * currentVelocityX +
                                                    currentVelocityY * currentVelocityY
                                    )
                                    .toDouble()

                    if (lastSwipeVelocityTime > 0 && now > lastSwipeVelocityTime) {
                        val timeDelta = (now - lastSwipeVelocityTime) / 1000.0
                        if (timeDelta > 0) {
                            previousSwipeVelocity = currentVelocity
                        }
                    }
                    lastSwipeVelocityTime = now
                }
            }
            MotionEvent.ACTION_UP -> {
                val duration = System.currentTimeMillis() - tapStartTime
                val swipeDuration = System.currentTimeMillis() - swipeStartTime

                // Check if it's a swipe
                val deltaX = swipeLastX - swipeStartX
                val deltaY = swipeLastY - swipeStartY
                val distance = sqrt(deltaX * deltaX + deltaY * deltaY)

                // Determine if it's a swipe or tap
                // A swipe requires: significant movement (> threshold) AND sufficient duration (>=
                // 100ms)
                // A tap is: small movement OR very quick gesture (< 100ms) - quick taps are always
                // taps
                val isSwipeGesture = distance > swipeThresholdPx && swipeDuration >= 100

                if (isSwipeGesture && swipeDuration > 0) {
                    // It's a swipe - use native velocity from VelocityTracker
                    velocityTracker?.computeCurrentVelocity(1000) // pixels per second
                    val velocityX = velocityTracker?.xVelocity ?: 0f
                    val velocityY = velocityTracker?.yVelocity ?: 0f
                    val velocity = sqrt(velocityX * velocityX + velocityY * velocityY).toDouble()

                    // Calculate acceleration as change in velocity over time
                    // For a swipe starting from rest: a = (v_final - v_initial) / t
                    // Since initial velocity is 0, and assuming roughly constant acceleration:
                    // a ≈ v / t (but this can be large, so we'll use a more reasonable calculation)
                    val acceleration =
                            if (swipeDuration > 50 && previousSwipeVelocity > 0) {
                                // Use velocity change if we tracked it
                                (velocity - previousSwipeVelocity) / (swipeDuration / 1000.0)
                            } else if (swipeDuration > 50) {
                                // Fallback: average acceleration assuming constant acceleration
                                // from rest
                                // a = 2 * distance / t² (from d = 0.5 * a * t²)
                                (2.0 * distance) /
                                        ((swipeDuration / 1000.0) * (swipeDuration / 1000.0))
                            } else {
                                0.0
                            }

                    // Determine swipe direction
                    val direction =
                            when {
                                abs(deltaX) > abs(deltaY) -> if (deltaX > 0) "right" else "left"
                                else -> if (deltaY > 0) "down" else "up"
                            }

                    emitSwipeEvent(
                            direction = direction,
                            distancePx = distance.toDouble(),
                            durationMs = swipeDuration.toInt(),
                            velocity = velocity,
                            acceleration = acceleration
                    )
                } else {
                    // It's a tap - always emit for taps (including quick taps)
                    // Taps are: small movement OR quick gesture
                    val longPress = duration >= longPressThresholdMs
                    // Ensure minimum duration for very quick taps (at least 10ms)
                    val tapDuration = if (duration < 10) 10 else duration.toInt()
                    emitTapEvent(tapDurationMs = tapDuration, longPress = longPress)
                }

                // Clean up velocity tracker
                velocityTracker?.recycle()
                velocityTracker = null
            }
            MotionEvent.ACTION_CANCEL -> {
                velocityTracker?.recycle()
                velocityTracker = null
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

        // Calculate velocity from scroll delta (pixels per second)
        val deltaY = dy - lastScrollY
        val velocity = abs(deltaY) / timeDelta.toDouble() * 1000.0

        // Calculate acceleration (change in velocity over time)
        val acceleration =
                if (previousVelocity > 0 && timeDelta > 0) {
                    (velocity - previousVelocity) / (timeDelta / 1000.0)
                } else 0.0

        // Determine scroll direction
        val direction =
                when {
                    deltaY > 0 -> "down"
                    deltaY < 0 -> "up"
                    else -> lastScrollDirection ?: "down"
                }

        // Check for direction reversal
        if (lastScrollDirection != null && lastScrollDirection != direction) {
            hasDirectionReversal = true
        }

        // Emit scroll events
        if (velocity > 10.0) { // Only emit if significant movement
            emitScrollEvent(
                    velocity = velocity,
                    acceleration = acceleration,
                    direction = direction,
                    directionReversal = hasDirectionReversal
            )

            hasDirectionReversal = false
        }

        previousVelocity = velocity
        lastScrollTime = now
        lastScrollY = dy
        lastScrollDirection = direction
    }

    private fun getIsoTimestamp(): String {
        // Use DateTimeFormatter to ensure fractional seconds are included
        val instant = Instant.now()
        // Instant.toString() includes fractional seconds by default, but ensure it's explicit
        return instant.toString()
    }

    private fun emitScrollEvent(
            velocity: Double,
            acceleration: Double,
            direction: String,
            directionReversal: Boolean
    ) {
        if (eventHandler != null) {
            eventHandler?.invoke(
                    BehaviorEvent(
                            sessionId = "current",
                            timestamp = getIsoTimestamp(),
                            eventType = "scroll",
                            metrics =
                                    mapOf(
                                            "velocity" to velocity,
                                            "acceleration" to acceleration,
                                            "direction" to direction,
                                            "direction_reversal" to directionReversal
                                    )
                    )
            )
        }
    }

    private fun emitTapEvent(tapDurationMs: Int, longPress: Boolean) {
        tapTimestamps.add(System.currentTimeMillis())
        while (tapTimestamps.size > 50) {
            tapTimestamps.removeFirst()
        }

        if (eventHandler != null) {
            eventHandler?.invoke(
                    BehaviorEvent(
                            sessionId = "current",
                            timestamp = getIsoTimestamp(),
                            eventType = "tap",
                            metrics =
                                    mapOf(
                                            "tap_duration_ms" to tapDurationMs,
                                            "long_press" to longPress
                                    )
                    )
            )
        }
    }

    private fun emitSwipeEvent(
            direction: String,
            distancePx: Double,
            durationMs: Int,
            velocity: Double,
            acceleration: Double
    ) {
        eventHandler?.invoke(
                BehaviorEvent(
                        sessionId = "current",
                        timestamp = getIsoTimestamp(),
                        eventType = "swipe",
                        metrics =
                                mapOf(
                                        "direction" to direction,
                                        "distance_px" to distancePx,
                                        "duration_ms" to durationMs,
                                        "velocity" to velocity,
                                        "acceleration" to acceleration
                                )
                )
        )
    }

    fun dispose() {
        tapTimestamps.clear()
        velocityTracker?.recycle()
        velocityTracker = null
    }
}
