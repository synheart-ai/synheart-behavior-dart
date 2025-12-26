/// Types of behavioral events that can be emitted by the SDK.
enum BehaviorEventType {
  scroll,
  tap,
  swipe,
  notification,
  call,
}

/// Scroll direction enum (vertical scrolling only)
enum ScrollDirection {
  up,
  down,
}

/// Swipe direction enum (horizontal swipes only)
enum SwipeDirection {
  left,
  right,
}

/// Notification/Call action enum
enum InterruptionAction {
  ignored,
  opened,
  answered,
  dismissed,
}

/// A single behavioral event emitted by the SDK.
class BehaviorEvent {
  /// Unique event ID.
  final String eventId;

  /// Unique session ID for this event.
  final String sessionId;

  /// Timestamp in ISO 8601 format (e.g., "2025-03-14T10:15:23.456Z").
  final String timestamp;

  /// Type of behavioral event.
  final BehaviorEventType eventType;

  /// Event-specific metrics.
  final Map<String, dynamic> metrics;

  BehaviorEvent({
    String? eventId,
    required this.sessionId,
    DateTime? timestamp,
    required this.eventType,
    required this.metrics,
  })  : eventId = eventId ?? 'evt_${DateTime.now().millisecondsSinceEpoch}',
        timestamp = timestamp?.toUtc().toIso8601String() ??
            DateTime.now().toUtc().toIso8601String();

  /// Create a scroll event.
  factory BehaviorEvent.scroll({
    required String sessionId,
    required double velocity,
    required double acceleration,
    required ScrollDirection direction,
    required bool directionReversal,
    String? eventId,
    DateTime? timestamp,
  }) {
    return BehaviorEvent(
      eventId: eventId,
      sessionId: sessionId,
      timestamp: timestamp,
      eventType: BehaviorEventType.scroll,
      metrics: {
        'velocity': velocity,
        'acceleration': acceleration,
        'direction': direction.name,
        'direction_reversal': directionReversal,
      },
    );
  }

  /// Create a tap event.
  factory BehaviorEvent.tap({
    required String sessionId,
    required int tapDurationMs,
    required bool longPress,
    String? eventId,
    DateTime? timestamp,
  }) {
    return BehaviorEvent(
      eventId: eventId,
      sessionId: sessionId,
      timestamp: timestamp,
      eventType: BehaviorEventType.tap,
      metrics: {
        'tap_duration_ms': tapDurationMs,
        'long_press': longPress,
      },
    );
  }

  /// Create a swipe event.
  factory BehaviorEvent.swipe({
    required String sessionId,
    required SwipeDirection direction,
    required double distancePx,
    required int durationMs,
    required double velocity,
    required double acceleration,
    String? eventId,
    DateTime? timestamp,
  }) {
    return BehaviorEvent(
      eventId: eventId,
      sessionId: sessionId,
      timestamp: timestamp,
      eventType: BehaviorEventType.swipe,
      metrics: {
        'direction': direction.name,
        'distance_px': distancePx,
        'duration_ms': durationMs,
        'velocity': velocity,
        'acceleration': acceleration,
      },
    );
  }

  /// Create a notification event.
  factory BehaviorEvent.notification({
    required String sessionId,
    required InterruptionAction action,
    String? eventId,
    DateTime? timestamp,
  }) {
    return BehaviorEvent(
      eventId: eventId,
      sessionId: sessionId,
      timestamp: timestamp,
      eventType: BehaviorEventType.notification,
      metrics: {
        'action': action.name,
      },
    );
  }

  /// Create a call event.
  factory BehaviorEvent.call({
    required String sessionId,
    required InterruptionAction action,
    String? eventId,
    DateTime? timestamp,
  }) {
    return BehaviorEvent(
      eventId: eventId,
      sessionId: sessionId,
      timestamp: timestamp,
      eventType: BehaviorEventType.call,
      metrics: {
        'action': action.name,
      },
    );
  }

  factory BehaviorEvent.fromJson(Map<String, dynamic> json) {
    final eventData = json['event'] as Map<String, dynamic>? ?? json;
    final eventTypeStr = eventData['event_type'] as String;
    final eventType = BehaviorEventType.values.firstWhere(
      (e) => e.name == eventTypeStr,
      orElse: () => BehaviorEventType.tap,
    );

    return BehaviorEvent(
      eventId: eventData['event_id'] as String?,
      sessionId: eventData['session_id'] as String,
      timestamp: eventData['timestamp'] != null
          ? DateTime.parse(eventData['timestamp'] as String)
          : null,
      eventType: eventType,
      metrics: Map<String, dynamic>.from(eventData['metrics'] as Map),
    );
  }

  /// Convert to the new event format (wrapped in "event" object).
  Map<String, dynamic> toJson() => {
        'event': {
          'event_id': eventId,
          'session_id': sessionId,
          'timestamp': timestamp,
          'event_type': eventType.name,
          'metrics': metrics,
        },
      };

  /// Convert to legacy format for backward compatibility during migration.
  Map<String, dynamic> toLegacyJson() => {
        'session_id': sessionId,
        'timestamp': DateTime.parse(timestamp).millisecondsSinceEpoch,
        'type': eventType.name,
        'payload': metrics,
      };

  @override
  String toString() {
    return 'BehaviorEvent(eventId: $eventId, sessionId: $sessionId, type: $eventType, timestamp: $timestamp)';
  }
}
