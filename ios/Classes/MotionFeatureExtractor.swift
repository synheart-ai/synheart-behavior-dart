import Foundation
import Accelerate

/**
 * Extracts 561 ML features from raw accelerometer and gyroscope data.
 * Based on HAR (Human Activity Recognition) feature set.
 */
class MotionFeatureExtractor {
    
    /**
     * Extract all 561 features from raw sensor data in a 5-second window.
     */
    func extractFeatures(
        accelX: [Double],
        accelY: [Double],
        accelZ: [Double],
        gyroX: [Double],
        gyroY: [Double],
        gyroZ: [Double]
    ) -> [String: Double] {
        var features: [String: Double] = [:]
        
        if accelX.isEmpty || gyroX.isEmpty {
            return features
        }
        
        // Step 1: Separate gravity from body acceleration (low-pass filter)
        let (bodyAcc, gravityAcc) = separateGravity(accelX: accelX, accelY: accelY, accelZ: accelZ)
        
        // Step 2: Calculate jerk (derivative) for acceleration and gyroscope
        let bodyAccJerkX = calculateJerk(bodyAcc.x)
        let bodyAccJerkY = calculateJerk(bodyAcc.y)
        let bodyAccJerkZ = calculateJerk(bodyAcc.z)
        
        let bodyGyroJerkX = calculateJerk(gyroX)
        let bodyGyroJerkY = calculateJerk(gyroY)
        let bodyGyroJerkZ = calculateJerk(gyroZ)
        
        // Step 3: Calculate magnitudes
        let bodyAccMag = calculateMagnitude(bodyAcc.x, bodyAcc.y, bodyAcc.z)
        let gravityAccMag = calculateMagnitude(gravityAcc.x, gravityAcc.y, gravityAcc.z)
        let bodyAccJerkMag = calculateMagnitude(bodyAccJerkX, bodyAccJerkY, bodyAccJerkZ)
        let bodyGyroMag = calculateMagnitude(gyroX, gyroY, gyroZ)
        let bodyGyroJerkMag = calculateMagnitude(bodyGyroJerkX, bodyGyroJerkY, bodyGyroJerkZ)
        
        // Step 4: Extract time domain features for body acceleration (features 1-40)
        extractTimeDomainFeatures(prefix: "tBodyAcc", x: bodyAcc.x, y: bodyAcc.y, z: bodyAcc.z, features: &features)
        
        // Step 5: Extract time domain features for gravity acceleration (features 41-80)
        extractTimeDomainFeatures(prefix: "tGravityAcc", x: gravityAcc.x, y: gravityAcc.y, z: gravityAcc.z, features: &features)
        
        // Step 6: Extract time domain features for body acceleration jerk (features 81-120)
        extractTimeDomainFeatures(prefix: "tBodyAccJerk", x: bodyAccJerkX, y: bodyAccJerkY, z: bodyAccJerkZ, features: &features)
        
        // Step 7: Extract time domain features for body gyroscope (features 121-160)
        extractTimeDomainFeatures(prefix: "tBodyGyro", x: gyroX, y: gyroY, z: gyroZ, features: &features)
        
        // Step 8: Extract time domain features for body gyroscope jerk (features 161-200)
        extractTimeDomainFeatures(prefix: "tBodyGyroJerk", x: bodyGyroJerkX, y: bodyGyroJerkY, z: bodyGyroJerkZ, features: &features)
        
        // Step 9: Extract time domain features for magnitudes (features 201-265)
        extractTimeDomainFeaturesMagnitude(prefix: "tBodyAccMag", mag: bodyAccMag, features: &features)
        extractTimeDomainFeaturesMagnitude(prefix: "tGravityAccMag", mag: gravityAccMag, features: &features)
        extractTimeDomainFeaturesMagnitude(prefix: "tBodyAccJerkMag", mag: bodyAccJerkMag, features: &features)
        extractTimeDomainFeaturesMagnitude(prefix: "tBodyGyroMag", mag: bodyGyroMag, features: &features)
        extractTimeDomainFeaturesMagnitude(prefix: "tBodyGyroJerkMag", mag: bodyGyroJerkMag, features: &features)
        
        // Step 10: Extract frequency domain features (features 266-561)
        extractFrequencyDomainFeatures(prefix: "fBodyAcc", x: bodyAcc.x, y: bodyAcc.y, z: bodyAcc.z, features: &features)
        extractFrequencyDomainFeatures(prefix: "fBodyAccJerk", x: bodyAccJerkX, y: bodyAccJerkY, z: bodyAccJerkZ, features: &features)
        extractFrequencyDomainFeatures(prefix: "fBodyGyro", x: gyroX, y: gyroY, z: gyroZ, features: &features)
        extractFrequencyDomainFeaturesMagnitude(prefix: "fBodyAccMag", mag: bodyAccMag, features: &features)
        extractFrequencyDomainFeaturesMagnitude(prefix: "fBodyBodyAccJerkMag", mag: bodyAccJerkMag, features: &features)
        extractFrequencyDomainFeaturesMagnitude(prefix: "fBodyBodyGyroMag", mag: bodyGyroMag, features: &features)
        extractFrequencyDomainFeaturesMagnitude(prefix: "fBodyBodyGyroJerkMag", mag: bodyGyroJerkMag, features: &features)
        
        // Step 11: Extract angle features (features 555-561)
        extractAngleFeatures(
            bodyAcc: bodyAcc, bodyAccJerk: (bodyAccJerkX, bodyAccJerkY, bodyAccJerkZ),
            bodyGyro: (gyroX, gyroY, gyroZ), bodyGyroJerk: (bodyGyroJerkX, bodyGyroJerkY, bodyGyroJerkZ),
            gravityAcc: gravityAcc, features: &features
        )
        
        return features
    }
    
