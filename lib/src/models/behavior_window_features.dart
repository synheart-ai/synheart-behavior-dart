/// Window type for behavior feature aggregation.
enum WindowType {
  /// 30-second rolling window.
  short,

  /// 5-minute rolling window.
  long,
}

/// Derived behavior features for a time window.
///
/// Contains all normalized features computed from raw behavioral events,
/// plus MLP inference outputs (distraction_score and focus_hint).
/// Matches the Behavior → HSI Fusion Table specification.
class BehaviorWindowFeatures {
  /// Normalized tap rate (0.0 to 1.0).
  final double tapRateNorm;

  /// Normalized keystroke rate (0.0 to 1.0).
  final double keystrokeRateNorm;

  /// Normalized scroll velocity (0.0 to 1.0).
  final double scrollVelocityNorm;

  /// Ratio of idle time to total window time (0.0 to 1.0).
  final double idleRatio;

  /// Normalized app switch rate (0.0 to 1.0).
  final double switchRateNorm;

  /// Burstiness metric (0.0 to 1.0) - measures activity clustering.
  /// Formula: (σ - μ)/(σ + μ) remapped to [0,1]
  final double burstiness;

  /// Session fragmentation index (0.0 to 1.0).
  final double sessionFragmentation;

  /// Normalized notification received rate (0.0 to 1.0).
  final double notifRateNorm;

  /// Normalized notification opened rate (0.0 to 1.0).
  final double notifOpenRateNorm;

  /// Notification score: 0.6 * notif_rate_norm + 0.4 * notif_open_rate_norm
  final double notificationScore;

  /// Typing cadence stability (0.0 to 1.0) - consistency of typing rhythm.
  /// Formula: exp(-α * cv_key)
  final double typingCadenceStability;

  /// Scroll cadence stability (0.0 to 1.0) - consistency of scroll rhythm.
  /// Formula: exp(-β * cv_scroll)
  final double scrollCadenceStability;

  /// Interaction intensity: weighted combination of tap/key/scroll minus idle.
  /// Formula: σ(w1*tap + w2*key + w3*scroll - w4*idle_ratio)
  final double interactionIntensity;

  /// Behavioral distraction score from MLP (0.0 to 1.0).
  final double distractionScore;

  /// Behavioral focus hint from MLP (0.0 to 1.0).
  final double focusHint;

  /// Window type (short or long).
  final WindowType windowType;

  /// Timestamp when these features were computed.
  final int timestamp;

  const BehaviorWindowFeatures({
    required this.tapRateNorm,
    required this.keystrokeRateNorm,
    required this.scrollVelocityNorm,
    required this.idleRatio,
    required this.switchRateNorm,
    required this.burstiness,
    required this.sessionFragmentation,
    required this.notifRateNorm,
    required this.notifOpenRateNorm,
    required this.notificationScore,
    required this.typingCadenceStability,
    required this.scrollCadenceStability,
    required this.interactionIntensity,
    required this.distractionScore,
    required this.focusHint,
    required this.windowType,
    required this.timestamp,
  });

