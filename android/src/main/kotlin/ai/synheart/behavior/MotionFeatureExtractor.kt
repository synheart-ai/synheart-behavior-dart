package ai.synheart.behavior

import kotlin.math.*

// Type aliases for nested Triple structure
typealias Triple3D = Triple<List<Double>, List<Double>, List<Double>>

typealias GravityResult = Pair<Triple3D, Triple3D>

/**
 * Extracts 561 ML features from raw accelerometer and gyroscope data. Based on HAR (Human Activity
 * Recognition) feature set.
 */
class MotionFeatureExtractor {

    /**
     * Extract all 561 features from raw sensor data in a 5-second window.
     *
     * @param accelX Raw accelerometer X values
     * @param accelY Raw accelerometer Y values
     * @param accelZ Raw accelerometer Z values
     * @param gyroX Raw gyroscope X values
     * @param gyroY Raw gyroscope Y values
     * @param gyroZ Raw gyroscope Z values
     * @return Map of feature names to values (561 features total)
     */
    fun extractFeatures(
            accelX: List<Double>,
            accelY: List<Double>,
            accelZ: List<Double>,
            gyroX: List<Double>,
            gyroY: List<Double>,
            gyroZ: List<Double>
    ): Map<String, Double> {
        val features = mutableMapOf<String, Double>()

        if (accelX.isEmpty() || gyroX.isEmpty()) {
            // Return zeros for all features if no data
            return generateEmptyFeatures()
        }

        // Step 1: Separate gravity from body acceleration (low-pass filter)
        val gravityResult: GravityResult = separateGravity(accelX, accelY, accelZ)
        val bodyAcc: Triple3D = gravityResult.first
        val gravityAcc: Triple3D = gravityResult.second
        val bodyAccX: List<Double> = bodyAcc.first
        val bodyAccY: List<Double> = bodyAcc.second
        val bodyAccZ: List<Double> = bodyAcc.third
        val gravityAccX: List<Double> = gravityAcc.first
        val gravityAccY: List<Double> = gravityAcc.second
        val gravityAccZ: List<Double> = gravityAcc.third

        // Step 2: Calculate jerk (derivative) for acceleration and gyroscope
        val bodyAccJerkX = calculateJerk(bodyAccX)
        val bodyAccJerkY = calculateJerk(bodyAccY)
        val bodyAccJerkZ = calculateJerk(bodyAccZ)

        val bodyGyroJerkX = calculateJerk(gyroX)
        val bodyGyroJerkY = calculateJerk(gyroY)
        val bodyGyroJerkZ = calculateJerk(gyroZ)

        // Step 3: Calculate magnitudes
        val bodyAccMag = calculateMagnitude(bodyAccX, bodyAccY, bodyAccZ)
        val gravityAccMag = calculateMagnitude(gravityAccX, gravityAccY, gravityAccZ)
        val bodyAccJerkMag = calculateMagnitude(bodyAccJerkX, bodyAccJerkY, bodyAccJerkZ)
        val bodyGyroMag = calculateMagnitude(gyroX, gyroY, gyroZ)
        val bodyGyroJerkMag = calculateMagnitude(bodyGyroJerkX, bodyGyroJerkY, bodyGyroJerkZ)

        // Step 4: Extract time domain features for body acceleration (features 1-40)
        extractTimeDomainFeatures("tBodyAcc", bodyAccX, bodyAccY, bodyAccZ, features, 1)

        // Step 5: Extract time domain features for gravity acceleration (features 41-80)
        extractTimeDomainFeatures(
                "tGravityAcc",
                gravityAccX,
                gravityAccY,
                gravityAccZ,
                features,
                41
        )

        // Step 6: Extract time domain features for body acceleration jerk (features 81-120)
        extractTimeDomainFeatures(
                "tBodyAccJerk",
                bodyAccJerkX,
                bodyAccJerkY,
                bodyAccJerkZ,
                features,
                81
        )

        // Step 7: Extract time domain features for body gyroscope (features 121-160)
        extractTimeDomainFeatures("tBodyGyro", gyroX, gyroY, gyroZ, features, 121)

        // Step 8: Extract time domain features for body gyroscope jerk (features 161-200)
        extractTimeDomainFeatures(
                "tBodyGyroJerk",
                bodyGyroJerkX,
                bodyGyroJerkY,
                bodyGyroJerkZ,
                features,
                161
        )

        // Step 9: Extract time domain features for magnitudes (features 201-265)
        extractTimeDomainFeaturesMagnitude("tBodyAccMag", bodyAccMag, features, 201)
        extractTimeDomainFeaturesMagnitude("tGravityAccMag", gravityAccMag, features, 214)
        extractTimeDomainFeaturesMagnitude("tBodyAccJerkMag", bodyAccJerkMag, features, 227)
        extractTimeDomainFeaturesMagnitude("tBodyGyroMag", bodyGyroMag, features, 240)
        extractTimeDomainFeaturesMagnitude("tBodyGyroJerkMag", bodyGyroJerkMag, features, 253)

        // Step 10: Extract frequency domain features (features 266-561)
        extractFrequencyDomainFeatures("fBodyAcc", bodyAccX, bodyAccY, bodyAccZ, features, 266)
        extractFrequencyDomainFeatures(
                "fBodyAccJerk",
                bodyAccJerkX,
                bodyAccJerkY,
                bodyAccJerkZ,
                features,
                345
        )
        extractFrequencyDomainFeatures("fBodyGyro", gyroX, gyroY, gyroZ, features, 424)
        extractFrequencyDomainFeaturesMagnitude("fBodyAccMag", bodyAccMag, features, 503)
        extractFrequencyDomainFeaturesMagnitude(
                "fBodyBodyAccJerkMag",
                bodyAccJerkMag,
                features,
                516
        )
        extractFrequencyDomainFeaturesMagnitude("fBodyBodyGyroMag", bodyGyroMag, features, 529)
        extractFrequencyDomainFeaturesMagnitude(
                "fBodyBodyGyroJerkMag",
                bodyGyroJerkMag,
                features,
                542
        )

        // Step 11: Extract angle features (features 555-561)
        extractAngleFeatures(
                bodyAccX,
                bodyAccY,
                bodyAccZ,
                bodyAccJerkX,
                bodyAccJerkY,
                bodyAccJerkZ,
                gyroX,
                gyroY,
                gyroZ,
                bodyGyroJerkX,
                bodyGyroJerkY,
                bodyGyroJerkZ,
                gravityAccX,
                gravityAccY,
                gravityAccZ,
                features,
                555
        )

        return features
    }

