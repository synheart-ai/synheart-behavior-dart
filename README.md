# Synheart Behavioral SDK for Flutter

A lightweight, privacy-preserving mobile SDK that collects digital behavioral signals from smartphones. These signals represent biobehavioral markers strongly correlated with cognitive and emotional states, especially focus, stress, engagement, and fatigue.

## Features

- 🎯 **Privacy-First**: No text, content, or PII collected - only timing-based signals
- ⚡ **Lightweight**: <150 KB compiled, <2% CPU usage, <500 KB memory footprint
- 🔄 **Streaming API**: Real-time event streaming for behavioral signals
- 📊 **Session Tracking**: Built-in session management with summaries
- 🎨 **Easy Integration**: Simple API that works with Synheart Focus Engine, SWIP, and Syni

## Behavioral Signals

### Input Interaction Signals
- Keystroke timing metrics (inter-key latency, burst length, pause duration)
- Scroll dynamics (speed, acceleration, jitter)
- Gesture activity (tap rate, long-press, drag velocity)

### Attention & Multitasking Signals
- App switching (frequency, foreground duration)
- Idle gaps (micro, mid, task-drop)
- Session stability (stability index, fragmentation)

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  synheart_behavior:
    git:
      url: https://github.com/synheart-ai/synheart-behavior-flutter.git
      ref: main
```

## Usage

### Initialization

```dart
import 'package:synheart_behavior/synheart_behavior.dart';

final behavior = await SynheartBehavior.initialize(
  config: BehaviorConfig(
    enableInputSignals: true,
    enableAttentionSignals: true,
    enableMotionLite: false,
  ),
);
```

### Streaming API

```dart
behavior.onEvent.listen((event) {
  print('Event type: ${event.type}');
  print('Payload: ${event.payload}');
  print('Timestamp: ${event.timestamp}');
});
```

### Session Tracking

```dart
final session = await behavior.startSession();

// ... user interacts with app ...

final summary = await session.end();
print('Session duration: ${summary.duration}');
print('Total events: ${summary.eventCount}');
```

### Manual Polling

```dart
final stats = await behavior.getCurrentStats();
print('Current typing cadence: ${stats.typingCadence}');
print('Scroll velocity: ${stats.scrollVelocity}');
```

## Example Event Payload

```json
{
  "session_id": "SESS-xyz",
  "timestamp": 1731462000,
  "type": "typing_burst",
  "payload": {
    "burst_length": 14,
    "inter_key_latency": 110,
    "variance": 14.3
  }
}
```

## Privacy & Compliance

- ✅ No PII collected
- ✅ No keystroke content
- ✅ No screen capture
- ✅ No app content
- ✅ Fully local processing
- ✅ GDPR/CCPA-ready
- ✅ iOS App Tracking Transparency not required
- ✅ Android Privacy Sandbox friendly

## Performance

- <2% CPU usage
- <500 KB memory footprint
- <2% battery overhead
- <1 ms processing latency
- Zero background threads

## Platform Support

- iOS (Swift 5+)
- Android (Kotlin)
- Flutter (MethodChannel → native SDKs)

## License

[Add your license here]

## Author

Israel Goytom

## Contributing

[Add contributing guidelines]

