import Foundation
import os.log

/// Monitors SDK performance metrics (CPU, memory usage).
/// Used for validating performance requirements (<2% CPU, <500KB memory).
class PerformanceMonitor {

    private var metrics: [String: PerformanceMetrics] = [:]
    private let startTime = Date()
    private let queue = DispatchQueue(label: "ai.synheart.behavior.performance", attributes: .concurrent)

    func recordSnapshot(label: String = "default") {
        queue.async(flags: .barrier) {
            let now = Date()
            let memoryUsage = self.getMemoryUsage()
            let cpuUsage = self.getCPUUsage()

            let metric = PerformanceMetrics(
                timestamp: now.timeIntervalSince1970,
                label: label,
                memoryUsageKB: memoryUsage,
                cpuUsagePercent: cpuUsage,
                uptimeMs: Int64(now.timeIntervalSince(self.startTime) * 1000)
            )

            self.metrics[label] = metric
        }
    }

    func getMetrics() -> [String: PerformanceMetrics] {
        return queue.sync {
            return metrics
        }
    }

    func getSummary() -> PerformanceSummary {
        return queue.sync {
            let allMetrics = Array(metrics.values)

            guard !allMetrics.isEmpty else {
                return PerformanceSummary(
                    sampleCount: 0,
                    averageMemoryKB: 0.0,
                    maxMemoryKB: 0.0,
                    averageCpuPercent: 0.0,
                    maxCpuPercent: 0.0
                )
            }

            let memoryValues = allMetrics.map { $0.memoryUsageKB }
            let cpuValues = allMetrics.map { $0.cpuUsagePercent }

            return PerformanceSummary(
                sampleCount: allMetrics.count,
                averageMemoryKB: memoryValues.reduce(0.0, +) / Double(memoryValues.count),
                maxMemoryKB: memoryValues.max() ?? 0.0,
                averageCpuPercent: cpuValues.reduce(0.0, +) / Double(cpuValues.count),
                maxCpuPercent: cpuValues.max() ?? 0.0
            )
        }
    }

    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        if kerr == KERN_SUCCESS {
            // Return memory in KB
            return Double(info.resident_size) / 1024.0
        } else {
            return 0.0
        }
    }

    private func getCPUUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount = mach_msg_type_number_t(0)
        let threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)

        let kerr = task_threads(mach_task_self_, &threadList, &threadCount)

        guard kerr == KERN_SUCCESS, let threads = threadList else {
            return 0.0
        }

        var totalCPU: Double = 0.0

        for index in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = threadInfoCount

            let infoKerr = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    thread_info(
                        threads[index],
                        thread_flavor_t(THREAD_BASIC_INFO),
                        $0,
                        &threadInfoCount
                    )
                }
            }

            guard infoKerr == KERN_SUCCESS else {
                continue
            }

            if threadInfo.flags != TH_FLAGS_IDLE {
                let cpuUsage = Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE)
                totalCPU += cpuUsage * 100.0
            }
        }

        vm_deallocate(
            mach_task_self_,
            vm_address_t(bitPattern: threads),
            vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride)
        )

        return totalCPU
    }

    func printReport() -> String {
        let summary = getSummary()

        var report = "=== Synheart Behavior SDK Performance Report ===\n"
        report += "Samples: \(summary.sampleCount)\n"
        report += "Memory Usage:\n"
        report += "  Average: \(String(format: "%.2f", summary.averageMemoryKB)) KB\n"
        report += "  Max: \(String(format: "%.2f", summary.maxMemoryKB)) KB\n"
        report += "  Target: <500 KB\n"
        report += "  Status: \(summary.maxMemoryKB < 500 ? "✓ PASS" : "✗ FAIL")\n"
        report += "\n"
        report += "CPU Usage:\n"
        report += "  Average: \(String(format: "%.2f", summary.averageCpuPercent))%\n"
        report += "  Max: \(String(format: "%.2f", summary.maxCpuPercent))%\n"
        report += "  Target: <2%\n"
        report += "  Status: \(summary.maxCpuPercent < 2.0 ? "✓ PASS" : "✗ FAIL")\n"
        report += "\n"
        report += "Overall Performance: \(summary.passesRequirements() ? "✓ PASS" : "⚠ REVIEW NEEDED")\n"

        return report
    }
}

struct PerformanceMetrics {
    let timestamp: Double
    let label: String
    let memoryUsageKB: Double
    let cpuUsagePercent: Double
    let uptimeMs: Int64
}

struct PerformanceSummary {
    let sampleCount: Int
    let averageMemoryKB: Double
    let maxMemoryKB: Double
    let averageCpuPercent: Double
    let maxCpuPercent: Double

    func passesRequirements() -> Bool {
        return maxMemoryKB < 500 && maxCpuPercent < 2.0
    }
}
