/// Types of behavioral events that can be emitted by the SDK.
enum BehaviorEventType {
  /// Keystroke timing events
  typingCadence,
  typingBurst,

  /// Scroll dynamics events
  scrollVelocity,
  scrollAcceleration,
  scrollJitter,
  scrollStop,

  /// Gesture activity events
  tapRate,
  longPressRate,
  dragVelocity,

  /// App switching events
  appSwitch,
  foregroundDuration,

  /// Idle gap events
  idleGap,
  microIdle,
  midIdle,
  taskDropIdle,

  /// Session stability events
  sessionStability,
  fragmentationIndex,

  /// Motion-lite events (optional)
  orientationShift,
  shakePattern,
  microMovement,
}

/// A single behavioral event emitted by the SDK.
class BehaviorEvent {
  /// Unique session ID for this event.
  final String sessionId;

  /// Timestamp in milliseconds since epoch.
  final int timestamp;

  /// Type of behavioral event.
  final BehaviorEventType type;

  /// Event payload containing signal-specific data.
  final Map<String, dynamic> payload;

  const BehaviorEvent({
    required this.sessionId,
    required this.timestamp,
    required this.type,
    required this.payload,
  });

  factory BehaviorEvent.fromJson(Map<String, dynamic> json) {
    return BehaviorEvent(
      sessionId: json['session_id'] as String,
      timestamp: json['timestamp'] as int,
      type: BehaviorEventType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => BehaviorEventType.typingCadence,
      ),
      payload: Map<String, dynamic>.from(json['payload'] as Map),
    );
  }

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'timestamp': timestamp,
        'type': type.name,
        'payload': payload,
      };

  @override
  String toString() {
    return 'BehaviorEvent(sessionId: $sessionId, type: $type, timestamp: $timestamp)';
  }
}
