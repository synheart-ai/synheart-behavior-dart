/// Rolling statistics snapshot of current behavioral signals.
class BehaviorStats {
  // Typing functionality removed - these fields are always null
  // /// Current typing cadence (keys per second).
  // final double? typingCadence;

  // /// Current inter-key latency in milliseconds.
  // final double? interKeyLatency;

  // /// Current burst length (number of keys in current burst).
  // final int? burstLength;

  /// Current scroll velocity (pixels per second).
  final double? scrollVelocity;

  /// Current scroll acceleration (pixels per second squared).
  final double? scrollAcceleration;

  /// Current scroll jitter (variance in scroll speed).
  final double? scrollJitter;

  /// Current tap rate (taps per second).
  final double? tapRate;

  /// Number of app switches in the last minute.
  final int appSwitchesPerMinute;

  /// Current foreground duration in seconds.
  final double? foregroundDuration;

  /// Current idle gap duration in seconds.
  final double? idleGapSeconds;

  /// Current session stability index (0.0 to 1.0).
  final double? stabilityIndex;

  /// Current fragmentation index (0.0 to 1.0).
  final double? fragmentationIndex;

  /// Timestamp when these stats were captured.
  final int timestamp;

  const BehaviorStats({
    // this.typingCadence,
    // this.interKeyLatency,
    // this.burstLength,
    this.scrollVelocity,
    this.scrollAcceleration,
    this.scrollJitter,
    this.tapRate,
    this.appSwitchesPerMinute = 0,
    this.foregroundDuration,
    this.idleGapSeconds,
    this.stabilityIndex,
    this.fragmentationIndex,
    required this.timestamp,
  });

  factory BehaviorStats.fromJson(Map<String, dynamic> json) {
    return BehaviorStats(
      // typingCadence: json['typing_cadence'] as double?,
      // interKeyLatency: json['inter_key_latency'] as double?,
      // burstLength: json['burst_length'] as int?,
      scrollVelocity: json['scroll_velocity'] as double?,
      scrollAcceleration: json['scroll_acceleration'] as double?,
      scrollJitter: json['scroll_jitter'] as double?,
      tapRate: json['tap_rate'] as double?,
      appSwitchesPerMinute: json['app_switches_per_minute'] as int? ?? 0,
      foregroundDuration: json['foreground_duration'] as double?,
      idleGapSeconds: json['idle_gap_seconds'] as double?,
      stabilityIndex: json['stability_index'] as double?,
      fragmentationIndex: json['fragmentation_index'] as double?,
      timestamp: json['timestamp'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        // 'typing_cadence': typingCadence,
        // 'inter_key_latency': interKeyLatency,
        // 'burst_length': burstLength,
        'scroll_velocity': scrollVelocity,
        'scroll_acceleration': scrollAcceleration,
        'scroll_jitter': scrollJitter,
        'tap_rate': tapRate,
        'app_switches_per_minute': appSwitchesPerMinute,
        'foreground_duration': foregroundDuration,
        'idle_gap_seconds': idleGapSeconds,
        'stability_index': stabilityIndex,
        'fragmentation_index': fragmentationIndex,
        'timestamp': timestamp,
      };
}