    /**
     * Separate gravity from body acceleration using low-pass filter.
     */
    private func separateGravity(
        accelX: [Double],
        accelY: [Double],
        accelZ: [Double]
    ) -> (body: (x: [Double], y: [Double], z: [Double]), gravity: (x: [Double], y: [Double], z: [Double])) {
        let windowSize = min(10, accelX.count / 2)
        if windowSize < 2 {
            return (
                body: (accelX, accelY, accelZ),
                gravity: (Array(repeating: 0.0, count: accelX.count), Array(repeating: 0.0, count: accelY.count), Array(repeating: 0.0, count: accelZ.count))
            )
        }
        
        let gravityX = movingAverage(data: accelX, windowSize: windowSize)
        let gravityY = movingAverage(data: accelY, windowSize: windowSize)
        let gravityZ = movingAverage(data: accelZ, windowSize: windowSize)
        
        let bodyX = zip(accelX, gravityX).map { $0 - $1 }
        let bodyY = zip(accelY, gravityY).map { $0 - $1 }
        let bodyZ = zip(accelZ, gravityZ).map { $0 - $1 }
        
        return (
            body: (bodyX, bodyY, bodyZ),
            gravity: (gravityX, gravityY, gravityZ)
        )
    }
    
    private func movingAverage(data: [Double], windowSize: Int) -> [Double] {
        if data.isEmpty { return [] }
        
        var result: [Double] = []
        for i in 0..<data.count {
            let start = max(0, i - windowSize / 2)
            let end = min(data.count, i + windowSize / 2 + 1)
            let window = Array(data[start..<end])
            result.append(window.reduce(0, +) / Double(window.count))
        }
        return result
    }
    
    /**
     * Calculate jerk (derivative) of signal.
     */
    private func calculateJerk(_ signal: [Double]) -> [Double] {
        if signal.count < 2 { return [] }
        
        var jerk: [Double] = []
        let dt = 0.02 // 20ms, assuming 50Hz sampling rate
        for i in 1..<signal.count {
            jerk.append((signal[i] - signal[i - 1]) / dt)
        }
        return jerk
    }
    
    /**
     * Calculate magnitude: sqrt(x² + y² + z²)
     */
    private func calculateMagnitude(_ x: [Double], _ y: [Double], _ z: [Double]) -> [Double] {
        let minSize = min(x.count, min(y.count, z.count))
        return (0..<minSize).map { i in
            sqrt(x[i] * x[i] + y[i] * y[i] + z[i] * z[i])
        }
    }
    
