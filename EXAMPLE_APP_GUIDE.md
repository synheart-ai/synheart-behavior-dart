# Example App Guide

## Running and Testing Real Behavioral Signal Collection

This guide shows you how to run the example app and verify that behavioral signals are being collected in real-time.

---

## Prerequisites

### Software Requirements

- Flutter SDK (>=3.10.0)
- Dart SDK (>=3.0.0)
- For Android:
  - Android Studio or VS Code with Flutter plugin
  - Android SDK (API 21+)
  - Android emulator or physical device
- For iOS:
  - macOS with Xcode (14.0+)
  - iOS Simulator or physical iOS device (iOS 12.0+)
  - CocoaPods

### Installation Check

```bash
# Verify Flutter installation
flutter doctor

# Expected output should show:
# [✓] Flutter
# [✓] Android toolchain (or iOS toolchain on macOS)
# [✓] VS Code or Android Studio
```

---

## Running the Example App

### Option 1: Run on Android

#### Step 1: Navigate to Example Directory

```bash
cd example
```

#### Step 2: Get Dependencies

```bash
flutter pub get
```

#### Step 3: Run on Android Device/Emulator

```bash
# List available devices
flutter devices

# Run on specific device
flutter run -d <device-id>

# Or simply run on the first available device
flutter run
```

#### Step 4: Observe Logs (Optional)

```bash
# In a separate terminal, monitor native logs
adb logcat | grep "Synheart\|Behavior"
```

---

### Option 2: Run on iOS

#### Step 1: Navigate to Example Directory

```bash
cd example
```

#### Step 2: Get Dependencies

```bash
flutter pub get
```

#### Step 3: Install iOS Pods (First time only)

```bash
cd ios
pod install
cd ..
```

#### Step 4: Run on iOS Simulator/Device

```bash
# List available devices
flutter devices

# Run on iOS
flutter run -d <ios-device-id>
```

#### Step 5: Observe Logs (Optional)

```bash
# Monitor iOS console logs
xcrun simctl spawn booted log stream --predicate 'subsystem contains "ai.synheart"' --level debug
```

---

## Using the Example App

### App Interface

When the app launches, you'll see:

1. **SDK Status Card**

   - Shows if SDK is initialized
   - Displays current active session ID

2. **Control Buttons**

   - **Start Session**: Begin a new behavioral tracking session
   - **End Session**: Stop current session and view summary
   - **Refresh Stats**: Get current rolling statistics

3. **Current Stats Card**

   - Shows real-time behavioral metrics:
     - Scroll Velocity
     - Tap Rate
     - App Switches per minute
     - Stability Index

4. **Recent Events List**

   - Displays the last 50 behavioral events
   - Updates in real-time as you interact

5. **Test Area**
   - Scrollable content for testing scroll dynamics
   - Buttons and interactive elements for testing tap and swipe gestures

---

## Testing Behavioral Signal Collection

**Important**: The SDK emits **real-time events** (scroll, tap, swipe, notification, call) via the `onEvent` stream. Aggregated statistics (scroll velocity averages, tap rates, etc.) are computed from these events and available via `getCurrentStats()`. The tests below show both individual events and aggregated statistics.

### Test 1: Tap Gesture Signals

**Objective**: Verify tap gesture detection and timing

**Steps**:

1. Click **"Start Session"**
2. Tap various buttons and UI elements in the app
3. Try both quick taps and long-press gestures
4. Observe the **Recent Events** list

**Expected Events**:

- `tap` events - Each tap generates an event with duration and long-press detection

**Expected Event Structure**:

```json
{
  "event_type": "tap",
  "metrics": {
    "tap_duration_ms": 120,
    "long_press": false
  }
}
```

**Note**: Tap rate is computed from tap events and available via `getCurrentStats()`.

**✅ Privacy Check**: Event contains NO coordinates or content, only timing!

---