    /**
     * Separate gravity from body acceleration using low-pass filter. Gravity is the low-frequency
     * component, body is the high-frequency component.
     */
    private fun separateGravity(
            accelX: List<Double>,
            accelY: List<Double>,
            accelZ: List<Double>
    ): GravityResult {
        // Simple low-pass filter: moving average with window size 10
        // Gravity = low-pass filtered signal
        // Body = original - gravity
        val windowSize = minOf(10, accelX.size / 2)
        if (windowSize < 2) {
            // If too few samples, return original as body, zero as gravity
            val zeroX: List<Double> = List(accelX.size) { 0.0 }
            val zeroY: List<Double> = List(accelY.size) { 0.0 }
            val zeroZ: List<Double> = List(accelZ.size) { 0.0 }
            val bodyTriple = Triple(accelX, accelY, accelZ)
            val gravityTriple = Triple(zeroX, zeroY, zeroZ)
            return Pair(bodyTriple, gravityTriple)
        }

        val gravityX = movingAverage(accelX, windowSize)
        val gravityY = movingAverage(accelY, windowSize)
        val gravityZ = movingAverage(accelZ, windowSize)

        val bodyX = accelX.zip(gravityX).map { it.first - it.second }
        val bodyY = accelY.zip(gravityY).map { it.first - it.second }
        val bodyZ = accelZ.zip(gravityZ).map { it.first - it.second }

        val bodyTriple = Triple(bodyX, bodyY, bodyZ)
        val gravityTriple = Triple(gravityX, gravityY, gravityZ)
        return Pair(bodyTriple, gravityTriple)
    }

