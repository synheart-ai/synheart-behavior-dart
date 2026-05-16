/// Rolling statistics snapshot of current behavioral signals.
///
/// Fields are nullable when the corresponding signal hasn't been observed
/// yet, or — for typing fields — when typing aggregation is performed by
/// a downstream consumer rather than on-device in this SDK.
class BehaviorStats {
  /// Current typing cadence (keys per second). Null on Flutter when typing
  /// aggregation is delegated to the runtime. Kept for cross-SDK parity.
  final double? typingCadence;

  /// Current inter-key latency in milliseconds. Null when not aggregated locally.
  final double? interKeyLatency;

  /// Current burst length (number of keys in current burst). Null when not
  /// aggregated locally.
  final int? burstLength;

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
    this.typingCadence,
    this.interKeyLatency,
    this.burstLength,
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
      typingCadence: (json['typing_cadence'] as num?)?.toDouble(),
      interKeyLatency: (json['inter_key_latency'] as num?)?.toDouble(),
      burstLength: (json['burst_length'] as num?)?.toInt(),
      scrollVelocity: (json['scroll_velocity'] as num?)?.toDouble(),
      scrollAcceleration: (json['scroll_acceleration'] as num?)?.toDouble(),
      scrollJitter: (json['scroll_jitter'] as num?)?.toDouble(),
      tapRate: (json['tap_rate'] as num?)?.toDouble(),
      appSwitchesPerMinute: json['app_switches_per_minute'] as int? ?? 0,
      foregroundDuration: (json['foreground_duration'] as num?)?.toDouble(),
      idleGapSeconds: (json['idle_gap_seconds'] as num?)?.toDouble(),
      stabilityIndex: (json['stability_index'] as num?)?.toDouble(),
      fragmentationIndex: (json['fragmentation_index'] as num?)?.toDouble(),
      timestamp: json['timestamp'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'typing_cadence': typingCadence,
        'inter_key_latency': interKeyLatency,
        'burst_length': burstLength,
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