### Test 2: Scroll Dynamics Signals

**Objective**: Verify scroll velocity, acceleration, and direction tracking

**Steps**:

1. Ensure session is active
2. Scroll the main view **slowly**
3. Then scroll **quickly**
4. Try **jerky** scrolling (start-stop-start)
5. Observe the **Recent Events** list

**Expected Events**:

- `scroll` events - Emitted when scrolling occurs, with velocity, acceleration, direction, and direction reversal metrics

**Expected Event Structure**:

```json
{
  "event_type": "scroll",
  "metrics": {
    "velocity": 150.5,
    "acceleration": 25.3,
    "direction": "down",
    "direction_reversal": false
  }
}
```

**Note**: Scroll jitter and aggregated scroll statistics are computed from scroll events and available via `getCurrentStats()`.

**✅ Privacy Check**: No screen coordinates, only velocity magnitude and direction!

---

### Test 3: Tap and Gesture Signals

**Objective**: Verify tap and swipe gesture detection

**Steps**:

1. Tap various buttons **quickly** (multiple times)
2. **Long-press** on UI elements
3. **Swipe** in the scrollable area
4. Observe events

**Expected Events**:

- `tap` events - Each tap generates an event with duration and long-press detection
- `swipe` events - Swipe gestures generate events with direction, distance, velocity, and acceleration

**Expected Tap Event Structure**:

```json
{
  "event_type": "tap",
  "metrics": {
    "tap_duration_ms": 150,
    "long_press": false
  }
}
```

**Expected Swipe Event Structure**:

```json
{
  "event_type": "swipe",
  "metrics": {
    "direction": "left",
    "distance_px": 250.5,
    "duration_ms": 300,
    "velocity": 835.0,
    "acceleration": 120.5
  }
}
```

**Note**: Tap rate is computed from tap events and available via `getCurrentStats()`.

**✅ Privacy Check**: No tap/swipe coordinates, only timing and movement metrics!

---

### Test 4: App Lifecycle Signals

**Objective**: Verify foreground/background detection

**Steps**:

1. Ensure session is active
2. Press device **Home button** (or swipe up)
3. Wait 5 seconds
4. Return to the app
5. Check events and stats

**Note**: App lifecycle events are tracked internally by the SDK. App switch counts and foreground duration are available via `getCurrentStats()`, not as individual events.

**Expected Stats** (from `getCurrentStats()`):

```json
{
  "app_switches_per_minute": 2,
  "foreground_duration": 5.2
}
```

**Note**: The SDK tracks app switches and foreground duration as part of attention signals, but these are aggregated into statistics rather than emitted as individual events.

---

### Test 5: Idle Gap Detection

**Objective**: Verify idle state detection

**Steps**:

1. Start a session
2. **Stop interacting** with the device completely
3. Wait for:
   - 2 seconds (micro idle)
   - 5 seconds (mid idle)
   - 12 seconds (task-drop idle)
4. Check stats using `getCurrentStats()`

**Note**: Idle gaps are tracked internally and available via `getCurrentStats()`, not as individual events.

**Expected Stats** (from `getCurrentStats()`):

```json
{
  "idle_gap_seconds": 12.5
}
```

**Note**: The SDK tracks idle periods as part of attention signals. The idle duration is available in the current stats, but idle type classification is computed from the duration value.

---

### Test 6: Session Stability Metrics

**Objective**: Verify stability and fragmentation calculation

**Steps**:

1. Start a session
2. Use the app **steadily** for 2 minutes
3. Switch apps 2-3 times
4. Click **"Refresh Stats"**
5. View stability index

**Expected Stats**:

```json
{
  "stability_index": 0.85, // 0.0-1.0, higher = more stable
  "fragmentation_index": 0.15 // 0.0-1.0, higher = more fragmented
}
```

**Interpretation**:

- **High stability** (>0.8): User is focused, few interruptions
- **Low stability** (<0.5): User is distracted, many app switches