    /** Calculate moving average (low-pass filter). */
    private fun movingAverage(data: List<Double>, windowSize: Int): List<Double> {
        if (data.isEmpty()) return emptyList()

        val result = mutableListOf<Double>()
        for (i in data.indices) {
            val start = maxOf(0, i - windowSize / 2)
            val end = minOf(data.size, i + windowSize / 2 + 1)
            val window = data.subList(start, end)
            result.add(window.average())
        }
        return result
    }

    /** Calculate jerk (derivative) of signal. */
    private fun calculateJerk(signal: List<Double>): List<Double> {
        if (signal.size < 2) return emptyList()

        val jerk = mutableListOf<Double>()
        for (i in 1 until signal.size) {
            // Jerk = difference between consecutive samples
            // Assuming 50Hz sampling rate (0.02s intervals)
            val dt = 0.02 // 20ms
            jerk.add((signal[i] - signal[i - 1]) / dt)
        }
        return jerk
    }

    /** Calculate magnitude: sqrt(x² + y² + z²) */
    private fun calculateMagnitude(
            x: List<Double>,
            y: List<Double>,
            z: List<Double>
    ): List<Double> {
        val minSize = minOf(x.size, y.size, z.size)
        return (0 until minSize).map { i -> sqrt(x[i] * x[i] + y[i] * y[i] + z[i] * z[i]) }
    }

    /** Extract time domain features for 3-axis signals. */
    private fun extractTimeDomainFeatures(
            prefix: String,
            x: List<Double>,
            y: List<Double>,
            z: List<Double>,
            features: MutableMap<String, Double>,
            startIndex: Int // Kept for reference but not used in feature names
    ) {
        var index = startIndex

        // Mean (features 1-3, 41-43, etc.)
        features["${prefix}-mean()-X"] = x.average()
        features["${prefix}-mean()-Y"] = y.average()
        features["${prefix}-mean()-Z"] = z.average()

        // Std (features 4-6)
        features["${prefix}-std()-X"] = stdDev(x)
        features["${prefix}-std()-Y"] = stdDev(y)
        features["${prefix}-std()-Z"] = stdDev(z)

        // MAD - Median Absolute Deviation (features 7-9)
        features["${prefix}-mad()-X"] = mad(x)
        features["${prefix}-mad()-Y"] = mad(y)
        features["${prefix}-mad()-Z"] = mad(z)

        // Max (features 10-12)
        features["${prefix}-max()-X"] = x.maxOrNull() ?: 0.0
        features["${prefix}-max()-Y"] = y.maxOrNull() ?: 0.0
        features["${prefix}-max()-Z"] = z.maxOrNull() ?: 0.0

        // Min (features 13-15)
        features["${prefix}-min()-X"] = x.minOrNull() ?: 0.0
        features["${prefix}-min()-Y"] = y.minOrNull() ?: 0.0
        features["${prefix}-min()-Z"] = z.minOrNull() ?: 0.0

        // SMA - Signal Magnitude Area (feature 16)
        val sma = (x.map { abs(it) } + y.map { abs(it) } + z.map { abs(it) }).average()
        features["${prefix}-sma()"] = sma

        // Energy (features 17-19)
        features["${prefix}-energy()-X"] = energy(x)
        features["${prefix}-energy()-Y"] = energy(y)
        features["${prefix}-energy()-Z"] = energy(z)

        // IQR - Interquartile Range (features 20-22)
        features["${prefix}-iqr()-X"] = iqr(x)
        features["${prefix}-iqr()-Y"] = iqr(y)
        features["${prefix}-iqr()-Z"] = iqr(z)

        // Entropy (features 23-25)
        features["${prefix}-entropy()-X"] = entropy(x)
        features["${prefix}-entropy()-Y"] = entropy(y)
        features["${prefix}-entropy()-Z"] = entropy(z)

        // AR Coefficients (features 26-37: 4 coefficients × 3 axes)
        val arCoeffsX = arCoefficients(x, 4)
        val arCoeffsY = arCoefficients(y, 4)
        val arCoeffsZ = arCoefficients(z, 4)
        for (i in 0 until 4) {
            features["${prefix}-arCoeff()-X,${i + 1}"] = arCoeffsX.getOrElse(i) { 0.0 }
            features["${prefix}-arCoeff()-Y,${i + 1}"] = arCoeffsY.getOrElse(i) { 0.0 }
            features["${prefix}-arCoeff()-Z,${i + 1}"] = arCoeffsZ.getOrElse(i) { 0.0 }
        }

        // Correlation (features 38-40)
        features["${prefix}-correlation()-X,Y"] = correlation(x, y)
        features["${prefix}-correlation()-X,Z"] = correlation(x, z)
        features["${prefix}-correlation()-Y,Z"] = correlation(y, z)
    }