    /**
     * Extract time domain features for 3-axis signals.
     */
    private func extractTimeDomainFeatures(
        prefix: String,
        x: [Double],
        y: [Double],
        z: [Double],
        features: inout [String: Double]
    ) {
        // Mean
        features["\(prefix)-mean()-X"] = x.average()
        features["\(prefix)-mean()-Y"] = y.average()
        features["\(prefix)-mean()-Z"] = z.average()
        
        // Std
        features["\(prefix)-std()-X"] = stdDev(x)
        features["\(prefix)-std()-Y"] = stdDev(y)
        features["\(prefix)-std()-Z"] = stdDev(z)
        
        // MAD
        features["\(prefix)-mad()-X"] = mad(x)
        features["\(prefix)-mad()-Y"] = mad(y)
        features["\(prefix)-mad()-Z"] = mad(z)
        
        // Max
        features["\(prefix)-max()-X"] = x.max() ?? 0.0
        features["\(prefix)-max()-Y"] = y.max() ?? 0.0
        features["\(prefix)-max()-Z"] = z.max() ?? 0.0
        
        // Min
        features["\(prefix)-min()-X"] = x.min() ?? 0.0
        features["\(prefix)-min()-Y"] = y.min() ?? 0.0
        features["\(prefix)-min()-Z"] = z.min() ?? 0.0
        
        // SMA
        let sma = (x.map { abs($0) } + y.map { abs($0) } + z.map { abs($0) }).average()
        features["\(prefix)-sma()"] = sma
        
        // Energy
        features["\(prefix)-energy()-X"] = energy(x)
        features["\(prefix)-energy()-Y"] = energy(y)
        features["\(prefix)-energy()-Z"] = energy(z)
        
        // IQR
        features["\(prefix)-iqr()-X"] = iqr(x)
        features["\(prefix)-iqr()-Y"] = iqr(y)
        features["\(prefix)-iqr()-Z"] = iqr(z)
        
        // Entropy
        features["\(prefix)-entropy()-X"] = entropy(x)
        features["\(prefix)-entropy()-Y"] = entropy(y)
        features["\(prefix)-entropy()-Z"] = entropy(z)
        
        // AR Coefficients
        let arCoeffsX = arCoefficients(x, order: 4)
        let arCoeffsY = arCoefficients(y, order: 4)
        let arCoeffsZ = arCoefficients(z, order: 4)
        for i in 0..<4 {
            features["\(prefix)-arCoeff()-X,\(i + 1)"] = arCoeffsX[safe: i] ?? 0.0
            features["\(prefix)-arCoeff()-Y,\(i + 1)"] = arCoeffsY[safe: i] ?? 0.0
            features["\(prefix)-arCoeff()-Z,\(i + 1)"] = arCoeffsZ[safe: i] ?? 0.0
        }
        
        // Correlation
        features["\(prefix)-correlation()-X,Y"] = correlation(x, y)
        features["\(prefix)-correlation()-X,Z"] = correlation(x, z)
        features["\(prefix)-correlation()-Y,Z"] = correlation(y, z)
    }
    
    /**
     * Extract time domain features for magnitude signals.
     */
    private func extractTimeDomainFeaturesMagnitude(
        prefix: String,
        mag: [Double],
        features: inout [String: Double]
    ) {
        features["\(prefix)-mean()"] = mag.average()
        features["\(prefix)-std()"] = stdDev(mag)
        features["\(prefix)-mad()"] = mad(mag)
        features["\(prefix)-max()"] = mag.max() ?? 0.0
        features["\(prefix)-min()"] = mag.min() ?? 0.0
        features["\(prefix)-sma()"] = mag.map { abs($0) }.average()
        features["\(prefix)-energy()"] = energy(mag)
        features["\(prefix)-iqr()"] = iqr(mag)
        features["\(prefix)-entropy()"] = entropy(mag)
        
        let arCoeffs = arCoefficients(mag, order: 4)
        for i in 0..<4 {
            features["\(prefix)-arCoeff()\(i + 1)"] = arCoeffs[safe: i] ?? 0.0
        }
    }
    
