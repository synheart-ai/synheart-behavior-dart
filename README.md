# Synheart Behavior

> On-device behavioral signal inference from digital interactions for Flutter applications

[![pub.dev](https://img.shields.io/pub/v/synheart_behavior.svg)](https://pub.dev/packages/synheart_behavior)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-lightgrey.svg)](https://pub.dev/packages/synheart_behavior)
[![Dart](https://img.shields.io/badge/dart-%3E%3D3.0.0-blue.svg)](https://dart.dev/)
[![Flutter](https://img.shields.io/badge/flutter-%3E%3D3.10.0-blue.svg)](https://flutter.dev/)

A privacy-preserving mobile SDK that collects digital behavioral signals from smartphones. The SDK transforms low-level digital interaction events into structured numerical representations of behavior across event and session. By modeling interaction timing, intensity, fragmentation, and interruption patterns without collecting content or personal data, the SDK provides stable, interpretable metrics to represent digital behavior.

These behavioral signals power downstream systems such as:
- Focus and distraction inference
- Digital wellness analytics
- Cognitive load and fatigue estimation
- Multimodal human state modeling (HSI)

## 🚀 Features

- **Privacy-First**: No text, content, or personally identifiable information (PII) collected—only timing-based signals
- **Real-Time Streaming**: Event streams for scroll, tap, swipe, notification, and call interactions
- **Session Tracking**: Built-in session management with comprehensive summaries
- **Motion State Prediction**: Activity recognition (LAYING, MOVING, SITTING, STANDING) using ML model inference
- **Flutter Integration**: Gesture detection widgets for Flutter apps
- **Minimal Permissions**: No permissions required for basic functionality (scroll, tap, swipe). Optional permissions for notification and call tracking.
- **Platform Support**: iOS and Android with native implementations

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  synheart_behavior: ^0.0.1
```

Then run:

```bash
flutter pub get
```

### Platform Setup

**No additional configuration required!** The SDK works out of the box. For optional features (notifications and calls), see the [Permissions](#permissions) section below.

## 🎯 Quick Start

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

## 📡 Real-Time Event Tracking

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

## 📊 Event Types

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

## 🔐 Permissions

**Note**: Basic functionality (scroll, tap, swipe) requires **no permissions**. The following permissions are optional and only needed for notification and call tracking.

No content-level information is ever collected or stored. For notifications, the SDK does not record notification text, sender identity, application source, or semantic meaning. For phone calls, the SDK does not record audio, voice data, call content, or call participants.

Instead, the SDK records only event-level metadata, such as:

- the occurrence of a notification or call,
- the timestamp of the event,
- and the user’s interaction outcome (e.g., opened, dismissed, ignored).

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

Required for tracking call interactions (answered and ignored).

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

## 🔧 Configuration

### Initial Configuration

Configure the SDK during initialization:

```dart
final config = BehaviorConfig(
  // Enable/disable signal types
  enableInputSignals: true,        // Scroll, tap, swipe gestures
  enableAttentionSignals: true,    // App switching, idle gaps, session stability
  enableMotionLite: true,          // Device motion + activity recognition (LAYING, MOVING, SITTING, STANDING)

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

## 📈 Session Management

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
print('Interaction Intensity: ${summary.behavioralMetrics.interactionIntensity}');
print('Distraction Score: ${summary.behavioralMetrics.distractionScore}');
print('Focus Hint: ${summary.behavioralMetrics.focusHint}');
print('Deep Focus Blocks: ${summary.behavioralMetrics.deepFocusBlocks.length}');

// Activity summary
print('Total Events: ${summary.activitySummary.totalEvents}');
print('App Switches: ${summary.activitySummary.appSwitchCount}');

// Notification summary
print('Notifications: ${summary.notificationSummary.notificationCount}');
print('Ignore Rate: ${summary.notificationSummary.notificationIgnoreRate}');

// Motion state (if enableMotionLite is true)
if (summary.motionState != null) {
  print('Motion State: ${summary.motionState!.majorState}');
  print('Confidence: ${summary.motionState!.confidence}');
  print('States: ${summary.motionState!.state}');
}
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

### Core Behavioral Metrics

Session-level outputs include:
- `interactionIntensity`: Overall interaction rate and engagement
- `distractionScore`: Behavioral proxy for distraction (0-1)
- `focusHint`: Behavioral proxy for focus quality (0-1)
- `deepFocusBlocks`: Periods of sustained, uninterrupted engagement
- `taskSwitchRate`: Frequency of app switching
- `idleRatio`: Proportion of idle time vs active interaction
- `fragmentedIdleRatio`: Ratio of fragmented vs continuous idle periods
- `burstiness`: Temporal clustering of interaction events
- `notificationLoad`: Notification pressure and response patterns
- `scrollJitterRate`: Scroll pattern irregularity

All metrics are bounded, normalized, and numerically stable.

## ⚙️ Additional Features

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

## 🔒 Privacy & Compliance

The Synheart SDK is designed around privacy-by-design and data minimization principles. It captures only the minimum interaction metadata required to model digital behavior, without accessing personal, semantic, or content-level information.

### Hard Guarantees

✅ **No PII**: The SDK does not collect names, contacts, account identifiers, message content, or any user-identifying data. All signals are timing-based and structural.

✅ **No content capture**: The SDK does not collect notification text/titles/sender identity, call audio/voice data/participants, or application UI content/screen data.

✅ **No keystroke logging**: Text input is never recorded. Interactions with text fields are captured only as abstract tap events (timing and duration only), without any character-level data.

✅ **No audio or visual recording**: The SDK does not access the screen buffer, screenshots, camera, microphone, or any form of visual/audio capture.

✅ **Permission-scoped tracking only**: Behavioral data is collected exclusively from applications that explicitly receive user permission. The SDK does not monitor, infer, or aggregate behavior across the entire device or across unpermitted applications.

✅ **No tracking across unconsented apps**: The SDK only tracks behavior within the app that integrates it and has received user consent.

✅ **Event-level metadata only**: Collected data is limited to event type (tap, scroll, swipe, notification, call), timestamp, and non-semantic physical metrics (duration, velocity). No semantic interpretation is performed at the data collection stage.

### Connectivity & System Access

✅ **No internet connectivity required**: The SDK functions fully offline and does not require an active internet connection to perform behavioral capture or inference.

✅ **Network availability state only**: The SDK may record a binary system-level indicator of whether network connectivity is present at a given time. This signal does not include network traffic, destinations, IPs, or content, does not trigger any data transmission, and is used solely as contextual metadata.

✅ **No Bluetooth or external connectivity required**: The SDK does not depend on Bluetooth, NFC, or communication with external devices.

✅ **No background network communication**: Behavioral computation and aggregation occur locally without initiating network requests. Any optional data transmission is explicitly controlled, consent-gated, and configurable.

### Processing & Storage

✅ **On-device computation by default**: Behavioral features and metrics are computed locally on the device whenever possible, minimizing data exposure.

✅ **Ephemeral data handling**: Raw interaction events are processed in-memory and are not persisted in long-term storage unless explicitly configured for research or debugging purposes.

✅ **No third-party data sharing**: The SDK does not share raw or derived behavioral data with advertisers, analytics providers, or external third parties.

### Regulatory Alignment

✅ **GDPR / CCPA aligned**: The SDK adheres to the principles of data minimization, purpose limitation, user consent, and transparency.

✅ **App Tracking Transparency (ATT) not required**: The SDK does not track users across apps, services, or companies and does not perform cross-app or cross-device identification.

## 📱 Platform Support

- ✅ **iOS**: Swift 5+, iOS 12.0+
- ✅ **Android**: Kotlin, API 21+ (Android 5.0+)
- ✅ **Flutter**: 3.10.0+

## ⚡ Performance

The SDK is designed for continuous background operation with minimal resource impact:

- **CPU**: ≤ 1% average
- **Memory**: ≤ 10 MB peak
- **Battery**: < 0.3% per hour
- **Event processing**: < 500 μs per event
- **UI blocking**: None (all processing on background threads)

## 📋 Requirements

- **Dart SDK**: >=3.0.0 <4.0.0
- **Flutter**: >=3.10.0

## 🔍 Troubleshooting

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

## 🧪 Example App

A complete example app demonstrating all SDK features is available in the [`example/`](https://github.com/synheart-ai/synheart-behavior-dart/tree/main/example) directory.

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

## 📚 API Reference

For detailed API documentation, see the [pub.dev package page](https://pub.dev/packages/synheart_behavior).

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## 📄 License

Apache 2.0 License - see [LICENSE](LICENSE) file for details.

## 👥 Author

Israel Goytom

## 🔗 Links

- 📦 [pub.dev package](https://pub.dev/packages/synheart_behavior)
- 🔗 [GitHub repository](https://github.com/synheart-ai/synheart-behavior-dart)
- 🔗 [Parent specification repository](https://github.com/synheart-ai/synheart-behavior)
- 📖 [Example App Guide](EXAMPLE_APP_GUIDE.md)

## 🔗 Related Projects

- [Synheart Focus](https://github.com/synheart-ai/synheart-focus-dart) - Cognitive concentration inference
- [Synheart Emotion](https://github.com/synheart-ai/synheart-emotion-dart) - Physiological emotion inference from biosignals
- [Synheart Behavior (Parent)](https://github.com/synheart-ai/synheart-behavior) - Multi-platform SDK specification

## ⚖️ Patent Pending Notice

This project is provided under an open-source license. Certain underlying systems, methods, and architectures described or implemented herein may be covered by one or more pending patent applications.

Nothing in this repository grants any license, express or implied, to any patents or patent applications, except as provided by the applicable open-source license.