    /** Extract time domain features for magnitude signals. */
    private fun extractTimeDomainFeaturesMagnitude(
            prefix: String,
            mag: List<Double>,
            features: MutableMap<String, Double>,
            startIndex: Int
    ) {
        features["${prefix}-mean()"] = mag.average()
        features["${prefix}-std()"] = stdDev(mag)
        features["${prefix}-mad()"] = mad(mag)
        features["${prefix}-max()"] = mag.maxOrNull() ?: 0.0
        features["${prefix}-min()"] = mag.minOrNull() ?: 0.0
        features["${prefix}-sma()"] = mag.map { abs(it) }.average()
        features["${prefix}-energy()"] = energy(mag)
        features["${prefix}-iqr()"] = iqr(mag)
        features["${prefix}-entropy()"] = entropy(mag)

        // AR Coefficients (4 coefficients)
        val arCoeffs = arCoefficients(mag, 4)
        for (i in 0 until 4) {
            features["${prefix}-arCoeff()${i + 1}"] = arCoeffs.getOrElse(i) { 0.0 }
        }
    }

    /** Extract frequency domain features using FFT. */
    private fun extractFrequencyDomainFeatures(
            prefix: String,
            x: List<Double>,
            y: List<Double>,
            z: List<Double>,
            features: MutableMap<String, Double>,
            startIndex: Int // Kept for reference but not used in feature names
    ) {
        // Apply FFT
        val fftX = fft(x)
        val fftY = fft(y)
        val fftZ = fft(z)

        val absX = fftX.map { abs(it) }
        val absY = fftY.map { abs(it) }
        val absZ = fftZ.map { abs(it) }

        // Mean
        features["${prefix}-mean()-X"] = absX.average()
        features["${prefix}-mean()-Y"] = absY.average()
        features["${prefix}-mean()-Z"] = absZ.average()

        // Std
        features["${prefix}-std()-X"] = stdDev(absX)
        features["${prefix}-std()-Y"] = stdDev(absY)
        features["${prefix}-std()-Z"] = stdDev(absZ)

        // MAD
        features["${prefix}-mad()-X"] = mad(absX)
        features["${prefix}-mad()-Y"] = mad(absY)
        features["${prefix}-mad()-Z"] = mad(absZ)

        // Max
        features["${prefix}-max()-X"] = absX.maxOrNull() ?: 0.0
        features["${prefix}-max()-Y"] = absY.maxOrNull() ?: 0.0
        features["${prefix}-max()-Z"] = absZ.maxOrNull() ?: 0.0

        // Min
        features["${prefix}-min()-X"] = absX.minOrNull() ?: 0.0
        features["${prefix}-min()-Y"] = absY.minOrNull() ?: 0.0
        features["${prefix}-min()-Z"] = absZ.minOrNull() ?: 0.0

        // SMA
        val sma = (absX + absY + absZ).average()
        features["${prefix}-sma()"] = sma

        // Energy
        features["${prefix}-energy()-X"] = energy(absX)
        features["${prefix}-energy()-Y"] = energy(absY)
        features["${prefix}-energy()-Z"] = energy(absZ)

        // IQR
        features["${prefix}-iqr()-X"] = iqr(absX)
        features["${prefix}-iqr()-Y"] = iqr(absY)
        features["${prefix}-iqr()-Z"] = iqr(absZ)

        // Entropy
        features["${prefix}-entropy()-X"] = entropy(absX)
        features["${prefix}-entropy()-Y"] = entropy(absY)
        features["${prefix}-entropy()-Z"] = entropy(absZ)

        // MaxInds - index of maximum frequency component
        features["${prefix}-maxInds-X"] = absX.indexOf(absX.maxOrNull() ?: 0.0).toDouble()
        features["${prefix}-maxInds-Y"] = absY.indexOf(absY.maxOrNull() ?: 0.0).toDouble()
        features["${prefix}-maxInds-Z"] = absZ.indexOf(absZ.maxOrNull() ?: 0.0).toDouble()

        // MeanFreq - weighted mean frequency
        features["${prefix}-meanFreq()-X"] = meanFreq(fftX)
        features["${prefix}-meanFreq()-Y"] = meanFreq(fftY)
        features["${prefix}-meanFreq()-Z"] = meanFreq(fftZ)

        // Skewness
        features["${prefix}-skewness()-X"] = skewness(absX)
        features["${prefix}-skewness()-Y"] = skewness(absY)
        features["${prefix}-skewness()-Z"] = skewness(absZ)

        // Kurtosis
        features["${prefix}-kurtosis()-X"] = kurtosis(absX)
        features["${prefix}-kurtosis()-Y"] = kurtosis(absY)
        features["${prefix}-kurtosis()-Z"] = kurtosis(absZ)

        // BandsEnergy - energy in frequency bands
        extractBandsEnergy(prefix, fftX, fftY, fftZ, features)
    }

