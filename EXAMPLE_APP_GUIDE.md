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
     - Typing Cadence
     - Scroll Velocity
     - App Switches per minute
     - Stability Index

4. **Recent Events List**
   - Displays the last 50 behavioral events
   - Updates in real-time as you interact

5. **Test Area**
   - Interactive text field for testing keystroke collection
   - Scrollable content for testing scroll dynamics

---

## Testing Behavioral Signal Collection

### Test 1: Keystroke Timing Signals

**Objective**: Verify keystroke timing collection (NO text content!)

**Steps**:
1. Click **"Start Session"**
2. Type in the text field in the **Test Area**
3. Type at varying speeds (fast, slow, with pauses)
4. Observe the **Recent Events** list

**Expected Events**:
- `typingCadence` - Shows keys per second
- `typingBurst` - Shows burst length when typing quickly

**Expected Payload**:
```json
{
  "cadence": 2.5,
  "inter_key_latency": 110.5,
  "keys_in_window": 15
}
```

**✅ Privacy Check**: Event contains NO text content, only timing!

---

### Test 2: Scroll Dynamics Signals

**Objective**: Verify scroll velocity, acceleration, and jitter tracking

**Steps**:
1. Ensure session is active
2. Scroll the main view **slowly**
3. Then scroll **quickly**
4. Try **jerky** scrolling (start-stop-start)
5. Observe the **Recent Events** list

**Expected Events**:
- `scrollVelocity` - Appears during scrolling
- `scrollAcceleration` - Shows velocity changes
- `scrollJitter` - Appears during uneven scrolling
- `scrollStop` - Emitted when scrolling stops

**Expected Payload**:
```json
{
  "velocity": 150.5,
  "unit": "pixels_per_second"
}
```

**✅ Privacy Check**: No screen coordinates, only velocity magnitude!

---

### Test 3: Tap and Gesture Signals

**Objective**: Verify tap rate and gesture detection

**Steps**:
1. Tap various buttons **quickly** (multiple times)
2. **Long-press** on UI elements
3. **Drag/swipe** in the scrollable area
4. Observe events

**Expected Events**:
- `tapRate` - Shows taps per second
- `longPressRate` - Counts long presses
- `dragVelocity` - Shows drag speed

**Expected Payload**:
```json
{
  "tap_rate": 1.5,
  "taps_in_window": 15,
  "window_seconds": 10
}
```

**✅ Privacy Check**: No tap coordinates, only rates!

---

### Test 4: App Lifecycle Signals

**Objective**: Verify foreground/background detection

**Steps**:
1. Ensure session is active
2. Press device **Home button** (or swipe up)
3. Wait 5 seconds
4. Return to the app
5. Check events

**Expected Events**:
- `appSwitch` - direction: "background"
- `foregroundDuration` - Previous session duration
- `appSwitch` - direction: "foreground"

**Expected Payload**:
```json
{
  "direction": "foreground",
  "previous_duration_ms": 5000,
  "switch_count": 2
}
```

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
4. Check events

**Expected Events**:
- `idleGap` - with `idle_type`: "microIdle" (< 3s)
- `idleGap` - with `idle_type`: "midIdle" (3-10s)
- `idleGap` - with `idle_type`: "taskDropIdle" (> 10s)

**Expected Payload**:
```json
{
  "idle_seconds": 12.5,
  "idle_type": "taskDropIdle"
}
```

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
  "stability_index": 0.85,    // 0.0-1.0, higher = more stable
  "fragmentation_index": 0.15  // 0.0-1.0, higher = more fragmented
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
   - Type in text field
   - Scroll the view
   - Tap buttons
   - Switch apps once or twice
3. Click **"End Session"**
4. View the summary dialog

**Expected Summary**:
```
Session Summary
─────────────────────
Duration: 120000ms (2 minutes)
Event Count: 87
Average Typing Cadence: 2.3 keys/sec
Average Scroll Velocity: 145.2 px/sec
App Switch Count: 2
Stability Index: 0.82
Fragmentation Index: 0.18
```

---

## Verifying Data Privacy

### What You Should SEE in Events

✅ **Timing Metrics**:
- `inter_key_latency`: 110.5
- `velocity`: 150.0
- `idle_seconds`: 5.2

✅ **Counts and Rates**:
- `burst_length`: 12
- `tap_rate`: 1.5
- `switch_count`: 3

✅ **Aggregated Stats**:
- `cadence`: 2.5
- `acceleration`: 20.3
- `jitter`: 5.1

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

🔔 Event: typingCadence
   Payload: {cadence: 2.5, inter_key_latency: 110.0}

🔔 Event: scrollVelocity
   Payload: {velocity: 150.5}

🔔 Event: appSwitch
   Payload: {direction: background, switch_count: 1}

📊 Session Ended: SESS-1705234567890
   Duration: 120000ms
   Events: 87
   Stability: 0.85
```

### Event Stream (Real-time)

```json
[
  {
    "session_id": "SESS-1705234567890",
    "timestamp": 1705234567900,
    "type": "typingCadence",
    "payload": {
      "cadence": 2.5,
      "inter_key_latency": 110.0,
      "keys_in_window": 15
    }
  },
  {
    "session_id": "SESS-1705234567890",
    "timestamp": 1705234568100,
    "type": "scrollVelocity",
    "payload": {
      "velocity": 150.5,
      "unit": "pixels_per_second"
    }
  },
  {
    "session_id": "SESS-1705234567890",
    "timestamp": 1705234570000,
    "type": "idleGap",
    "payload": {
      "idle_seconds": 2.1,
      "idle_type": "microIdle"
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
      print('Behavioral Event: ${event.type}');
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
    return MaterialApp(/* your app */);
  }
}
```

---

## Support

If you encounter issues:

1. Check the [README.md](README.md) for basic setup
2. Review [IMPLEMENTATION.md](IMPLEMENTATION.md) for technical details
3. Check [PRIVACY_AUDIT.md](PRIVACY_AUDIT.md) for privacy questions
4. See [PERFORMANCE_PROFILING.md](PERFORMANCE_PROFILING.md) for performance issues
5. File an issue on GitHub

**Happy Testing! 🎉**
