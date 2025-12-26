/// Configuration for initializing the Synheart Behavioral SDK.
class BehaviorConfig {
  /// Enable input interaction signals (keystroke timing, scroll dynamics, gestures).
  final bool enableInputSignals;

  /// Enable attention and multitasking signals (app switching, idle gaps, session stability).
  final bool enableAttentionSignals;

  /// Enable motion-lite signals (device orientation, shake patterns, micro-movement).
  /// Note: This is optional and may have higher battery impact.
  final bool enableMotionLite;

  /// Custom session ID prefix. If null, auto-generated.
  final String? sessionIdPrefix;

  /// Event batch size for streaming. Default: 10 events per batch.
  final int eventBatchSize;

  /// Maximum idle gap duration in seconds before considering task dropped.
  /// Default: 10 seconds.
  final double maxIdleGapSeconds;

  /// Anonymous user identifier for HSI payloads (e.g., "anon_43a8cd").
  /// If null, will be auto-generated.
  final String? userId;

  /// Device identifier for HSI payloads (e.g., "synheart_ios_14").
  /// If null, will be auto-generated based on platform.
  final String? deviceId;

  /// Behavior SDK version for HSI payloads (e.g., "1.0.0").
  /// Default: "1.0.0"
  final String behaviorVersion;

  /// Whether behavior tracking consent is granted.
  /// Default: true
  final bool consentBehavior;

  const BehaviorConfig({
    this.enableInputSignals = true,
    this.enableAttentionSignals = true,
    this.enableMotionLite = false,
    this.sessionIdPrefix,
    this.eventBatchSize = 10,
    this.maxIdleGapSeconds = 10.0,
    this.userId,
    this.deviceId,
    this.behaviorVersion = '1.0.0',
    this.consentBehavior = true,
  });

  Map<String, dynamic> toJson() => {
        'enableInputSignals': enableInputSignals,
        'enableAttentionSignals': enableAttentionSignals,
        'enableMotionLite': enableMotionLite,
        'sessionIdPrefix': sessionIdPrefix,
        'eventBatchSize': eventBatchSize,
        'maxIdleGapSeconds': maxIdleGapSeconds,
        'userId': userId,
        'deviceId': deviceId,
        'behaviorVersion': behaviorVersion,
        'consentBehavior': consentBehavior,
      };
}