    /** Extract frequency domain features for magnitude signals. */
    private fun extractFrequencyDomainFeaturesMagnitude(
            prefix: String,
            mag: List<Double>,
            features: MutableMap<String, Double>,
            startIndex: Int // Kept for reference but not used in feature names
    ) {
        val fftMag = fft(mag)
        val absMag = fftMag.map { abs(it) }

        features["${prefix}-mean()"] = absMag.average()
        features["${prefix}-std()"] = stdDev(absMag)
        features["${prefix}-mad()"] = mad(absMag)
        features["${prefix}-max()"] = absMag.maxOrNull() ?: 0.0
        features["${prefix}-min()"] = absMag.minOrNull() ?: 0.0
        features["${prefix}-sma()"] = absMag.average()
        features["${prefix}-energy()"] = energy(absMag)
        features["${prefix}-iqr()"] = iqr(absMag)
        features["${prefix}-entropy()"] = entropy(absMag)
        features["${prefix}-maxInds"] = absMag.indexOf(absMag.maxOrNull() ?: 0.0).toDouble()
        features["${prefix}-meanFreq()"] = meanFreq(fftMag)
        features["${prefix}-skewness()"] = skewness(absMag)
        features["${prefix}-kurtosis()"] = kurtosis(absMag)
    }

    /** Extract angle features. */
    private fun extractAngleFeatures(
            bodyAccX: List<Double>,
            bodyAccY: List<Double>,
            bodyAccZ: List<Double>,
            bodyAccJerkX: List<Double>,
            bodyAccJerkY: List<Double>,
            bodyAccJerkZ: List<Double>,
            bodyGyroX: List<Double>,
            bodyGyroY: List<Double>,
            bodyGyroZ: List<Double>,
            bodyGyroJerkX: List<Double>,
            bodyGyroJerkY: List<Double>,
            bodyGyroJerkZ: List<Double>,
            gravityAccX: List<Double>,
            gravityAccY: List<Double>,
            gravityAccZ: List<Double>,
            features: MutableMap<String, Double>,
            startIndex: Int
    ) {
        var index = startIndex

        // Calculate mean vectors
        val bodyAccMean = Triple(bodyAccX.average(), bodyAccY.average(), bodyAccZ.average())
        val bodyAccJerkMean =
                Triple(bodyAccJerkX.average(), bodyAccJerkY.average(), bodyAccJerkZ.average())
        val bodyGyroMean = Triple(bodyGyroX.average(), bodyGyroY.average(), bodyGyroZ.average())
        val bodyGyroJerkMean =
                Triple(bodyGyroJerkX.average(), bodyGyroJerkY.average(), bodyGyroJerkZ.average())
        val gravityMean =
                Triple(gravityAccX.average(), gravityAccY.average(), gravityAccZ.average())

        // Angle between vectors
        features["angle(tBodyAccMean,gravity)"] = angle(bodyAccMean, gravityMean)
        features["angle(tBodyAccJerkMean),gravityMean)"] = angle(bodyAccJerkMean, gravityMean)
        features["angle(tBodyGyroMean,gravityMean)"] = angle(bodyGyroMean, gravityMean)
        features["angle(tBodyGyroJerkMean,gravityMean)"] = angle(bodyGyroJerkMean, gravityMean)

        // Angle with X, Y, Z axes
        val xAxis = Triple(1.0, 0.0, 0.0)
        val yAxis = Triple(0.0, 1.0, 0.0)
        val zAxis = Triple(0.0, 0.0, 1.0)
        features["angle(X,gravityMean)"] = angle(xAxis, gravityMean)
        features["angle(Y,gravityMean)"] = angle(yAxis, gravityMean)
        features["angle(Z,gravityMean)"] = angle(zAxis, gravityMean)
    }