    /**
     * Extract frequency domain features using FFT.
     */
    private func extractFrequencyDomainFeatures(
        prefix: String,
        x: [Double],
        y: [Double],
        z: [Double],
        features: inout [String: Double]
    ) {
        let fftX = fft(x)
        let fftY = fft(y)
        let fftZ = fft(z)
        
        let absX = fftX.map { abs($0) }
        let absY = fftY.map { abs($0) }
        let absZ = fftZ.map { abs($0) }
        
        // Mean
        features["\(prefix)-mean()-X"] = absX.average()
        features["\(prefix)-mean()-Y"] = absY.average()
        features["\(prefix)-mean()-Z"] = absZ.average()
        
        // Std
        features["\(prefix)-std()-X"] = stdDev(absX)
        features["\(prefix)-std()-Y"] = stdDev(absY)
        features["\(prefix)-std()-Z"] = stdDev(absZ)
        
        // MAD
        features["\(prefix)-mad()-X"] = mad(absX)
        features["\(prefix)-mad()-Y"] = mad(absY)
        features["\(prefix)-mad()-Z"] = mad(absZ)
        
        // Max
        features["\(prefix)-max()-X"] = absX.max() ?? 0.0
        features["\(prefix)-max()-Y"] = absY.max() ?? 0.0
        features["\(prefix)-max()-Z"] = absZ.max() ?? 0.0
        
        // Min
        features["\(prefix)-min()-X"] = absX.min() ?? 0.0
        features["\(prefix)-min()-Y"] = absY.min() ?? 0.0
        features["\(prefix)-min()-Z"] = absZ.min() ?? 0.0
        
        // SMA
        let sma = (absX + absY + absZ).average()
        features["\(prefix)-sma()"] = sma
        
        // Energy
        features["\(prefix)-energy()-X"] = energy(absX)
        features["\(prefix)-energy()-Y"] = energy(absY)
        features["\(prefix)-energy()-Z"] = energy(absZ)
        
        // IQR
        features["\(prefix)-iqr()-X"] = iqr(absX)
        features["\(prefix)-iqr()-Y"] = iqr(absY)
        features["\(prefix)-iqr()-Z"] = iqr(absZ)
        
        // Entropy
        features["\(prefix)-entropy()-X"] = entropy(absX)
        features["\(prefix)-entropy()-Y"] = entropy(absY)
        features["\(prefix)-entropy()-Z"] = entropy(absZ)
        
        // MaxInds
        if let maxX = absX.max(), let idxX = absX.firstIndex(of: maxX) {
            features["\(prefix)-maxInds-X"] = Double(idxX)
        } else {
            features["\(prefix)-maxInds-X"] = 0.0
        }
        if let maxY = absY.max(), let idxY = absY.firstIndex(of: maxY) {
            features["\(prefix)-maxInds-Y"] = Double(idxY)
        } else {
            features["\(prefix)-maxInds-Y"] = 0.0
        }
        if let maxZ = absZ.max(), let idxZ = absZ.firstIndex(of: maxZ) {
            features["\(prefix)-maxInds-Z"] = Double(idxZ)
        } else {
            features["\(prefix)-maxInds-Z"] = 0.0
        }
        
        // MeanFreq
        features["\(prefix)-meanFreq()-X"] = meanFreq(fftX)
        features["\(prefix)-meanFreq()-Y"] = meanFreq(fftY)
        features["\(prefix)-meanFreq()-Z"] = meanFreq(fftZ)
        
        // Skewness
        features["\(prefix)-skewness()-X"] = skewness(absX)
        features["\(prefix)-skewness()-Y"] = skewness(absY)
        features["\(prefix)-skewness()-Z"] = skewness(absZ)
        
        // Kurtosis
        features["\(prefix)-kurtosis()-X"] = kurtosis(absX)
        features["\(prefix)-kurtosis()-Y"] = kurtosis(absY)
        features["\(prefix)-kurtosis()-Z"] = kurtosis(absZ)
        
        // BandsEnergy
        extractBandsEnergy(prefix: prefix, fftX: fftX, fftY: fftY, fftZ: fftZ, features: &features)
    }
    
