/// Represents an active behavioral tracking session.
class BehaviorSession {
  /// Unique session ID.
  final String sessionId;

  /// Start timestamp in milliseconds since epoch.
  final int startTimestamp;

  final Future<BehaviorSessionSummary> Function(String) _endCallback;

  BehaviorSession({
    required this.sessionId,
    required this.startTimestamp,
    required Future<BehaviorSessionSummary> Function(String) endCallback,
  }) : _endCallback = endCallback;

  /// End this session and generate a summary.
  Future<BehaviorSessionSummary> end() async {
    return await _endCallback(sessionId);
  }

  /// Get the current duration of this session in milliseconds.
  int get currentDuration =>
      DateTime.now().millisecondsSinceEpoch - startTimestamp;
}

/// Summary statistics for a completed behavioral session.
class BehaviorSessionSummary {
  /// Unique session ID.
  final String sessionId;

  /// Start timestamp in milliseconds since epoch.
  final int startTimestamp;

  /// End timestamp in milliseconds since epoch.
  final int endTimestamp;

  /// Total session duration in milliseconds.
  final int duration;

  /// Total number of events captured during this session.
  int eventCount = 0;

  /// Average typing cadence (keys per second) during session.
  double? averageTypingCadence;

  /// Average scroll velocity during session.
  double? averageScrollVelocity;

  /// Number of app switches during session.
  int appSwitchCount = 0;

  /// Session stability index (0.0 to 1.0).
  double? stabilityIndex;

  /// Fragmentation index (0.0 to 1.0).
  double? fragmentationIndex;

  BehaviorSessionSummary({
    required this.sessionId,
    required this.startTimestamp,
    required this.endTimestamp,
    required this.duration,
    this.eventCount = 0,
    this.averageTypingCadence,
    this.averageScrollVelocity,
    this.appSwitchCount = 0,
    this.stabilityIndex,
    this.fragmentationIndex,
  });

  factory BehaviorSessionSummary.fromJson(Map<String, dynamic> json) {
    return BehaviorSessionSummary(
      sessionId: json['session_id'] as String,
      startTimestamp: json['start_timestamp'] as int,
      endTimestamp: json['end_timestamp'] as int,
      duration: json['duration'] as int,
      eventCount: json['event_count'] as int? ?? 0,
      averageTypingCadence: json['average_typing_cadence'] as double?,
      averageScrollVelocity: json['average_scroll_velocity'] as double?,
      appSwitchCount: json['app_switch_count'] as int? ?? 0,
      stabilityIndex: json['stability_index'] as double?,
      fragmentationIndex: json['fragmentation_index'] as double?,
    );
  }

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'start_timestamp': startTimestamp,
        'end_timestamp': endTimestamp,
        'duration': duration,
        'event_count': eventCount,
        'average_typing_cadence': averageTypingCadence,
        'average_scroll_velocity': averageScrollVelocity,
        'app_switch_count': appSwitchCount,
        'stability_index': stabilityIndex,
        'fragmentation_index': fragmentationIndex,
      };
}