    // Helper functions for statistical calculations

    private fun stdDev(data: List<Double>): Double {
        if (data.isEmpty()) return 0.0
        val mean = data.average()
        val variance = data.map { (it - mean) * (it - mean) }.average()
        return sqrt(variance)
    }

    private fun mad(data: List<Double>): Double {
        if (data.isEmpty()) return 0.0
        val sorted = data.sorted()
        val median =
                if (sorted.size % 2 == 0) {
                    (sorted[sorted.size / 2 - 1] + sorted[sorted.size / 2]) / 2.0
                } else {
                    sorted[sorted.size / 2]
                }
        return sorted.map { abs(it - median) }.average()
    }

    private fun energy(data: List<Double>): Double {
        return data.map { it * it }.sum() / data.size
    }

    private fun iqr(data: List<Double>): Double {
        if (data.size < 4) return 0.0
        val sorted = data.sorted()
        val q1Index = sorted.size / 4
        val q3Index = (3 * sorted.size) / 4
        val q1 = sorted[q1Index]
        val q3 = sorted[q3Index]
        return q3 - q1
    }

    private fun entropy(data: List<Double>): Double {
        if (data.isEmpty()) return 0.0
        // Normalize data to [0, 1]
        val min = data.minOrNull() ?: 0.0
        val max = data.maxOrNull() ?: 1.0
        val range = max - min
        if (range == 0.0) return 0.0

        val normalized = data.map { (it - min) / range }
        // Discretize into bins
        val bins = 10
        val histogram = IntArray(bins)
        normalized.forEach { value ->
            val bin = ((value * bins).toInt().coerceIn(0, bins - 1))
            histogram[bin]++
        }

        // Calculate entropy
        var entropy = 0.0
        histogram.forEach { count ->
            if (count > 0) {
                val p = count.toDouble() / data.size
                entropy -= p * ln(p)
            }
        }
        return entropy
    }

