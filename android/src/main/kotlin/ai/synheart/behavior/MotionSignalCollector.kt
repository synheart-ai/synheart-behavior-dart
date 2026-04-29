package ai.synheart.behavior

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Collects raw motion sensor data (accelerometer and gyroscope). Privacy: Only raw motion patterns,
 * no location or context.
 *
 * Collects raw samples and aggregates them into time windows (5 seconds). Calculates 561 ML
 * features per window for model input.
 */
class MotionSignalCollector(private val context: Context, private var config: BehaviorConfig) :
        SensorEventListener {

    private var sensorManager: SensorManager? = null
    private var accelerometerSensor: Sensor? = null
    private var gyroscopeSensor: Sensor? = null

    private var isCollecting = false
    private var sessionStartTime: Long = 0

    // Raw sample buffers (thread-safe)
    // Store as: timestamp to (x, y, z) values
    private val accelerometerSamples =
            ConcurrentLinkedQueue<Pair<Long, FloatArray>>() // timestamp, [x, y, z]
    private val gyroscopeSamples =
            ConcurrentLinkedQueue<Pair<Long, FloatArray>>() // timestamp, [x, y, z]

    // Aggregated motion data (per time window) - now stores ML features instead of raw arrays
    private val motionDataPoints = mutableListOf<MotionDataPoint>()

    // Time window configuration (5 seconds = 5000ms)
    private val timeWindowMs: Long = 5000L
    private var lastWindowEndTime: Long = 0

    // Raw-sample batch emission (RFC-MOTION-STATE-0001 Phase 3).
    private var rawSampleBatchHandler: ((List<Map<String, Any>>) -> Unit)? = null
    private var lastRawBatchEndMs: Long = 0
    private val rawBatchIntervalMs: Long = 1000L
    private val rawBatchHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val rawBatchRunnable = object : Runnable {
        override fun run() {
            flushRawBatch()
            rawBatchHandler.postDelayed(this, rawBatchIntervalMs)
        }
    }
    private var rawBatchTimerActive = false

    // ISO 8601 formatter for timestamps
    private val timestampFormatter = DateTimeFormatter.ISO_INSTANT

    // Feature extractor for calculating ML features
    private val featureExtractor = MotionFeatureExtractor()

    data class MotionDataPoint(
            val timestamp: String, // ISO 8601 format
            val features: Map<String, Double> // 561 ML features
    )

    fun updateConfig(newConfig: BehaviorConfig) {
        config = newConfig
        val shouldCollect = config.enableMotionLite || config.emitRawMotionSamples
        if (!shouldCollect && isCollecting) {
            stopCollecting()
        } else if (shouldCollect && !isCollecting && sessionStartTime > 0) {
            startCollecting()
        }
        updateRawBatchTimer()
    }

    fun setRawSampleBatchHandler(handler: (List<Map<String, Any>>) -> Unit) {
        rawSampleBatchHandler = handler
        updateRawBatchTimer()
    }

    fun startSession(sessionStartTime: Long) {
        this.sessionStartTime = sessionStartTime
        this.lastWindowEndTime = sessionStartTime
        this.lastRawBatchEndMs = sessionStartTime

        // Clear previous data
        accelerometerSamples.clear()
        gyroscopeSamples.clear()
        motionDataPoints.clear()

        if (config.enableMotionLite || config.emitRawMotionSamples) {
            startCollecting()
        }
        updateRawBatchTimer()
    }

    fun stopSession(): List<MotionDataPoint> {
        stopCollecting()

        // Flush any remaining samples in the current window
        flushCurrentWindow()
        flushRawBatch()
        stopRawBatchTimer()

        // Return collected motion data
        return motionDataPoints.toList()
    }

    fun getCurrentMotionData(): List<MotionDataPoint> {
        // Flush current window to ensure we have the latest data
        flushCurrentWindow()
        // Return current motion data without stopping collection
        return motionDataPoints.toList()
    }

    private fun startCollecting() {
        if (isCollecting) return
        if (!config.enableMotionLite && !config.emitRawMotionSamples) return

        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        if (sensorManager == null) {
            android.util.Log.w("MotionSignalCollector", "SensorManager not available")
            return
        }

        accelerometerSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        gyroscopeSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

        if (accelerometerSensor == null || gyroscopeSensor == null) {
            android.util.Log.w(
                    "MotionSignalCollector",
                    "Motion sensors not available on this device"
            )
            return
        }

        // Register listeners with default sampling rate (SENSOR_DELAY_NORMAL = ~50Hz)
        // For higher rates, use SENSOR_DELAY_FASTEST, but it may drain battery faster
        val samplingRate = SensorManager.SENSOR_DELAY_NORMAL // ~50Hz (20ms intervals)

        sensorManager?.registerListener(this, accelerometerSensor, samplingRate)
        sensorManager?.registerListener(this, gyroscopeSensor, samplingRate)

        isCollecting = true
        android.util.Log.d("MotionSignalCollector", "Started collecting motion data")
    }

    private fun stopCollecting() {
        if (!isCollecting) return

        sensorManager?.unregisterListener(this)
        sensorManager = null
        accelerometerSensor = null
        gyroscopeSensor = null

        isCollecting = false
        android.util.Log.d("MotionSignalCollector", "Stopped collecting motion data")
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null || !isCollecting) return

        val timestamp = System.currentTimeMillis()
        val sensorType = event.sensor.type

        when (sensorType) {
            Sensor.TYPE_ACCELEROMETER -> {
                // Store raw accelerometer values (x, y, z in m/s²)
                // Copy the values array to avoid reference issues
                val values = FloatArray(3)
                System.arraycopy(event.values, 0, values, 0, 3)
                accelerometerSamples.offer(Pair(timestamp, values))
            }
            Sensor.TYPE_GYROSCOPE -> {
                // Store raw gyroscope values (x, y, z in rad/s)
                // Copy the values array to avoid reference issues
                val values = FloatArray(3)
                System.arraycopy(event.values, 0, values, 0, 3)
                gyroscopeSamples.offer(Pair(timestamp, values))
            }
        }

        // Check if we need to flush the current window and start a new one
        // Use time boundaries, not event timestamps, to ensure consistent window creation
        while (timestamp >= lastWindowEndTime + timeWindowMs) {
            flushCurrentWindow()
            lastWindowEndTime =
                    lastWindowEndTime + timeWindowMs // Use window boundary, not event timestamp
        }
    }

    private fun flushCurrentWindow() {
        val windowStartTime = lastWindowEndTime
        val windowEndTime = System.currentTimeMillis()

        // Collect all samples within this window
        val accelSamples = mutableListOf<Pair<Long, FloatArray>>()
        val gyroSamples = mutableListOf<Pair<Long, FloatArray>>()

        // Extract accelerometer samples in this window
        val accelIterator = accelerometerSamples.iterator()
        while (accelIterator.hasNext()) {
            val sample = accelIterator.next()
            if (sample.first >= windowStartTime && sample.first < windowEndTime) {
                accelSamples.add(sample)
                accelIterator.remove()
            } else if (sample.first < windowStartTime) {
                // Remove old samples
                accelIterator.remove()
            }
        }

        // Extract gyroscope samples in this window
        val gyroIterator = gyroscopeSamples.iterator()
        while (gyroIterator.hasNext()) {
            val sample = gyroIterator.next()
            if (sample.first >= windowStartTime && sample.first < windowEndTime) {
                gyroSamples.add(sample)
                gyroIterator.remove()
            } else if (sample.first < windowStartTime) {
                // Remove old samples
                gyroIterator.remove()
            }
        }

        // Only create data point if we have samples
        if (accelSamples.isNotEmpty() || gyroSamples.isNotEmpty()) {
            // Convert to lists of doubles (raw values)
            // Sort by timestamp to ensure consistent ordering
            val sortedAccel = accelSamples.sortedBy { it.first }
            val sortedGyro = gyroSamples.sortedBy { it.first }

            val accelX = sortedAccel.map { it.second[0].toDouble() }
            val accelY = sortedAccel.map { it.second[1].toDouble() }
            val accelZ = sortedAccel.map { it.second[2].toDouble() }

            val gyroX = sortedGyro.map { it.second[0].toDouble() }
            val gyroY = sortedGyro.map { it.second[1].toDouble() }
            val gyroZ = sortedGyro.map { it.second[2].toDouble() }

            // Extract 561 ML features from raw sensor data
            val features =
                    featureExtractor.extractFeatures(accelX, accelY, accelZ, gyroX, gyroY, gyroZ)

            // Create timestamp for this window (use window start time)
            val timestamp = Instant.ofEpochMilli(windowStartTime)
            val timestampString = timestampFormatter.format(timestamp)

            // Create motion data point with ML features
            val dataPoint = MotionDataPoint(timestamp = timestampString, features = features)

            motionDataPoints.add(dataPoint)
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Sensor accuracy changed - we can log this but don't need to do anything
    }

    fun dispose() {
        stopCollecting()
        stopRawBatchTimer()
        accelerometerSamples.clear()
        gyroscopeSamples.clear()
        motionDataPoints.clear()
    }

    // MARK: - Raw-sample batch emission (RFC-MOTION-STATE-0001 Phase 3)

    private fun updateRawBatchTimer() {
        val shouldEmit = config.emitRawMotionSamples &&
                rawSampleBatchHandler != null &&
                sessionStartTime > 0
        if (shouldEmit && !rawBatchTimerActive) {
            rawBatchTimerActive = true
            rawBatchHandler.postDelayed(rawBatchRunnable, rawBatchIntervalMs)
        } else if (!shouldEmit) {
            stopRawBatchTimer()
        }
    }

    private fun stopRawBatchTimer() {
        if (rawBatchTimerActive) {
            rawBatchHandler.removeCallbacks(rawBatchRunnable)
            rawBatchTimerActive = false
        }
    }

    /**
     * Pull samples accumulated since the last flush and forward to the
     * runtime via the registered handler. Trims the per-axis buffer to the
     * last 10 seconds so memory stays bounded if no consumer is attached.
     */
    private fun flushRawBatch() {
        val handler = rawSampleBatchHandler ?: return
        if (!config.emitRawMotionSamples) return
        val nowMs = System.currentTimeMillis()
        val cutoffStart = lastRawBatchEndMs
        val trimCutoff = nowMs - 10_000L

        val batch = mutableListOf<Map<String, Any>>()
        // Drain newer-than-cutoff samples; trim older ones.
        val keep = ArrayList<Pair<Long, FloatArray>>(accelerometerSamples.size)
        for (entry in accelerometerSamples) {
            val ts = entry.first
            if (ts <= cutoffStart) {
                if (ts >= trimCutoff) keep.add(entry)
                continue
            }
            if (ts > nowMs) {
                keep.add(entry)
                continue
            }
            val axes = entry.second
            batch.add(
                mapOf(
                    "ts_ms" to ts,
                    "ax" to axes[0].toDouble(),
                    "ay" to axes[1].toDouble(),
                    "az" to axes[2].toDouble(),
                ) as Map<String, Any>
            )
            if (ts >= trimCutoff) keep.add(entry)
        }
        accelerometerSamples.clear()
        accelerometerSamples.addAll(keep)
        lastRawBatchEndMs = nowMs

        if (batch.isEmpty()) return
        handler(batch)
    }
}
