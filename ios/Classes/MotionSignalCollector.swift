import Foundation
import CoreMotion

/// Collects raw 50 Hz accelerometer samples and forwards them to the runtime
/// in 1-second batches for `MotionStateHead` for the on-device motion classifier to
/// classify. The legacy on-device feature-extraction ML path has been removed.
///
/// Privacy: only raw motion timing/values, no location or content.
class MotionSignalCollector {

    private var config: BehaviorConfig
    private var motionManager: CMMotionManager?

    private var isCollecting = false
    private var sessionStartTime: Double = 0

    // Raw accel buffer (thread-safe via concurrent DispatchQueue + barrier writes).
    private let sampleQueue = DispatchQueue(label: "ai.synheart.motion.samples", attributes: .concurrent)
    private var accelerometerSamples: [(timestamp: Double, x: Double, y: Double, z: Double)] = []

    // Raw-sample batch emission (future work).
    // Forwards a 1-second slice of the accel buffer to the runtime so
    // The Synheart Runtime can derive features and run motion classification.
    private var rawSampleBatchHandler: (([[String: Any]]) -> Void)?
    private var rawBatchTimer: Timer?
    private var lastRawBatchEndMs: Double = 0
    private let rawBatchIntervalMs: Double = 1000.0

    init(config: BehaviorConfig) {
        self.config = config
    }
    
    func updateConfig(_ newConfig: BehaviorConfig) {
        config = newConfig
        let shouldCollect = config.enableMotionLite || config.emitRawMotionSamples
        if !shouldCollect && isCollecting {
            stopCollecting()
        } else if shouldCollect && !isCollecting && sessionStartTime > 0 {
            startCollecting()
        }
        updateRawBatchTimer()
    }

    /// Register a handler for periodic 1-second batches of raw 50 Hz accel
    /// samples. Each batch entry is
    /// `["ts_ms": Int64, "ax": Double, "ay": Double, "az": Double]`.
    /// Only fires when `config.emitRawMotionSamples` is `true`.
    func setRawSampleBatchHandler(_ handler: @escaping ([[String: Any]]) -> Void) {
        rawSampleBatchHandler = handler
        updateRawBatchTimer()
    }
    
    func startSession(sessionStartTime: Double) {
        self.sessionStartTime = sessionStartTime
        self.lastRawBatchEndMs = sessionStartTime

        // Clear previous data
        sampleQueue.async(flags: .barrier) {
            self.accelerometerSamples.removeAll()
        }

        if config.enableMotionLite || config.emitRawMotionSamples {
            startCollecting()
        }
        updateRawBatchTimer()
    }

    func stopSession() {
        stopCollecting()
        flushRawBatch()
        stopRawBatchTimer()
    }
    
    private func startCollecting() {
        if isCollecting { return }
        guard config.enableMotionLite || config.emitRawMotionSamples else { return }

        motionManager = CMMotionManager()
        guard let motionManager = motionManager else {
            print("MotionSignalCollector: CMMotionManager not available")
            return
        }

        if !motionManager.isAccelerometerAvailable {
            print("MotionSignalCollector: Accelerometer not available on this device")
            return
        }

        // 50 Hz — matches the Synheart Runtime's default.
        motionManager.accelerometerUpdateInterval = 0.02

        // CMAccelerometerData.acceleration is in **G-units** (1.0 = 9.81 m/s²).
        // The runtime expects m/s² (matches Android's Sensor.TYPE_ACCELEROMETER
        // and what the Synheart Runtime's GRAVITY_MAG_MIN/MAX bounds (6.0–14.0)
        // sanity-check against). Convert here so downstream code stays
        // unit-consistent across platforms.
        let gToMs2: Double = 9.80665
        motionManager.startAccelerometerUpdates(to: OperationQueue()) { [weak self] (data, error) in
            guard let self = self, let data = data, error == nil else { return }

            let timestamp = Date().timeIntervalSince1970 * 1000 // milliseconds
            self.sampleQueue.async(flags: .barrier) {
                self.accelerometerSamples.append((
                    timestamp: timestamp,
                    x: data.acceleration.x * gToMs2,
                    y: data.acceleration.y * gToMs2,
                    z: data.acceleration.z * gToMs2
                ))
            }
        }

        isCollecting = true
        print("MotionSignalCollector: Started collecting motion data")
    }

    private func stopCollecting() {
        if !isCollecting { return }

        motionManager?.stopAccelerometerUpdates()
        motionManager = nil

        isCollecting = false
        print("MotionSignalCollector: Stopped collecting motion data")
    }

    func dispose() {
        stopCollecting()
        stopRawBatchTimer()
        sampleQueue.async(flags: .barrier) {
            self.accelerometerSamples.removeAll()
        }
    }

    // MARK: - Raw-sample batch emission (future work)

    private func updateRawBatchTimer() {
        let shouldEmit = config.emitRawMotionSamples
            && rawSampleBatchHandler != nil
            && sessionStartTime > 0
        if shouldEmit && rawBatchTimer == nil {
            startRawBatchTimer()
        } else if !shouldEmit {
            stopRawBatchTimer()
        }
    }

    private func startRawBatchTimer() {
        let interval = rawBatchIntervalMs / 1000.0
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.rawBatchTimer?.invalidate()
            self.rawBatchTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.flushRawBatch()
            }
        }
    }

    private func stopRawBatchTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.rawBatchTimer?.invalidate()
            self?.rawBatchTimer = nil
        }
    }

    /// Pull samples accumulated since the last flush and forward to the
    /// runtime via the registered handler. Trims the per-axis buffer to the
    /// last 10 seconds so memory stays bounded if no consumer is attached.
    private func flushRawBatch() {
        guard let handler = rawSampleBatchHandler, config.emitRawMotionSamples else { return }
        let nowMs = Date().timeIntervalSince1970 * 1000

        let batch: [[String: Any]] = sampleQueue.sync(flags: .barrier) {
            let cutoffStart = self.lastRawBatchEndMs
            let recent = self.accelerometerSamples.filter { $0.timestamp > cutoffStart && $0.timestamp <= nowMs }
            // Buffer trim — keep ≤ 10 s of history regardless of consumer state.
            let trimCutoff = nowMs - 10_000
            self.accelerometerSamples.removeAll { $0.timestamp < trimCutoff }
            self.lastRawBatchEndMs = nowMs
            return recent.map { sample in
                [
                    "ts_ms": Int64(sample.timestamp),
                    "ax": sample.x,
                    "ay": sample.y,
                    "az": sample.z,
                ] as [String: Any]
            }
        }
        if batch.isEmpty { return }
        handler(batch)
    }
}