    private fun arCoefficients(data: List<Double>, order: Int): List<Double> {
        // Simplified AR coefficient calculation using Yule-Walker equations
        if (data.size < order + 1) return List(order) { 0.0 }

        // Calculate autocorrelation (need order + 1 values for lags 0 to order)
        val autocorr = mutableListOf<Double>()
        val mean = data.average()
        val centered = data.map { it - mean }

        for (lag in 0..order) {
            var sum = 0.0
            for (i in 0 until data.size - lag) {
                sum += centered[i] * centered[i + lag]
            }
            autocorr.add(sum / data.size)
        }

        // Solve Yule-Walker equations (simplified - using Levinson-Durbin recursion)
        val coeffs = mutableListOf<Double>()
        if (autocorr[0] == 0.0) return List(order) { 0.0 }

        var prev = listOf(autocorr[1] / autocorr[0])
        coeffs.addAll(prev)

        for (k in 1 until order) {
            var num = autocorr[k + 1]
            for (j in 0 until k) {
                num -= prev[j] * autocorr[k - j]
            }
            val denom = 1.0 - prev.mapIndexed { i, v -> v * autocorr[i + 1] }.sum()

            if (denom == 0.0) {
                coeffs.add(0.0)
                continue
            }

            val ak = num / denom
            val newCoeffs = mutableListOf<Double>()
            for (i in 0 until k) {
                newCoeffs.add(prev[i] - ak * prev[k - 1 - i])
            }
            newCoeffs.add(ak)
            prev = newCoeffs
            if (coeffs.size < order) {
                coeffs.add(ak)
            }
        }

        return coeffs.take(order)
    }

    private fun correlation(x: List<Double>, y: List<Double>): Double {
        if (x.size != y.size || x.isEmpty()) return 0.0

        val meanX = x.average()
        val meanY = y.average()

        var numerator = 0.0
        var sumSqX = 0.0
        var sumSqY = 0.0

        for (i in x.indices) {
            val dx = x[i] - meanX
            val dy = y[i] - meanY
            numerator += dx * dy
            sumSqX += dx * dx
            sumSqY += dy * dy
        }

        val denominator = sqrt(sumSqX * sumSqY)
        return if (denominator == 0.0) 0.0 else numerator / denominator
    }

    private fun fft(data: List<Double>): List<Double> {
        // Simple FFT implementation (Cooley-Tukey algorithm)
        // For production, consider using a library like Apache Commons Math
        if (data.isEmpty()) return emptyList()

        val n = data.size
        // Pad to next power of 2 for FFT
        val paddedSize = (1 shl (32 - n.countLeadingZeroBits())).coerceAtLeast(2)
        val padded = data + List(paddedSize - n) { 0.0 }

        return fftRecursive(padded).take(n)
    }

    private fun fftRecursive(data: List<Double>): List<Double> {
        val n = data.size
        if (n <= 1) return data

        val even = fftRecursive(data.filterIndexed { i, _ -> i % 2 == 0 })
        val odd = fftRecursive(data.filterIndexed { i, _ -> i % 2 == 1 })

        val result = mutableListOf<Double>()
        for (k in 0 until n / 2) {
            val t = -2.0 * PI * k / n
            val re = cos(t)
            val im = sin(t)
            val oddK = odd.getOrElse(k) { 0.0 }
            val evenK = even.getOrElse(k) { 0.0 }
            result.add(evenK + re * oddK)
            result.add(evenK - re * oddK)
        }
        return result
    }

    private fun meanFreq(fftData: List<Double>): Double {
        if (fftData.isEmpty()) return 0.0
        val magnitudes = fftData.map { abs(it) }
        val totalEnergy = magnitudes.sum()
        if (totalEnergy == 0.0) return 0.0

        var weightedSum = 0.0
        magnitudes.forEachIndexed { index, mag -> weightedSum += index * mag }
        return weightedSum / totalEnergy
    }

