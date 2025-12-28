import Foundation
import CoreMotion

/// Collects raw motion sensor data (accelerometer and gyroscope).
/// Privacy: Only raw motion patterns, no location or context.
///
/// Collects raw samples and aggregates them into time windows (5 seconds).
/// Calculates 561 ML features per window for model input.
class MotionSignalCollector {
    
    private var config: BehaviorConfig
    private var motionManager: CMMotionManager?
    
    private var isCollecting = false
    private var sessionStartTime: Double = 0
    
    // Raw sample buffers (thread-safe using DispatchQueue)
    private let sampleQueue = DispatchQueue(label: "com.synheart.motion.samples", attributes: .concurrent)
    private var accelerometerSamples: [(timestamp: Double, x: Double, y: Double, z: Double)] = []
    private var gyroscopeSamples: [(timestamp: Double, x: Double, y: Double, z: Double)] = []
    
    // Aggregated motion data (per time window)
    private var motionDataPoints: [MotionDataPoint] = []
    
    // Time window configuration (5 seconds = 5000ms)
    private let timeWindowMs: Double = 5000.0
    private var lastWindowEndTime: Double = 0
    
    // ISO 8601 formatter for timestamps
    private let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    struct MotionDataPoint {
        let timestamp: String // ISO 8601 format (5-second window)
        let features: [String: Double] // 561 ML features
    }
    
    // Feature extractor for calculating ML features
    private let featureExtractor = MotionFeatureExtractor()
    
    init(config: BehaviorConfig) {
        self.config = config
    }
    
    func updateConfig(_ newConfig: BehaviorConfig) {
        config = newConfig
        if !config.enableMotionLite && isCollecting {
            stopCollecting()
        } else if config.enableMotionLite && !isCollecting && sessionStartTime > 0 {
            startCollecting()
        }
    }
    
    func startSession(sessionStartTime: Double) {
        self.sessionStartTime = sessionStartTime
        self.lastWindowEndTime = sessionStartTime
        
        // Clear previous data
        sampleQueue.async(flags: .barrier) {
            self.accelerometerSamples.removeAll()
            self.gyroscopeSamples.removeAll()
            self.motionDataPoints.removeAll()
        }
        
        if config.enableMotionLite {
            startCollecting()
        }
    }
    
    func stopSession() -> [MotionDataPoint] {
        stopCollecting()
        
        // Flush any remaining samples in the current window
        flushCurrentWindow()
        
        // Return collected motion data
        return sampleQueue.sync {
            return motionDataPoints
        }
    }
    
    private func startCollecting() {
        if isCollecting || !config.enableMotionLite { return }
        
        motionManager = CMMotionManager()
        guard let motionManager = motionManager else {
            print("MotionSignalCollector: CMMotionManager not available")
            return
        }
        
        // Check if sensors are available
        if !motionManager.isAccelerometerAvailable || !motionManager.isGyroAvailable {
            print("MotionSignalCollector: Motion sensors not available on this device")
            return
        }
        
        // Set update interval (default: 0.02 seconds = 50Hz)
        motionManager.accelerometerUpdateInterval = 0.02 // 50Hz
        motionManager.gyroUpdateInterval = 0.02 // 50Hz
        
        // Start accelerometer updates
        motionManager.startAccelerometerUpdates(to: OperationQueue()) { [weak self] (data, error) in
            guard let self = self, let data = data, error == nil else { return }
            
            let timestamp = Date().timeIntervalSince1970 * 1000 // milliseconds
            self.sampleQueue.async(flags: .barrier) {
                self.accelerometerSamples.append((
                    timestamp: timestamp,
                    x: data.acceleration.x,
                    y: data.acceleration.y,
                    z: data.acceleration.z
                ))
            }
            
            // Check if we need to flush the current window
            // Use time boundaries, not event timestamps, to ensure consistent window creation
            while timestamp >= self.lastWindowEndTime + self.timeWindowMs {
                self.flushCurrentWindow()
                self.lastWindowEndTime = self.lastWindowEndTime + self.timeWindowMs // Use window boundary, not event timestamp
            }
        }
        
        // Start gyroscope updates
        motionManager.startGyroUpdates(to: OperationQueue()) { [weak self] (data, error) in
            guard let self = self, let data = data, error == nil else { return }
            
            let timestamp = Date().timeIntervalSince1970 * 1000 // milliseconds
            self.sampleQueue.async(flags: .barrier) {
                self.gyroscopeSamples.append((
                    timestamp: timestamp,
                    x: data.rotationRate.x,
                    y: data.rotationRate.y,
                    z: data.rotationRate.z
                ))
            }
        }
        
        isCollecting = true
        print("MotionSignalCollector: Started collecting motion data")
    }
    
    private func stopCollecting() {
        if !isCollecting { return }
        
        motionManager?.stopAccelerometerUpdates()
        motionManager?.stopGyroUpdates()
        motionManager = nil
        
        isCollecting = false
        print("MotionSignalCollector: Stopped collecting motion data")
    }
    
    private func flushCurrentWindow() {
        let windowStartTime = lastWindowEndTime
        let windowEndTime = Date().timeIntervalSince1970 * 1000
        
        sampleQueue.async(flags: .barrier) {
            // Collect all samples within this window
            let accelSamples = self.accelerometerSamples.filter { sample in
                sample.timestamp >= windowStartTime && sample.timestamp < windowEndTime
            }
            
            let gyroSamples = self.gyroscopeSamples.filter { sample in
                sample.timestamp >= windowStartTime && sample.timestamp < windowEndTime
            }
            
            // Remove processed samples
            self.accelerometerSamples.removeAll { $0.timestamp < windowEndTime }
            self.gyroscopeSamples.removeAll { $0.timestamp < windowEndTime }
            
            // Only create data point if we have samples
            if !accelSamples.isEmpty || !gyroSamples.isEmpty {
                // Sort by timestamp to ensure consistent ordering
                let sortedAccel = accelSamples.sorted { $0.timestamp < $1.timestamp }
                let sortedGyro = gyroSamples.sorted { $0.timestamp < $1.timestamp }
                
                // Extract raw values
                let accelX = sortedAccel.map { $0.x }
                let accelY = sortedAccel.map { $0.y }
                let accelZ = sortedAccel.map { $0.z }
                
                let gyroX = sortedGyro.map { $0.x }
                let gyroY = sortedGyro.map { $0.y }
                let gyroZ = sortedGyro.map { $0.z }
                
                // Extract 561 ML features from raw sensor data
                let features = self.featureExtractor.extractFeatures(
                    accelX: accelX, accelY: accelY, accelZ: accelZ,
                    gyroX: gyroX, gyroY: gyroY, gyroZ: gyroZ
                )
                
                // Create timestamp for this window (use window start time)
                let timestampDate = Date(timeIntervalSince1970: windowStartTime / 1000)
                let timestampString = self.timestampFormatter.string(from: timestampDate)
                
                // Create motion data point with ML features
                let dataPoint = MotionDataPoint(
                    timestamp: timestampString,
                    features: features
                )
                
                self.motionDataPoints.append(dataPoint)
            }
        }
    }
    
    func dispose() {
        stopCollecting()
        sampleQueue.async(flags: .barrier) {
            self.accelerometerSamples.removeAll()
            self.gyroscopeSamples.removeAll()
            self.motionDataPoints.removeAll()
        }
    }
}

