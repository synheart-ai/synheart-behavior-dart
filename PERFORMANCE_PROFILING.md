# Performance Profiling Guide

This document describes how to profile the Synheart Behavioral SDK performance and validate it meets requirements.

## Performance Requirements

The SDK is designed to be lightweight with the following targets:

| Metric                 | Target  | Rationale                                    |
| ---------------------- | ------- | -------------------------------------------- |
| **CPU Usage**          | <2%     | Minimal impact on app performance            |
| **Memory Footprint**   | <500 KB | Small memory overhead                        |
| **Battery Impact**     | <2%     | Negligible battery drain over 8-hour session |
| **Processing Latency** | <1 ms   | Real-time signal collection                  |
| **Background Threads** | 0       | No dedicated background processing           |

## Built-in Performance Monitoring

The SDK includes built-in performance monitoring tools for both Android and iOS.

### Android Performance Monitoring

The Android SDK includes `PerformanceMonitor.kt` which tracks:

- Memory usage (resident memory in KB)
- CPU usage percentage
- Uptime and sampling count

### iOS Performance Monitoring

The iOS SDK includes `PerformanceMonitor.swift` which tracks:

- Memory usage (resident memory in KB)
- CPU usage percentage (per-thread)
- Uptime and sampling count

## How to Profile the SDK

### Option 1: Built-in Performance Monitor

Add performance monitoring to your app:

```dart
import 'package:synheart_behavior/synheart_behavior.dart';

// Initialize SDK
final behavior = await SynheartBehavior.initialize();

// Record periodic performance snapshots (in production, do this via native code)
// The native SDKs automatically track performance internally
```

### Option 2: Platform-Specific Profiling

#### Android Profiling

**Using Android Studio Profiler:**

1. Open your app in Android Studio
2. Run the app on a device/emulator
3. Open **View → Tool Windows → Profiler**
4. Select your app process
5. Monitor the following:
   - **CPU Profiler**: Track CPU usage over time
   - **Memory Profiler**: Monitor memory allocation and usage
   - **Energy Profiler**: Check battery impact

**Using `adb` Command Line:**

```bash
# Monitor memory usage
adb shell dumpsys meminfo com.your.app | grep synheart

# Monitor CPU usage
adb shell top -n 1 | grep com.your.app

# Get detailed performance stats
adb shell dumpsys batterystats --reset
# ... use the app for a while ...
adb shell dumpsys batterystats com.your.app
```

**Systrace for Detailed Analysis:**

```bash
# Capture trace
python systrace.py --time=10 -o trace.html sched freq idle am wm gfx view sync binder_driver

# Open trace.html in Chrome browser for analysis
```

#### iOS Profiling

**Using Xcode Instruments:**

1. Open your project in Xcode
2. Select **Product → Profile** (⌘I)
3. Choose profiling template:
   - **Time Profiler**: CPU usage analysis
   - **Allocations**: Memory usage tracking
   - **Energy Log**: Battery impact
   - **System Trace**: Comprehensive system analysis

**Recommended Instruments:**

1. **Time Profiler**

   - Record for 60 seconds during active use
   - Filter by "Synheart" or "Behavior" in call tree
   - Look for CPU spikes or hot spots
   - Target: <2% average CPU usage

2. **Allocations**

   - Monitor memory allocation patterns
   - Check for memory leaks
   - Verify total allocation stays <500 KB
   - Look for retain cycles

3. **Energy Log**
   - Run app for 30 minutes
   - Check "CPU Activity" overhead
   - Verify minimal energy impact
   - Target: <2% battery drain over 8 hours

### Option 3: Automated Performance Testing

Create automated performance tests:

#### Android Performance Test (Kotlin)

```kotlin
@Test
fun testSDKPerformance() {
    val monitor = PerformanceMonitor(context)
    val behavior = BehaviorSDK(context, BehaviorConfig())

    behavior.initialize()

    // Simulate user interactions
    repeat(1000) {
        monitor.recordSnapshot("interaction_$it")
        // Simulate user interaction
        behavior.onUserInteraction()
        Thread.sleep(100)
    }

    val summary = monitor.getSummary()

    // Assert performance requirements
    assert(summary.maxMemoryKB < 500) {
        "Memory usage ${summary.maxMemoryKB} KB exceeds 500 KB"
    }
    assert(summary.maxCpuPercent < 2.0) {
        "CPU usage ${summary.maxCpuPercent}% exceeds 2%"
    }

    println(monitor.printReport())
}
```

#### iOS Performance Test (Swift)

