# Synheart Behavioral SDK for Flutter

[![pub.dev](https://img.shields.io/pub/v/synheart_behavior.svg)](https://pub.dev/packages/synheart_behavior)

A privacy-preserving mobile SDK that collects digital behavioral signals from smartphones. These timing-based signals represent biobehavioral markers correlated with cognitive and emotional states, especially focus, stress, engagement, and fatigue.

## Features

- **Privacy-First**: No text, content, or personally identifiable information (PII) collected—only timing-based signals
- **Real-Time Streaming**: Event streams for scroll, tap, swipe, notification, and call interactions
- **Session Tracking**: Built-in session management with comprehensive summaries
- **Flutter Integration**: Gesture detection widgets for Flutter apps
- **Minimal Permissions**: No permissions required for basic functionality (scroll, tap, swipe). Optional permissions for notification and call tracking.
- **Platform Support**: iOS and Android with native implementations

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  synheart_behavior: ^0.1.0
```

Then run:

```bash
flutter pub get
```

### Platform Setup

**No additional configuration required!** The SDK works out of the box. For optional features (notifications and calls), see the [Permissions](#permissions) section below.

## Quick Start

Here's a complete example to get you started:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:synheart_behavior/synheart_behavior.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SDK
  final behavior = await SynheartBehavior.initialize(
    config: const BehaviorConfig(
      enableInputSignals: true,
      enableAttentionSignals: true,
      enableMotionLite: false,
    ),
  );

  runApp(MyApp(behavior: behavior));
}

class MyApp extends StatelessWidget {
  final SynheartBehavior behavior;

  const MyApp({super.key, required this.behavior});

  @override
  Widget build(BuildContext context) {
    return behavior.wrapWithGestureDetector(
      MaterialApp(
        title: 'My App',
        home: HomePage(behavior: behavior),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final SynheartBehavior behavior;

  const HomePage({super.key, required this.behavior});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  BehaviorSession? _session;
  StreamSubscription<BehaviorEvent>? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _startListening();
    _startSession();
  }

  void _startListening() {
    // Listen to real-time events
    _eventSubscription = widget.behavior.onEvent.listen((event) {
      print('Event: ${event.eventType} at ${event.timestamp}');
      print('Metrics: ${event.metrics}');
    });

  }

  Future<void> _startSession() async {
    try {
      _session = await widget.behavior.startSession();
      print('Session started: ${_session!.sessionId}');
    } catch (e) {
      print('Failed to start session: $e');
    }
  }

  Future<void> _endSession() async {
    if (_session != null) {
      try {
        final summary = await _session!.end();
        print('Session ended: ${summary.durationMs}ms');
        print('Total events: ${summary.activitySummary.totalEvents}');
        print('Focus hint: ${summary.behavioralMetrics.focusHint}');
        _session = null;
      } catch (e) {
        print('Failed to end session: $e');
      }
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    widget.behavior.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My App')),
      body: Center(
        child: ElevatedButton(
          onPressed: _endSession,
          child: const Text('End Session'),
        ),
      ),
    );
  }
}
```

### Key Steps

1. **Initialize the SDK** - Call `SynheartBehavior.initialize()` before using the SDK
2. **Wrap Your App** - Use `wrapWithGestureDetector()` to enable gesture tracking
3. **Listen to Events** - Subscribe to `onEvent` stream for real-time behavioral signals
4. **Track Sessions** - Start and end sessions to get behavioral summaries
5. **Clean Up** - Call `dispose()` when done to free resources

## Real-Time Event Tracking

The SDK streams behavioral events in real-time as they occur. This is the primary way to track user behavior:

```dart
behavior.onEvent.listen((event) {
  print('Event: ${event.eventType} at ${event.timestamp}');
  print('Metrics: ${event.metrics}');

  // Handle different event types
  switch (event.eventType) {
    case BehaviorEventType.scroll:
      final velocity = event.metrics['velocity'] as double?;
      print('Scroll velocity: $velocity px/s');
      break;
    case BehaviorEventType.tap:
      final duration = event.metrics['tap_duration_ms'] as int?;
      final longPress = event.metrics['long_press'] as bool?;
      print('Tap duration: $duration ms, long press: $longPress');
      break;
    case BehaviorEventType.swipe:
      final direction = event.metrics['direction'] as String?;
      final velocity = event.metrics['velocity'] as double?;
      print('Swipe direction: $direction, velocity: $velocity px/s');
      break;
    // ... handle other event types
  }
});
```

## Event Types

The SDK collects five types of behavioral events:

- **Scroll**: Velocity, acceleration, direction, direction reversals
- **Tap**: Duration, long-press detection
- **Swipe**: Direction, distance, velocity, acceleration
- **Notification**: Received, opened, ignored (requires permission)
- **Call**: Answered, ignored, dismissed (requires permission)

Each event includes:

- `eventId`: Unique identifier
- `sessionId`: Associated session ID
- `timestamp`: ISO 8601 timestamp
- `eventType`: Type of event (scroll, tap, swipe, etc.)
- `metrics`: Event-specific metrics (velocity, duration, etc.)

## Permissions

**Note**: Basic functionality (scroll, tap, swipe) requires **no permissions**. The following permissions are optional and only needed for notification and call tracking.

### Notification Permission

Required for tracking notification interactions (received, opened, ignored).

**Android**: Requires enabling Notification Access in system settings  
**iOS**: Requires notification authorization

```dart
// Check if permission is granted
final hasPermission = await behavior.checkNotificationPermission();

if (!hasPermission) {
  // Request permission (opens system settings on Android)
  final granted = await behavior.requestNotificationPermission();
  if (granted) {
    print('Notification permission granted');
  } else {
    print('Notification permission denied');
  }
}
```

### Call Permission

Required for tracking call interactions (answered, ignored, dismissed).

**Android**: Requires `READ_PHONE_STATE` permission  
**iOS**: No explicit permission needed (uses system callbacks)

```dart
// Check if permission is granted
final hasPermission = await behavior.checkCallPermission();

if (!hasPermission) {
  // Request permission
  await behavior.requestCallPermission();
}
```

## Configuration

### Initial Configuration

Configure the SDK during initialization:

```dart
final config = BehaviorConfig(
  // Enable/disable signal types
  enableInputSignals: true,        // Scroll, tap, swipe gestures
  enableAttentionSignals: true,    // App switching, idle gaps, session stability
  enableMotionLite: false,         // Device motion (optional, may impact battery)

  // Session configuration
  sessionIdPrefix: 'MYAPP',        // Custom session ID prefix (default: 'SESS')

  // User/device identifiers (optional, for custom tracking)
  userId: 'user_123',              // Optional: custom user identifier
  deviceId: 'device_456',         // Optional: custom device identifier

  // SDK configuration
  behaviorVersion: '1.0.0',        // SDK version identifier
  consentBehavior: true,           // Consent flag for behavior tracking

  // Advanced settings
  eventBatchSize: 10,              // Events per batch (default: 10)
  maxIdleGapSeconds: 10.0,        // Max idle time before task drop (default: 10.0)
);

final behavior = await SynheartBehavior.initialize(config: config);
```

### Update Configuration at Runtime

You can update the configuration after initialization:

```dart
// Disable motion tracking to save battery
await behavior.updateConfig(BehaviorConfig(
  enableInputSignals: true,
  enableAttentionSignals: true,
  enableMotionLite: false,  // Disabled
));
```

## Session Management

### Starting a Session

```dart
// Start with auto-generated session ID
final session = await behavior.startSession();

// Or provide a custom session ID
final session = await behavior.startSession(
  sessionId: 'MYAPP-${DateTime.now().millisecondsSinceEpoch}',
);
```

### Ending a Session

When a session ends, you receive a comprehensive summary:

```dart
final summary = await session.end();

// Session metadata
print('Session ID: ${summary.sessionId}');
print('Started: ${summary.startAt}');
print('Ended: ${summary.endAt}');
print('Duration: ${summary.durationMs}ms');

// Behavioral metrics
print('Focus Hint: ${summary.behavioralMetrics.focusHint}');
print('Distraction Score: ${summary.behavioralMetrics.distractionScore}');
print('Interaction Intensity: ${summary.behavioralMetrics.interactionIntensity}');
print('Deep Focus Blocks: ${summary.behavioralMetrics.deepFocusBlocks}');

// Activity summary
print('Total Events: ${summary.activitySummary.totalEvents}');
print('App Switches: ${summary.activitySummary.appSwitchCount}');

// Notification summary
print('Notifications: ${summary.notificationSummary.notificationCount}');
print('Ignore Rate: ${summary.notificationSummary.notificationIgnoreRate}');
```

### Current Statistics

Get real-time statistics without ending a session:

```dart
final stats = await behavior.getCurrentStats();
print('Total events: ${stats.totalEvents}');
print('Active sessions: ${stats.activeSessions}');
```

### Session Status

```dart
// Check if SDK is initialized
if (behavior.isInitialized) {
  // Check current active session
  final currentSessionId = behavior.currentSessionId;
  if (currentSessionId != null) {
    print('Active session: $currentSessionId');
  }
}
```

## Additional Features

### Text Field Widget

The SDK provides a `BehaviorTextField` widget for convenience. Note that text input interactions are captured as tap events (not separate typing events):

```dart
behavior.createBehaviorTextField(
  controller: myTextController,
  decoration: const InputDecoration(
    labelText: 'Enter text',
  ),
)
```

**Note**: The SDK does not track typing/keystroke content. Text field interactions are captured as tap events with timing metrics only.

### Custom Event Sending

You can manually send events to the SDK. Note that only the predefined event types are supported (scroll, tap, swipe, notification, call):

```dart
final event = BehaviorEvent(
  eventId: 'custom-event-123',
  sessionId: behavior.currentSessionId ?? 'current',
  timestamp: DateTime.now(),
  eventType: BehaviorEventType.tap,  // Use one of the supported event types
  metrics: {'customMetric': 42},
);

await behavior.sendEvent(event);
```

### Cleanup

Always dispose of the SDK when done to free resources:

```dart
@override
void dispose() {
  behavior.dispose();
  super.dispose();
}
```

## Privacy & Compliance

- ✅ **No PII collected**: Only timing-based signals, no personal information
- ✅ **No keystroke tracking**: Typing is not tracked; text field interactions are captured as tap events only
- ✅ **No screen capture**: No screenshots or screen recording
- ✅ **No app content**: No access to app UI content or data
- ✅ **Fully local processing**: All processing happens on-device
- ✅ **No persistent storage**: Data stored only in memory
- ✅ **No network transmission**: Zero network activity
- ✅ **GDPR/CCPA-ready**: Compliant with privacy regulations
- ✅ **iOS App Tracking Transparency not required**: No user tracking across apps

## Platform Support

- ✅ **iOS**: Swift 5+, iOS 12.0+
- ✅ **Android**: Kotlin, API 21+ (Android 5.0+)
- ✅ **Flutter**: 3.10.0+

## Requirements

- **Dart SDK**: >=3.0.0 <4.0.0
- **Flutter**: >=3.10.0

## Troubleshooting

### SDK Not Initializing

**Problem**: `SynheartBehavior.initialize()` throws an exception.

**Solutions**:

- Ensure you're calling `WidgetsFlutterBinding.ensureInitialized()` before `runApp()` if initializing in `main()`
- Check that native platform code is properly integrated (should be automatic)
- Verify Flutter version meets requirements (>=3.10.0)

### No Events Being Collected

**Problem**: `onEvent` stream is not emitting events.

**Solutions**:

- Ensure you've wrapped your app with `wrapWithGestureDetector()`
- Verify a session is started with `startSession()`
- Check that `enableInputSignals` or `enableAttentionSignals` is `true` in config
- For notifications/calls, ensure permissions are granted

### Permission Requests Not Working

**Problem**: Permission requests don't show dialogs or open settings.

**Solutions**:

- **Android**: Notification access requires manual enablement in system settings
- **iOS**: Ensure you're testing on a real device (simulator may have limitations)
- Check platform-specific permission requirements in your app's manifest/Info.plist

### Session End Fails

**Problem**: `session.end()` throws an exception or times out.

**Solutions**:

- Ensure the session was properly started
- Check that the SDK is still initialized
- Verify native platform channel is working (check logs)
- Try ending the session with a timeout wrapper

### Build Errors

**Android**:

```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
```

**iOS**:

```bash
cd ios
pod deintegrate
pod install
cd ..
flutter clean
flutter pub get
```

## Example App

A complete example app demonstrating all SDK features is available in the [`example/`](https://github.com/synheart-ai/synheart-behavior-flutter/tree/main/example) directory.

To run the example:

```bash
cd example
flutter pub get
flutter run
```

The example app includes:

- Real-time event visualization
- Session management UI
- Permission handling examples
- Event type handling demonstrations

## API Reference

For detailed API documentation, see the [pub.dev package page](https://pub.dev/packages/synheart_behavior).

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Apache 2.0 License - see [LICENSE](LICENSE) file for details.

## Author

Israel Goytom

## Links

- 📦 [pub.dev package](https://pub.dev/packages/synheart_behavior)
- 🔗 [GitHub repository](https://github.com/synheart-ai/synheart-behavior-flutter)
- 📖 [Example App Guide](EXAMPLE_APP_GUIDE.md)

## Patent Pending Notice

This project is provided under an open-source license. Certain underlying systems, methods, and architectures described or implemented herein may be covered by one or more pending patent applications.

Nothing in this repository grants any license, express or implied, to any patents or patent applications, except as provided by the applicable open-source license.