    /**
     * Extract frequency domain features for magnitude signals.
     */
    private func extractFrequencyDomainFeaturesMagnitude(
        prefix: String,
        mag: [Double],
        features: inout [String: Double]
    ) {
        let fftMag = fft(mag)
        let absMag = fftMag.map { abs($0) }
        
        features["\(prefix)-mean()"] = absMag.average()
        features["\(prefix)-std()"] = stdDev(absMag)
        features["\(prefix)-mad()"] = mad(absMag)
        features["\(prefix)-max()"] = absMag.max() ?? 0.0
        features["\(prefix)-min()"] = absMag.min() ?? 0.0
        features["\(prefix)-sma()"] = absMag.average()
        features["\(prefix)-energy()"] = energy(absMag)
        features["\(prefix)-iqr()"] = iqr(absMag)
        features["\(prefix)-entropy()"] = entropy(absMag)
        if let max = absMag.max(), let idx = absMag.firstIndex(of: max) {
            features["\(prefix)-maxInds"] = Double(idx)
        } else {
            features["\(prefix)-maxInds"] = 0.0
        }
        features["\(prefix)-meanFreq()"] = meanFreq(fftMag)
        features["\(prefix)-skewness()"] = skewness(absMag)
        features["\(prefix)-kurtosis()"] = kurtosis(absMag)
    }
    
    /**
     * Extract angle features.
     */
    private func extractAngleFeatures(
        bodyAcc: (x: [Double], y: [Double], z: [Double]),
        bodyAccJerk: ([Double], [Double], [Double]),
        bodyGyro: ([Double], [Double], [Double]),
        bodyGyroJerk: ([Double], [Double], [Double]),
        gravityAcc: (x: [Double], y: [Double], z: [Double]),
        features: inout [String: Double]
    ) {
        let bodyAccMean = (bodyAcc.x.average(), bodyAcc.y.average(), bodyAcc.z.average())
        let bodyAccJerkMean = (bodyAccJerk.0.average(), bodyAccJerk.1.average(), bodyAccJerk.2.average())
        let bodyGyroMean = (bodyGyro.0.average(), bodyGyro.1.average(), bodyGyro.2.average())
        let bodyGyroJerkMean = (bodyGyroJerk.0.average(), bodyGyroJerk.1.average(), bodyGyroJerk.2.average())
        let gravityMean = (gravityAcc.x.average(), gravityAcc.y.average(), gravityAcc.z.average())
        
        features["angle(tBodyAccMean,gravity)"] = angle(bodyAccMean, gravityMean)
        features["angle(tBodyAccJerkMean),gravityMean)"] = angle(bodyAccJerkMean, gravityMean)
        features["angle(tBodyGyroMean,gravityMean)"] = angle(bodyGyroMean, gravityMean)
        features["angle(tBodyGyroJerkMean,gravityMean)"] = angle(bodyGyroJerkMean, gravityMean)
        
        let xAxis = (1.0, 0.0, 0.0)
        let yAxis = (0.0, 1.0, 0.0)
        let zAxis = (0.0, 0.0, 1.0)
        features["angle(X,gravityMean)"] = angle(xAxis, gravityMean)
        features["angle(Y,gravityMean)"] = angle(yAxis, gravityMean)
        features["angle(Z,gravityMean)"] = angle(zAxis, gravityMean)
    }
    
    // Helper functions for statistical calculations
    
    private func stdDev(_ data: [Double]) -> Double {
        if data.isEmpty { return 0.0 }
        let mean = data.average()
        let variance = data.map { pow($0 - mean, 2) }.average()
        return sqrt(variance)
    }
    
