import 'dart:collection';
import 'models/behavior_event.dart';
import 'models/behavior_window_features.dart';

/// Aggregates behavioral events into rolling time windows.
///
/// Maintains separate windows for 30-second (short) and 5-minute (long) periods.
class WindowAggregator {
  /// Duration of short window in milliseconds (30 seconds).
  static const int shortWindowMs = 30 * 1000;

  /// Duration of long window in milliseconds (5 minutes).
  static const int longWindowMs = 5 * 60 * 1000;

  /// Events in the short window (30s).
  final Queue<BehaviorEvent> _shortWindowEvents = Queue<BehaviorEvent>();

  /// Events in the long window (5m).
  final Queue<BehaviorEvent> _longWindowEvents = Queue<BehaviorEvent>();

  /// Current time for window boundary calculations (milliseconds since epoch).
  int _currentTime = DateTime.now().millisecondsSinceEpoch;

  /// Add a new event to both windows.
  void addEvent(BehaviorEvent event) {
    // Parse ISO timestamp to milliseconds
    final eventTime = DateTime.parse(event.timestamp).millisecondsSinceEpoch;
    _currentTime = eventTime;

    // Add to short window
    _shortWindowEvents.add(event);
    _pruneOldEvents(_shortWindowEvents, shortWindowMs);

    // Add to long window
    _longWindowEvents.add(event);
    _pruneOldEvents(_longWindowEvents, longWindowMs);
  }

  /// Get all events in the short window (30s).
  List<BehaviorEvent> getShortWindowEvents() {
    _pruneOldEvents(_shortWindowEvents, shortWindowMs);
    return List.unmodifiable(_shortWindowEvents);
  }

  /// Get all events in the long window (5m).
  List<BehaviorEvent> getLongWindowEvents() {
    _pruneOldEvents(_longWindowEvents, longWindowMs);
    return List.unmodifiable(_longWindowEvents);
  }

  /// Get events for a specific window type.
  List<BehaviorEvent> getWindowEvents(WindowType windowType) {
    switch (windowType) {
      case WindowType.short:
        return getShortWindowEvents();
      case WindowType.long:
        return getLongWindowEvents();
    }
  }

  /// Get the window duration in milliseconds.
  int getWindowDurationMs(WindowType windowType) {
    switch (windowType) {
      case WindowType.short:
        return shortWindowMs;
      case WindowType.long:
        return longWindowMs;
    }
  }

  /// Remove events older than the window duration.
  void _pruneOldEvents(Queue<BehaviorEvent> events, int windowDurationMs) {
    final cutoffTime = _currentTime - windowDurationMs;
    while (events.isNotEmpty) {
      final eventTime = DateTime.parse(events.first.timestamp).millisecondsSinceEpoch;
      if (eventTime < cutoffTime) {
        events.removeFirst();
      } else {
        break;
      }
    }
  }

  /// Clear all events from both windows.
  void clear() {
    _shortWindowEvents.clear();
    _longWindowEvents.clear();
  }

  /// Get the number of events in each window.
  Map<WindowType, int> getEventCounts() {
    return {
      WindowType.short: _shortWindowEvents.length,
      WindowType.long: _longWindowEvents.length,
    };
  }
}