---

### Test 7: Session Summary

**Objective**: Verify session summary generation

**Steps**:

1. Start a session
2. Interact with the app for 1-2 minutes:
   - Scroll the view
   - Tap buttons
   - Perform swipe gestures
   - Switch apps once or twice
3. Click **"End Session"**
4. View the summary dialog

**Expected Summary**:

```
Session Summary
─────────────────────
Duration: 120000ms (2 minutes)
Event Count: 87
Average Scroll Velocity: 145.2 px/sec
Tap Count: 45
App Switch Count: 2
Stability Index: 0.82
Fragmentation Index: 0.18
```

---

## Verifying Data Privacy

### What You Should SEE in Events

✅ **Event Types** (from `onEvent` stream):

- `scroll` - with metrics: `velocity`, `acceleration`, `direction`, `direction_reversal`
- `tap` - with metrics: `tap_duration_ms`, `long_press`
- `swipe` - with metrics: `direction`, `distance_px`, `duration_ms`, `velocity`, `acceleration`
- `notification` - with metrics: `action` (requires permission)
- `call` - with metrics: `action` (requires permission)

✅ **Aggregated Statistics** (from `getCurrentStats()`):

- `scroll_velocity`: 150.0 (pixels per second)
- `scroll_acceleration`: 20.3 (pixels per second squared)
- `scroll_jitter`: 5.1
- `tap_rate`: 1.5 (taps per second)
- `app_switches_per_minute`: 3
- `foreground_duration`: 5.2 (seconds)
- `idle_gap_seconds`: 2.1
- `stability_index`: 0.85
- `fragmentation_index`: 0.15

### What You Should NOT SEE

❌ **Text Content**:

- No character data
- No string values
- No field names

❌ **Screen Coordinates**:

- No X/Y positions
- No pixel locations
- No UI element IDs

❌ **Identifiers**:

- No device IDs
- No user IDs
- No advertising IDs

❌ **System Information**:

- No other app names
- No package identifiers
- No file paths

**Privacy Verification**: If you see ANY of the above ❌ items, please file a bug report!

---

## Performance Verification

### Monitor App Performance

While using the example app:

#### Android

```bash
# CPU usage
adb shell top -n 1 | grep com.example.synheart_behavior_example

# Memory usage
adb shell dumpsys meminfo com.example.synheart_behavior_example | grep -A 10 "App Summary"

# Expected:
# CPU: <2%
# Memory: <500 KB for SDK (check "Private" column)
```

#### iOS

1. Open Xcode
2. **Window** → **Devices and Simulators**
3. Select your device
4. Click **Open Console**
5. Monitor for memory/CPU warnings

**Expected Performance**:

- **CPU Usage**: <2% average, <5% peak
- **Memory**: <500 KB resident memory
- **No lag** in UI interactions

---

## Troubleshooting

### Problem: No Events Appearing

**Possible Causes**:

1. Session not started
2. Native SDK initialization failed
3. Platform channel error

**Solution**:

```bash
# Check logs
flutter logs

# Look for:
# - "initialize" method call success
# - "startSession" confirmation
# - No platform exceptions
```

### Problem: Build Errors

**Android Build Error**:

```bash
# Clear build cache
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
flutter run
```

**iOS Build Error**:

```bash
# Re-install pods
cd example/ios
pod deintegrate
pod install
cd ../..
flutter clean
flutter pub get
flutter run
```

### Problem: No Native Code Execution

**Check Platform Integration**:

```bash
# Verify native files exist
ls -la android/src/main/java/ai/synheart/behavior/
ls -la ios/Classes/

# Should see:
# - BehaviorSDK.kt / BehaviorSDK.swift
# - InputSignalCollector files
# - GestureCollector files
# etc.
```

---

## Expected Output Examples

### Console Log (Successful Run)