    private fun skewness(data: List<Double>): Double {
        if (data.size < 3) return 0.0
        val mean = data.average()
        val std = stdDev(data)
        if (std == 0.0) return 0.0

        val n = data.size
        val sum =
                data
                        .map {
                            val normalized: Double = (it - mean) / std
                            normalized.pow(3.0)
                        }
                        .sum()
        return (n / ((n - 1.0) * (n - 2.0))) * sum
    }

    private fun kurtosis(data: List<Double>): Double {
        if (data.size < 4) return 0.0
        val mean = data.average()
        val std = stdDev(data)
        if (std == 0.0) return 0.0

        val n = data.size
        val sum =
                data
                        .map {
                            val normalized: Double = (it - mean) / std
                            normalized.pow(4.0)
                        }
                        .sum()
        return ((n * (n + 1.0)) / ((n - 1.0) * (n - 2.0) * (n - 3.0))) * sum -
                3.0 * (n - 1.0) * (n - 1.0) / ((n - 2.0) * (n - 3.0))
    }

    private fun extractBandsEnergy(
            prefix: String,
            fftX: List<Double>,
            fftY: List<Double>,
            fftZ: List<Double>,
            features: MutableMap<String, Double>
    ) {
        val absX = fftX.map { abs(it) }
        val absY = fftY.map { abs(it) }
        val absZ = fftZ.map { abs(it) }

        // Frequency bands: 1-8, 9-16, 17-24, 25-32, 33-40, 41-48, 49-56, 57-64
        // Then: 1-16, 17-32, 33-48, 49-64
        // Then: 1-24, 25-48
        val bands =
                listOf(
                        Pair(1, 8),
                        Pair(9, 16),
                        Pair(17, 24),
                        Pair(25, 32),
                        Pair(33, 40),
                        Pair(41, 48),
                        Pair(49, 56),
                        Pair(57, 64),
                        Pair(1, 16),
                        Pair(17, 32),
                        Pair(33, 48),
                        Pair(49, 64),
                        Pair(1, 24),
                        Pair(25, 48)
                )

        for (band in bands) {
            val (start, end) = band
            val bandEnergyX =
                    absX.subList((start - 1).coerceAtMost(absX.size), end.coerceAtMost(absX.size))
                            .sumOf { it * it }
            val bandEnergyY =
                    absY.subList((start - 1).coerceAtMost(absY.size), end.coerceAtMost(absY.size))
                            .sumOf { it * it }
            val bandEnergyZ =
                    absZ.subList((start - 1).coerceAtMost(absZ.size), end.coerceAtMost(absZ.size))
                            .sumOf { it * it }

            features["${prefix}-bandsEnergy()-${start},${end}-X"] = bandEnergyX
            features["${prefix}-bandsEnergy()-${start},${end}-Y"] = bandEnergyY
            features["${prefix}-bandsEnergy()-${start},${end}-Z"] = bandEnergyZ
        }
    }

    private fun angle(
            v1: Triple<Double, Double, Double>,
            v2: Triple<Double, Double, Double>
    ): Double {
        val dot = v1.first * v2.first + v1.second * v2.second + v1.third * v2.third
        val mag1 = sqrt(v1.first * v1.first + v1.second * v1.second + v1.third * v1.third)
        val mag2 = sqrt(v2.first * v2.first + v2.second * v2.second + v2.third * v2.third)

        if (mag1 == 0.0 || mag2 == 0.0) return 0.0
        val cosAngle = (dot / (mag1 * mag2)).coerceIn(-1.0, 1.0)
        return acos(cosAngle)
    }

    private fun generateEmptyFeatures(): Map<String, Double> {
        // Return empty map - features will be calculated when data is available
        return emptyMap()
    }
}