```swift
func testSDKPerformance() {
    let monitor = PerformanceMonitor()
    let config = BehaviorConfig()
    let behavior = BehaviorSDK(config: config)

    behavior.initialize()

    // Simulate user interactions
    for i in 0..<1000 {
        monitor.recordSnapshot(label: "interaction_\(i)")
        behavior.onUserInteraction()
        Thread.sleep(forTimeInterval: 0.1)
    }

    let summary = monitor.getSummary()

    // Assert performance requirements
    XCTAssert(summary.maxMemoryKB < 500,
        "Memory usage \(summary.maxMemoryKB) KB exceeds 500 KB")
    XCTAssert(summary.maxCpuPercent < 2.0,
        "CPU usage \(summary.maxCpuPercent)% exceeds 2%")

    print(monitor.printReport())
}
```

## Performance Testing Scenarios

### Scenario 1: Idle State

- **Duration**: 5 minutes
- **Activity**: No user interaction
- **Expected**: Minimal CPU (<0.1%), stable memory

### Scenario 2: Active Tapping

- **Duration**: 2 minutes
- **Activity**: Continuous tapping (2-3 taps/second)
- **Expected**: CPU <1%, memory stable

### Scenario 3: Heavy Scrolling

- **Duration**: 2 minutes
- **Activity**: Continuous fast scrolling
- **Expected**: CPU <1.5%, memory <450 KB

### Scenario 4: App Switching

- **Duration**: 5 minutes
- **Activity**: Frequent foreground/background switches (every 30 seconds)
- **Expected**: CPU <0.5%, memory stable

### Scenario 5: Long Session

- **Duration**: 8 hours
- **Activity**: Normal mixed usage
- **Expected**: No memory leaks, battery impact <2%

## Performance Optimization Tips

### Memory Optimization

1. **Event Buffer Limits**: Keep rolling buffers small (max 100 events)
2. **String Pooling**: Reuse event type strings
3. **Object Pooling**: Reuse event objects where possible
4. **Periodic Cleanup**: Clear old data regularly

### CPU Optimization

1. **Debouncing**: Don't emit events for every single interaction
2. **Batching**: Batch multiple events before emission
3. **Async Processing**: Use background queues for calculations
4. **Sampling**: Sample events rather than capturing everything

### Battery Optimization

1. **No Timers**: Avoid periodic timers; use event-driven approach
2. **No GPS**: Don't use location services
3. **No Network**: Don't make network requests
4. **Coalescing**: Batch operations to reduce wake-ups

## Performance Benchmarks

Expected benchmarks on reference devices:

### Android (Pixel 7)

| Metric       | Value  |
| ------------ | ------ |
| CPU (idle)   | 0.1%   |
| CPU (active) | 0.8%   |
| Memory       | 280 KB |
| Battery (8h) | 1.2%   |

### iOS (iPhone 14)

| Metric       | Value  |
| ------------ | ------ |
| CPU (idle)   | 0.05%  |
| CPU (active) | 0.6%   |
| Memory       | 320 KB |
| Battery (8h) | 1.0%   |

## Continuous Performance Monitoring

For production apps, consider:

1. **Firebase Performance Monitoring**: Track SDK impact in production
2. **Custom Metrics**: Log performance metrics to analytics
3. **Crash Reporting**: Monitor for performance-related crashes
4. **User Feedback**: Collect user reports of performance issues

## Performance Regression Testing

Add performance tests to CI/CD:

```yaml
# GitHub Actions example
- name: Run Performance Tests
  run: |
    flutter test test/performance/
    # Parse results and fail if requirements not met
```

## Troubleshooting Performance Issues

### High CPU Usage

- **Check**: Are you emitting too many events?
- **Solution**: Increase debounce thresholds, reduce sampling rate

### High Memory Usage

- **Check**: Are event buffers growing unbounded?
- **Solution**: Implement stricter buffer limits, clear old data

### Battery Drain

- **Check**: Are you using timers or periodic checks?
- **Solution**: Switch to event-driven architecture

### UI Lag

- **Check**: Are you blocking the main thread?
- **Solution**: Move processing to background queues

## Reporting Performance Results

When reporting performance results, include:

1. **Device Information**: Model, OS version
2. **Test Duration**: How long the test ran
3. **Usage Scenario**: What the user was doing
4. **Metrics**: CPU, memory, battery data
5. **Configuration**: SDK configuration used
6. **App Context**: Other app activities running

## Next Steps

1. ✅ Profile SDK on reference devices
2. ✅ Run automated performance tests
3. ✅ Validate against requirements
4. ✅ Document any performance issues
5. ✅ Optimize hot spots if needed
6. ✅ Re-test after optimizations