```
🎯 Synheart Behavior SDK Initialized
✓ Native SDK: Ready
✓ Platform Channel: Connected
✓ Config: inputSignals=true, attentionSignals=true

📝 Session Started: SESS-1705234567890

🔔 Event: tap
   Metrics: {tap_duration_ms: 120, long_press: false}

🔔 Event: scroll
   Metrics: {velocity: 150.5, acceleration: 25.3, direction: down, direction_reversal: false}

🔔 Event: swipe
   Metrics: {direction: left, distance_px: 250.5, duration_ms: 300, velocity: 835.0, acceleration: 120.5}

📊 Session Ended: SESS-1705234567890
   Duration: 120000ms
   Events: 87
   Stability: 0.85
```

### Event Stream (Real-time)

```json
[
  {
    "event": {
      "event_id": "evt_1705234567890",
      "session_id": "SESS-1705234567890",
      "timestamp": "2025-01-15T10:15:23.456Z",
      "event_type": "tap",
      "metrics": {
        "tap_duration_ms": 120,
        "long_press": false
      }
    }
  },
  {
    "event": {
      "event_id": "evt_1705234568100",
      "session_id": "SESS-1705234567890",
      "timestamp": "2025-01-15T10:15:25.100Z",
      "event_type": "scroll",
      "metrics": {
        "velocity": 150.5,
        "acceleration": 25.3,
        "direction": "down",
        "direction_reversal": false
      }
    }
  },
  {
    "event": {
      "event_id": "evt_1705234570000",
      "session_id": "SESS-1705234567890",
      "timestamp": "2025-01-15T10:15:40.000Z",
      "event_type": "swipe",
      "metrics": {
        "direction": "left",
        "distance_px": 250.5,
        "duration_ms": 300,
        "velocity": 835.0,
        "acceleration": 120.5
      }
    }
  }
]
```

---

## Next Steps

After successfully running the example app:

1. ✅ **Verify All Signal Types**: Ensure all event types are being collected
2. ✅ **Privacy Check**: Confirm no sensitive data in events
3. ✅ **Performance Check**: Monitor CPU/memory usage
4. ✅ **Integration**: Add SDK to your own app
5. ✅ **Customization**: Configure signal collection for your needs

---

## Integration into Your App

Once you've verified the example app works:

```dart
// In your app's main.dart
import 'package:synheart_behavior/synheart_behavior.dart';

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  SynheartBehavior? _behavior;

  @override
  void initState() {
    super.initState();
    _initializeSDK();
  }

  Future<void> _initializeSDK() async {
    _behavior = await SynheartBehavior.initialize(
      config: BehaviorConfig(
        enableInputSignals: true,
        enableAttentionSignals: true,
        enableMotionLite: false,
      ),
    );

    // Start a session
    await _behavior!.startSession();

    // Listen to events
    _behavior!.onEvent.listen((event) {
      print('Behavioral Event: ${event.eventType}');
      print('Metrics: ${event.metrics}');
      // Send to your analytics backend
    });
  }

  @override
  void dispose() {
    _behavior?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // IMPORTANT: Wrap your app with gesture detector to track Flutter gestures
    return _behavior!.wrapWithGestureDetector(
      MaterialApp(
        // your app content
        home: Scaffold(
          appBar: AppBar(title: const Text('My App')),
          body: const Center(child: Text('Your app content')),
        ),
      ),
    );
  }
}
```

---

## Support

If you encounter issues:

1. Check the [README.md](../README.md) for basic setup and API reference
2. Check [PRIVACY_AUDIT.md](../PRIVACY_AUDIT.md) for privacy questions
3. See [PERFORMANCE_PROFILING.md](../PERFORMANCE_PROFILING.md) for performance issues
4. Review [PERMISSIONS_DATA_MATRIX.md](../PERMISSIONS_DATA_MATRIX.md) for permission requirements
5. File an issue on GitHub

**Happy Testing! 🎉**