    private func mad(_ data: [Double]) -> Double {
        if data.isEmpty { return 0.0 }
        let sorted = data.sorted()
        let median = sorted.count % 2 == 0 ?
            (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0 :
            sorted[sorted.count / 2]
        return sorted.map { abs($0 - median) }.average()
    }
    
    private func energy(_ data: [Double]) -> Double {
        return data.map { $0 * $0 }.reduce(0, +) / Double(data.count)
    }
    
    private func iqr(_ data: [Double]) -> Double {
        if data.count < 4 { return 0.0 }
        let sorted = data.sorted()
        let q1Index = sorted.count / 4
        let q3Index = (3 * sorted.count) / 4
        return sorted[q3Index] - sorted[q1Index]
    }
    
    private func entropy(_ data: [Double]) -> Double {
        if data.isEmpty { return 0.0 }
        let min = data.min() ?? 0.0
        let max = data.max() ?? 1.0
        let range = max - min
        if range == 0.0 { return 0.0 }
        
        let normalized = data.map { ($0 - min) / range }
        let bins = 10
        var histogram = Array(repeating: 0, count: bins)
        normalized.forEach { value in
            let bin = min(Int(value * Double(bins)), bins - 1)
            histogram[bin] += 1
        }
        
        var entropy = 0.0
        histogram.forEach { count in
            if count > 0 {
                let p = Double(count) / Double(data.count)
                entropy -= p * log(p)
            }
        }
        return entropy
    }
    
    private func arCoefficients(_ data: [Double], order: Int) -> [Double] {
        if data.count < order + 1 { return Array(repeating: 0.0, count: order) }
        
        let mean = data.average()
        let centered = data.map { $0 - mean }
        
        // Calculate autocorrelation (need order + 1 values for lags 0 to order)
        var autocorr: [Double] = []
        for lag in 0...order {
            var sum = 0.0
            for i in 0..<(data.count - lag) {
                sum += centered[i] * centered[i + lag]
            }
            autocorr.append(sum / Double(data.count))
        }
        
        if autocorr[0] == 0.0 { return Array(repeating: 0.0, count: order) }
        
        var prev = [autocorr[1] / autocorr[0]]
        var coeffs = prev
        
        for k in 1..<order {
            var num = autocorr[k + 1]
            for j in 0..<k {
                num -= prev[j] * autocorr[k - j]
            }
            let denom = 1.0 - zip(prev, autocorr.dropFirst()).map { $0 * $1 }.reduce(0, +)
            
            if denom == 0.0 {
                coeffs.append(0.0)
                continue
            }
            
            let ak = num / denom
            var newCoeffs: [Double] = []
            for i in 0..<k {
                newCoeffs.append(prev[i] - ak * prev[k - 1 - i])
            }
            newCoeffs.append(ak)
            prev = newCoeffs
            if coeffs.count < order {
                coeffs.append(ak)
            }
        }
        
        return Array(coeffs.prefix(order))
    }
    
    private func correlation(_ x: [Double], _ y: [Double]) -> Double {
        if x.count != y.count || x.isEmpty { return 0.0 }
        
        let meanX = x.average()
        let meanY = y.average()
        
        var numerator = 0.0
        var sumSqX = 0.0
        var sumSqY = 0.0
        
        for i in 0..<x.count {
            let dx = x[i] - meanX
            let dy = y[i] - meanY
            numerator += dx * dy
            sumSqX += dx * dx
            sumSqY += dy * dy
        }
        
        let denominator = sqrt(sumSqX * sumSqY)
        return denominator == 0.0 ? 0.0 : numerator / denominator
    }
    
    private func fft(_ data: [Double]) -> [Double] {
        if data.isEmpty { return [] }
        
        // Use Accelerate framework for FFT
        let n = data.count
        let log2n = vDSP_Length(log2(Double(n)))
        let fftSetup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2))
        
        guard let setup = fftSetup else {
            // Fallback to simple implementation if Accelerate fails
            return simpleFFT(data)
        }
        
        defer { vDSP_destroy_fftsetupD(setup) }
        
        // Pad to next power of 2
        let paddedSize = 1 << log2n
        var padded = data + Array(repeating: 0.0, count: paddedSize - n)
        
        var realp = [Double](repeating: 0.0, count: paddedSize / 2)
        var imagp = [Double](repeating: 0.0, count: paddedSize / 2)
        
        var splitComplex = DSPSplitComplexD(realp: &realp, imagp: &imagp)
        
        padded.withUnsafeBufferPointer { buffer in
            var input = buffer.baseAddress!
            vDSP_ctozD(UnsafePointer<DSPDoubleComplex>(OpaquePointer(input)), 2, &splitComplex, 1, vDSP_Length(paddedSize / 2))
        }
        
        vDSP_fft_zipD(setup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
        
        // Calculate magnitudes
        var magnitudes = [Double](repeating: 0.0, count: paddedSize / 2)
        vDSP_zvmagsD(&splitComplex, 1, &magnitudes, 1, vDSP_Length(paddedSize / 2))
        
        return Array(magnitudes.prefix(n)).map { sqrt($0) }
    }
    