  /// Create zero-initialized features (used when no data available).
  factory BehaviorWindowFeatures.zero(WindowType windowType) {
    return BehaviorWindowFeatures(
      tapRateNorm: 0.0,
      keystrokeRateNorm: 0.0,
      scrollVelocityNorm: 0.0,
      idleRatio: 0.0,
      switchRateNorm: 0.0,
      burstiness: 0.0,
      sessionFragmentation: 0.0,
      notifRateNorm: 0.0,
      notifOpenRateNorm: 0.0,
      notificationScore: 0.0,
      typingCadenceStability: 0.0,
      scrollCadenceStability: 0.0,
      interactionIntensity: 0.0,
      distractionScore: 0.0,
      focusHint: 0.0,
      windowType: windowType,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => {
        'tap_rate_norm': tapRateNorm,
        'keystroke_rate_norm': keystrokeRateNorm,
        'scroll_velocity_norm': scrollVelocityNorm,
        'idle_ratio': idleRatio,
        'switch_rate_norm': switchRateNorm,
        'burstiness': burstiness,
        'session_fragmentation': sessionFragmentation,
        'notif_rate_norm': notifRateNorm,
        'notif_open_rate_norm': notifOpenRateNorm,
        'notification_score': notificationScore,
        'typing_cadence_stability': typingCadenceStability,
        'scroll_cadence_stability': scrollCadenceStability,
        'interaction_intensity': interactionIntensity,
        'distraction_score': distractionScore,
        'focus_hint': focusHint,
        'window_type': windowType.name,
        'timestamp': timestamp,
      };

  factory BehaviorWindowFeatures.fromJson(Map<String, dynamic> json) {
    return BehaviorWindowFeatures(
      tapRateNorm: (json['tap_rate_norm'] as num).toDouble(),
      keystrokeRateNorm: (json['keystroke_rate_norm'] as num).toDouble(),
      scrollVelocityNorm: (json['scroll_velocity_norm'] as num).toDouble(),
      idleRatio: (json['idle_ratio'] as num).toDouble(),
      switchRateNorm: (json['switch_rate_norm'] as num).toDouble(),
      burstiness: (json['burstiness'] as num).toDouble(),
      sessionFragmentation: (json['session_fragmentation'] as num).toDouble(),
      notifRateNorm: (json['notif_rate_norm'] as num?)?.toDouble() ?? 0.0,
      notifOpenRateNorm:
          (json['notif_open_rate_norm'] as num?)?.toDouble() ?? 0.0,
      notificationScore: (json['notification_score'] as num?)?.toDouble() ??
          (json['notification_load'] as num?)?.toDouble() ??
          0.0, // Backward compatibility
      typingCadenceStability:
          (json['typing_cadence_stability'] as num).toDouble(),
      scrollCadenceStability:
          (json['scroll_cadence_stability'] as num?)?.toDouble() ?? 0.0,
      interactionIntensity:
          (json['interaction_intensity'] as num?)?.toDouble() ?? 0.0,
      distractionScore: (json['distraction_score'] as num).toDouble(),
      focusHint: (json['focus_hint'] as num).toDouble(),
      windowType: WindowType.values.firstWhere(
        (w) => w.name == json['window_type'],
        orElse: () => WindowType.short,
      ),
      timestamp: json['timestamp'] as int,
    );
  }

  /// Convert to HSI (Human State Inference) payload format.
  ///
  /// Returns a JSON-compatible map matching the Behavior → HSI Fusion Table specification.
  ///
  /// Parameters:
  /// - [userId]: Anonymous user identifier (e.g., "anon_43a8cd")
  /// - [deviceId]: Device identifier (e.g., "synheart_ios_14")
  /// - [behaviorVersion]: SDK version (e.g., "1.0.0")
  /// - [consentBehavior]: Whether behavior tracking consent is granted (default: true)
  Map<String, dynamic> toHSIPayload({
    required String userId,
    required String deviceId,
    required String behaviorVersion,
    bool consentBehavior = true,
  }) {
    // Calculate window duration based on window type
    final windowDurationSeconds =
        windowType == WindowType.short ? 30 : 300; // 30s or 5m
    final windowStart = timestamp ~/ 1000; // Convert to seconds
    final windowEnd = windowStart + windowDurationSeconds;

    return {
      'window_start': windowStart,
      'window_end': windowEnd,
      'user_id': userId,
      'device_id': deviceId,
      'behavior_version': behaviorVersion,
      'features': {
        'tap_rate_norm': tapRateNorm,
        'keystroke_rate_norm': keystrokeRateNorm,
        'scroll_velocity_norm': scrollVelocityNorm,
        'typing_cadence_stability': typingCadenceStability,
        'scroll_cadence_stability': scrollCadenceStability,
        'idle_ratio': idleRatio,
        'switch_rate_norm': switchRateNorm,
        'session_fragmentation': sessionFragmentation,
        'burstiness': burstiness,
        'notif_rate_norm': notifRateNorm,
        'notif_open_rate_norm': notifOpenRateNorm,
        'notification_load':
            notificationScore, // Note: spec uses "notification_load"
        'distraction_score': distractionScore,
        'behavioral_focus_hint':
            focusHint, // Note: spec uses "behavioral_focus_hint"
      },
      'consent': {
        'behavior': consentBehavior,
      },
      'source': 'behavior_sdk',
    };
  }

  @override
  String toString() {
    return 'BehaviorWindowFeatures(windowType: $windowType, '
        'distractionScore: ${distractionScore.toStringAsFixed(3)}, '
        'focusHint: ${focusHint.toStringAsFixed(3)})';
  }
}
