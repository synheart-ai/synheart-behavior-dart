# Synheart Behavior Example App

This example app demonstrates how to use the Synheart Behavioral SDK in a Flutter application.

## Features Demonstrated

- SDK initialization
- Session management (start/end)
- Real-time event streaming
- Stats polling
- Interactive test area for generating behavioral events

## Running the Example

```bash
cd example
flutter pub get
flutter run
```

## Usage

1. **Initialize SDK**: The app automatically initializes the SDK on startup
2. **Start Session**: Tap "Start Session" to begin tracking behavioral signals
3. **Interact**: Tap buttons, scroll, or swipe to generate behavioral events
4. **View Events**: See real-time events in the events list
5. **Check Stats**: Tap "Refresh Stats" to see current behavioral statistics
6. **End Session**: Tap "End Session" to stop tracking and view summary

## Privacy Note

This SDK only collects timing-based signals. No text content, keystroke content, or PII is ever collected.