    private func simpleFFT(_ data: [Double]) -> [Double] {
        // Simple FFT fallback implementation
        if data.count <= 1 { return data }
        
        let n = data.count
        let even = simpleFFT(Array(stride(from: 0, to: n, by: 2).map { data[$0] }))
        let odd = simpleFFT(Array(stride(from: 1, to: n, by: 2).map { data[$0] }))
        
        var result = [Double](repeating: 0.0, count: n)
        for k in 0..<(n / 2) {
            let t = -2.0 * Double.pi * Double(k) / Double(n)
            let re = cos(t)
            let im = sin(t)
            let oddK = odd[safe: k] ?? 0.0
            let evenK = even[safe: k] ?? 0.0
            result[k] = evenK + re * oddK
            result[k + n / 2] = evenK - re * oddK
        }
        return result.map { abs($0) }
    }
    
    private func meanFreq(_ fftData: [Double]) -> Double {
        if fftData.isEmpty { return 0.0 }
        let magnitudes = fftData.map { abs($0) }
        let totalEnergy = magnitudes.reduce(0, +)
        if totalEnergy == 0.0 { return 0.0 }
        
        var weightedSum = 0.0
        for (index, mag) in magnitudes.enumerated() {
            weightedSum += Double(index) * mag
        }
        return weightedSum / totalEnergy
    }
    
    private func skewness(_ data: [Double]) -> Double {
        if data.count < 3 { return 0.0 }
        let mean = data.average()
        let std = stdDev(data)
        if std == 0.0 { return 0.0 }
        
        let n = Double(data.count)
        let sum = data.map { pow(($0 - mean) / std, 3.0) }.reduce(0, +)
        return (n / ((n - 1.0) * (n - 2.0))) * sum
    }
    
    private func kurtosis(_ data: [Double]) -> Double {
        if data.count < 4 { return 0.0 }
        let mean = data.average()
        let std = stdDev(data)
        if std == 0.0 { return 0.0 }
        
        let n = Double(data.count)
        let sum = data.map { pow(($0 - mean) / std, 4.0) }.reduce(0, +)
        return ((n * (n + 1.0)) / ((n - 1.0) * (n - 2.0) * (n - 3.0))) * sum -
            3.0 * (n - 1.0) * (n - 1.0) / ((n - 2.0) * (n - 3.0))
    }
    
    private func extractBandsEnergy(
        prefix: String,
        fftX: [Double],
        fftY: [Double],
        fftZ: [Double],
        features: inout [String: Double]
    ) {
        let absX = fftX.map { abs($0) }
        let absY = fftY.map { abs($0) }
        let absZ = fftZ.map { abs($0) }
        
        let bands = [
            (1, 8), (9, 16), (17, 24), (25, 32),
            (33, 40), (41, 48), (49, 56), (57, 64),
            (1, 16), (17, 32), (33, 48), (49, 64),
            (1, 24), (25, 48)
        ]
        
        for (start, end) in bands {
            let startIdx = min(start - 1, absX.count)
            let endIdx = min(end, absX.count)
            
            let bandEnergyX = absX[startIdx..<endIdx].map { $0 * $0 }.reduce(0, +)
            let bandEnergyY = absY[startIdx..<endIdx].map { $0 * $0 }.reduce(0, +)
            let bandEnergyZ = absZ[startIdx..<endIdx].map { $0 * $0 }.reduce(0, +)
            
            features["\(prefix)-bandsEnergy()-\(start),\(end)-X"] = bandEnergyX
            features["\(prefix)-bandsEnergy()-\(start),\(end)-Y"] = bandEnergyY
            features["\(prefix)-bandsEnergy()-\(start),\(end)-Z"] = bandEnergyZ
        }
    }
    
    private func angle(_ v1: (Double, Double, Double), _ v2: (Double, Double, Double)) -> Double {
        let dot = v1.0 * v2.0 + v1.1 * v2.1 + v1.2 * v2.2
        let mag1 = sqrt(v1.0 * v1.0 + v1.1 * v1.1 + v1.2 * v1.2)
        let mag2 = sqrt(v2.0 * v2.0 + v2.1 * v2.1 + v2.2 * v2.2)
        
        if mag1 == 0.0 || mag2 == 0.0 { return 0.0 }
        let cosAngle = max(-1.0, min(1.0, dot / (mag1 * mag2)))
        return acos(cosAngle)
    }
}

// Array extension for average
extension Array where Element == Double {
    func average() -> Double {
        return isEmpty ? 0.0 : reduce(0, +) / Double(count)
    }
}

// Array extension for safe indexing
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

