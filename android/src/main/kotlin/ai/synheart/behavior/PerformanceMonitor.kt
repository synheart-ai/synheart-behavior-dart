package ai.synheart.behavior

import android.app.ActivityManager
import android.content.Context
import android.os.Debug
import android.os.Process
import java.util.concurrent.ConcurrentHashMap

/**
 * Monitors SDK performance metrics (CPU, memory usage).
 * Used for validating performance requirements (<2% CPU, <500KB memory).
 */
class PerformanceMonitor(private val context: Context) {

    private val metrics = ConcurrentHashMap<String, PerformanceMetrics>()
    private val startTime = System.currentTimeMillis()
    private var lastCpuCheckTime = 0L
    private var lastCpuTime = 0L

    fun recordSnapshot(label: String = "default") {
        val now = System.currentTimeMillis()
        val memoryInfo = getMemoryUsage()
        val cpuUsage = getCpuUsage()

        val metric = PerformanceMetrics(
            timestamp = now,
            label = label,
            memoryUsageKB = memoryInfo,
            cpuUsagePercent = cpuUsage,
            uptimeMs = now - startTime
        )

        metrics[label] = metric
    }

    fun getMetrics(): Map<String, PerformanceMetrics> {
        return metrics.toMap()
    }

    fun getSummary(): PerformanceSummary {
        val allMetrics = metrics.values.toList()

        if (allMetrics.isEmpty()) {
            return PerformanceSummary(
                sampleCount = 0,
                averageMemoryKB = 0.0,
                maxMemoryKB = 0.0,
                averageCpuPercent = 0.0,
                maxCpuPercent = 0.0
            )
        }

        return PerformanceSummary(
            sampleCount = allMetrics.size,
            averageMemoryKB = allMetrics.map { it.memoryUsageKB }.average(),
            maxMemoryKB = allMetrics.maxOf { it.memoryUsageKB }.toDouble(),
            averageCpuPercent = allMetrics.map { it.cpuUsagePercent }.average(),
            maxCpuPercent = allMetrics.maxOf { it.cpuUsagePercent }
        )
    }

    private fun getMemoryUsage(): Long {
        val memoryInfo = Debug.MemoryInfo()
        Debug.getMemoryInfo(memoryInfo)

        // Total private memory in KB
        return memoryInfo.totalPrivateDirty.toLong()
    }

    private fun getCpuUsage(): Double {
        val pid = Process.myPid()
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager

        val processInfo = activityManager.runningAppProcesses?.find { it.pid == pid }

        if (processInfo != null) {
            val now = System.currentTimeMillis()

            // Get process CPU time
            val cpuTime = Process.getElapsedCpuTime()

            if (lastCpuCheckTime > 0) {
                val timeDelta = now - lastCpuCheckTime
                val cpuDelta = cpuTime - lastCpuTime

                if (timeDelta > 0) {
                    // Calculate CPU usage percentage
                    val usage = (cpuDelta.toDouble() / timeDelta) * 100.0
                    lastCpuCheckTime = now
                    lastCpuTime = cpuTime
                    return usage.coerceIn(0.0, 100.0)
                }
            }

            lastCpuCheckTime = now
            lastCpuTime = cpuTime
        }

        return 0.0
    }

    fun printReport(): String {
        val summary = getSummary()

        return buildString {
            appendLine("=== Synheart Behavior SDK Performance Report ===")
            appendLine("Samples: ${summary.sampleCount}")
            appendLine("Memory Usage:")
            appendLine("  Average: ${summary.averageMemoryKB.format()} KB")
            appendLine("  Max: ${summary.maxMemoryKB.format()} KB")
            appendLine("  Target: <500 KB")
            appendLine("  Status: ${if (summary.maxMemoryKB < 500) "✓ PASS" else "✗ FAIL"}")
            appendLine()
            appendLine("CPU Usage:")
            appendLine("  Average: ${summary.averageCpuPercent.format()}%")
            appendLine("  Max: ${summary.maxCpuPercent.format()}%")
            appendLine("  Target: <2%")
            appendLine("  Status: ${if (summary.maxCpuPercent < 2.0) "✓ PASS" else "✗ FAIL"}")
            appendLine()
            appendLine("Overall Performance: ${if (summary.passesRequirements()) "✓ PASS" else "⚠ REVIEW NEEDED"}")
        }
    }

    private fun Double.format(): String = "%.2f".format(this)
}

data class PerformanceMetrics(
    val timestamp: Long,
    val label: String,
    val memoryUsageKB: Long,
    val cpuUsagePercent: Double,
    val uptimeMs: Long
)

data class PerformanceSummary(
    val sampleCount: Int,
    val averageMemoryKB: Double,
    val maxMemoryKB: Double,
    val averageCpuPercent: Double,
    val maxCpuPercent: Double
) {
    fun passesRequirements(): Boolean {
        return maxMemoryKB < 500 && maxCpuPercent < 2.0
    }
}
