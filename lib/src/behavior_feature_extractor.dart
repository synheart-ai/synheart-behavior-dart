import 'dart:math' as math;
import 'models/behavior_event.dart';
import 'models/behavior_window_features.dart';

/// Extracts normalized behavior features from event windows.
///
/// Computes all features from the Behavior → HSI Fusion Table:
/// - tap_rate_norm
/// - keystroke_rate_norm
/// - scroll_velocity_norm
/// - typing_cadence_stability
/// - scroll_cadence_stability
/// - interaction_intensity
/// - idle_ratio
/// - switch_rate_norm
/// - session_fragmentation
/// - burstiness_norm
/// - notif_rate_norm
/// - notif_open_rate_norm
/// - notification_score
/// - distraction_score (from MLP)
/// - focus_hint (from MLP)
class BehaviorFeatureExtractor {
  /// Maximum expected values for normalization (used to compute 0.0-1.0 range).
  static const double maxTapRate = 10.0; // taps per second
  static const double maxKeystrokeRate = 8.0; // keystrokes per second
  static const double maxScrollVelocity = 2000.0; // pixels per second
  static const double maxSwitchRate = 2.0; // switches per minute
  static const double maxNotificationRate = 5.0; // notifications per minute

  final BehaviorMLP _mlp;

  BehaviorFeatureExtractor() : _mlp = BehaviorMLP();

  /// Extract features from events in a window.
  BehaviorWindowFeatures extractFeatures(
    List<BehaviorEvent> events,
    WindowType windowType,
    int windowDurationMs,
  ) {
    if (events.isEmpty) {
      return BehaviorWindowFeatures.zero(windowType);
    }

    // Compute raw metrics
    // For tap rate, count tapRate events (each tap emits one)
    final tapCount = _countEvents(events, BehaviorEventType.tapRate);

    // For keystroke rate: count typingCadence events (each keystroke emits one)
    // Note: typingBurst events represent bursts that already ended,
    // so those keystrokes are already counted in typingCadence events
    final keystrokeCount = _countEvents(events, [
      BehaviorEventType.typingCadence,
      // Don't double-count: typingBurst events are summaries, not additional keystrokes
    ]);

    final scrollEvents =
        _filterEvents(events, BehaviorEventType.scrollVelocity);

    final switchCount = _countEvents(events, BehaviorEventType.appSwitch);
    final idleEvents = _filterEvents(events, [
      BehaviorEventType.idleGap,
      BehaviorEventType.microIdle,
      BehaviorEventType.midIdle,
      BehaviorEventType.taskDropIdle,
    ]);
    // Separate notification counting
    final notifReceivedCount =
        _countEvents(events, BehaviorEventType.notificationReceived);
    final notifOpenedCount =
        _countEvents(events, BehaviorEventType.notificationOpened);

    // Normalize rates
    final windowDurationSeconds = windowDurationMs / 1000.0;

    // For tap rate: use event count (each tap emits one tapRate event)
    // Alternative: could use payload['tap_rate'] but counting is more accurate
    final tapRate = tapCount / windowDurationSeconds;
    final tapRateNorm = tapCount > 0 ? _normalize(tapRate, maxTapRate) : 0.0;

    // For keystroke rate: use total keystroke count (typingCadence events + burst lengths)
    final keystrokeRate = keystrokeCount / windowDurationSeconds;
    final keystrokeRateNorm =
        keystrokeCount > 0 ? _normalize(keystrokeRate, maxKeystrokeRate) : 0.0;

    final scrollVelocityNorm = _computeAverageScrollVelocity(scrollEvents);
    final switchRateNorm = _normalize(
      switchCount / (windowDurationSeconds / 60.0),
      maxSwitchRate,
    );
    final notifRateNorm = _normalize(
      notifReceivedCount / (windowDurationSeconds / 60.0),
      maxNotificationRate,
    );
    final notifOpenRateNorm = _normalize(
      notifOpenedCount / (windowDurationSeconds / 60.0),
      maxNotificationRate,
    );
    // Notification score: 0.6 * notif_rate_norm + 0.4 * notif_open_rate_norm
    final notificationScore =
        (0.6 * notifRateNorm + 0.4 * notifOpenRateNorm).clamp(0.0, 1.0);

    // Compute idle ratio
    final idleRatio = _computeIdleRatio(idleEvents, windowDurationMs);

    // Compute burstiness (activity clustering)
    final burstiness = _computeBurstiness(events, windowDurationMs);

    // Compute session fragmentation
    final sessionFragmentation =
        _computeFragmentation(events, windowDurationMs);

    // Compute typing cadence stability
    final typingCadenceStability =
        _computeTypingCadenceStability(events, windowDurationMs);

    // Compute scroll cadence stability
    final scrollCadenceStability =
        _computeScrollCadenceStability(events, windowDurationMs);

    // Compute interaction intensity
    final interactionIntensity = _computeInteractionIntensity(
      tapRateNorm,
      keystrokeRateNorm,
      scrollVelocityNorm,
      idleRatio,
    );

    // Prepare features for MLP (12 features as per spec)
    final mlpInput = [
      tapRateNorm,
      keystrokeRateNorm,
      scrollVelocityNorm,
      idleRatio,
      switchRateNorm,
      burstiness,
      sessionFragmentation,
      notifRateNorm,
      notifOpenRateNorm,
      notificationScore,
      typingCadenceStability,
      scrollCadenceStability,
    ];

    // Run MLP inference
    final mlpOutput = _mlp.infer(mlpInput);
    final distractionScore = mlpOutput[0];
    final focusHint = mlpOutput[1];

    return BehaviorWindowFeatures(
      tapRateNorm: tapRateNorm,
      keystrokeRateNorm: keystrokeRateNorm,
      scrollVelocityNorm: scrollVelocityNorm,
      idleRatio: idleRatio,
      switchRateNorm: switchRateNorm,
      burstiness: burstiness,
      sessionFragmentation: sessionFragmentation,
      notifRateNorm: notifRateNorm,
      notifOpenRateNorm: notifOpenRateNorm,
      notificationScore: notificationScore,
      typingCadenceStability: typingCadenceStability,
      scrollCadenceStability: scrollCadenceStability,
      interactionIntensity: interactionIntensity,
      distractionScore: distractionScore,
      focusHint: focusHint,
      windowType: windowType,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Normalize a value to 0.0-1.0 range using max value.
  double _normalize(double value, double maxValue) {
    return (value / maxValue).clamp(0.0, 1.0);
  }

  /// Count events of specific types.
  int _countEvents(
    List<BehaviorEvent> events,
    dynamic eventTypes,
  ) {
    if (eventTypes is BehaviorEventType) {
      return events.where((e) => e.type == eventTypes).length;
    } else if (eventTypes is List<BehaviorEventType>) {
      return events.where((e) => eventTypes.contains(e.type)).length;
    }
    return 0;
  }

  /// Filter events by type(s).
  List<BehaviorEvent> _filterEvents(
    List<BehaviorEvent> events,
    dynamic eventTypes,
  ) {
    if (eventTypes is BehaviorEventType) {
      return events.where((e) => e.type == eventTypes).toList();
    } else if (eventTypes is List<BehaviorEventType>) {
      return events.where((e) => eventTypes.contains(e.type)).toList();
    }
    return [];
  }

  /// Compute average normalized scroll velocity.
  double _computeAverageScrollVelocity(List<BehaviorEvent> scrollEvents) {
    if (scrollEvents.isEmpty) {
      return 0.0;
    }

    double totalVelocity = 0.0;
    int count = 0;

    for (final event in scrollEvents) {
      // Try to get velocity from payload (could be int or double)
      final velocityValue = event.payload['velocity'];
      if (velocityValue != null) {
        final velocity = (velocityValue is num)
            ? velocityValue.toDouble()
            : (velocityValue as double?);
        if (velocity != null && velocity > 0) {
          totalVelocity += velocity;
          count++;
        }
      }
    }

    if (count == 0) {
      return 0.0;
    }
    final avgVelocity = totalVelocity / count;
    return _normalize(avgVelocity, maxScrollVelocity);
  }

  /// Compute idle ratio (proportion of time spent idle).
  double _computeIdleRatio(List<BehaviorEvent> idleEvents, int windowMs) {
    if (idleEvents.isEmpty) return 0.0;

    double totalIdleTime = 0.0;
    for (final event in idleEvents) {
      final idleSeconds = event.payload['idle_seconds'] as double? ?? 0.0;
      totalIdleTime += idleSeconds * 1000; // Convert to milliseconds
    }

    return (totalIdleTime / windowMs).clamp(0.0, 1.0);
  }

  /// Compute burstiness (activity clustering metric).
  /// Formula: (σ - μ)/(σ + μ) remapped to [0,1]
  double _computeBurstiness(List<BehaviorEvent> events, int windowMs) {
    if (events.length < 2) return 0.0;

    // Compute inter-event intervals
    final intervals = <int>[];
    for (int i = 1; i < events.length; i++) {
      intervals.add(events[i].timestamp - events[i - 1].timestamp);
    }

    if (intervals.isEmpty) return 0.0;

    // Compute mean (μ) and standard deviation (σ)
    final mean = intervals.reduce((a, b) => a + b) / intervals.length;
    if (mean == 0) return 0.0;

    final variance =
        intervals.map((i) => (i - mean) * (i - mean)).reduce((a, b) => a + b) /
            intervals.length;
    final stdDev = variance > 0 ? math.sqrt(variance) : 0.0;

    // Burstiness formula: (σ - μ)/(σ + μ)
    // This ranges from -1 (regular) to +1 (bursty)
    // Remap to [0, 1]: (burstiness + 1) / 2
    final burstinessRaw = (stdDev - mean) / (stdDev + mean);
    return ((burstinessRaw + 1.0) / 2.0).clamp(0.0, 1.0);
  }

  /// Compute session fragmentation index.
  double _computeFragmentation(List<BehaviorEvent> events, int windowMs) {
    if (events.isEmpty) return 0.0;

    // Count interruptions (idle gaps, app switches)
    final interruptions = _countEvents(events, [
      BehaviorEventType.idleGap,
      BehaviorEventType.microIdle,
      BehaviorEventType.midIdle,
      BehaviorEventType.taskDropIdle,
      BehaviorEventType.appSwitch,
    ]);

    // Normalize by window duration (more interruptions = higher fragmentation)
    final windowMinutes = windowMs / (60 * 1000.0);
    final fragmentation =
        interruptions / (windowMinutes * 10.0); // 10 per minute max

    return fragmentation.clamp(0.0, 1.0);
  }

  /// Compute typing cadence stability (consistency of typing rhythm).
  double _computeTypingCadenceStability(
    List<BehaviorEvent> events,
    int windowMs,
  ) {
    final typingEvents = _filterEvents(events, [
      BehaviorEventType.typingCadence,
      BehaviorEventType.typingBurst,
    ]);

    if (typingEvents.length < 2) {
      return 0.0;
    }

    // Extract inter-key latencies (could be int or double from native)
    final latencies = <double>[];
    for (final event in typingEvents) {
      final latencyValue = event.payload['inter_key_latency'];
      if (latencyValue != null) {
        final latency = (latencyValue is num)
            ? latencyValue.toDouble()
            : (latencyValue as double?);
        if (latency != null && latency > 0) {
          latencies.add(latency);
        }
      }
    }

    if (latencies.length < 2) {
      return 0.0;
    }

    // Compute coefficient of variation (lower CV = more stable)
    final mean = latencies.reduce((a, b) => a + b) / latencies.length;
    final variance =
        latencies.map((l) => (l - mean) * (l - mean)).reduce((a, b) => a + b) /
            latencies.length;
    final stdDev = variance > 0 ? math.sqrt(variance) : 0.0;
    final cv = mean > 0 ? stdDev / mean : 0.0;

    // Stability formula: exp(-α * cv_key)
    // Using α = 1.0 for simplicity (can be tuned)
    const alpha = 1.0;
    return math.exp(-alpha * cv).clamp(0.0, 1.0);
  }

  /// Compute scroll cadence stability (consistency of scroll rhythm).
  /// Formula: exp(-β * cv_scroll)
  double _computeScrollCadenceStability(
    List<BehaviorEvent> events,
    int windowMs,
  ) {
    final scrollEvents =
        _filterEvents(events, BehaviorEventType.scrollVelocity);

    if (scrollEvents.length < 2) return 0.0;

    // Extract scroll intervals (time between scrolls)
    final intervals = <int>[];
    for (int i = 1; i < scrollEvents.length; i++) {
      intervals.add(scrollEvents[i].timestamp - scrollEvents[i - 1].timestamp);
    }

    if (intervals.length < 2) return 0.0;

    // Compute coefficient of variation
    final mean = intervals.reduce((a, b) => a + b) / intervals.length;
    if (mean == 0) return 0.0;

    final variance =
        intervals.map((i) => (i - mean) * (i - mean)).reduce((a, b) => a + b) /
            intervals.length;
    final stdDev = variance > 0 ? math.sqrt(variance) : 0.0;
    final cv = mean > 0 ? stdDev / mean : 0.0;

    // Stability formula: exp(-β * cv_scroll)
    // Using β = 1.0 for simplicity (can be tuned)
    const beta = 1.0;
    return math.exp(-beta * cv).clamp(0.0, 1.0);
  }

  /// Compute interaction intensity.
  /// Formula: σ(w1*tap + w2*key + w3*scroll - w4*idle_ratio)
  /// Using sigmoid activation and weights from spec
  double _computeInteractionIntensity(
    double tapRateNorm,
    double keystrokeRateNorm,
    double scrollVelocityNorm,
    double idleRatio,
  ) {
    // Weights (can be tuned based on domain knowledge)
    const w1 = 0.3; // tap weight
    const w2 = 0.3; // keystroke weight
    const w3 = 0.2; // scroll weight
    const w4 = 0.2; // idle penalty weight

    // Compute weighted sum
    final weightedSum = w1 * tapRateNorm +
        w2 * keystrokeRateNorm +
        w3 * scrollVelocityNorm -
        w4 * idleRatio;

    // Apply sigmoid activation: σ(x) = 1 / (1 + exp(-x))
    // Scale input to reasonable range for sigmoid
    final sigmoidInput = weightedSum * 5.0; // Scale factor
    final intensity = 1.0 / (1.0 + math.exp(-sigmoidInput));

    return intensity.clamp(0.0, 1.0);
  }
}

/// Simple on-device MLP for behavior inference.
///
/// Tiny neural network that takes 12 normalized features and outputs
/// distraction_score and focus_hint.
class BehaviorMLP {
  /// Simple feedforward inference (placeholder implementation).
  ///
  /// In production, this would be a trained model loaded from assets.
  /// For now, uses a simple weighted combination of features.
  /// Input features: [tap_rate, keystroke_rate, scroll_velocity, idle_ratio,
  ///                  switch_rate, burstiness, fragmentation, notif_rate,
  ///                  notif_open_rate, notification_score, typing_stability,
  ///                  scroll_stability]
  List<double> infer(List<double> features) {
    if (features.length != 12) {
      return [0.0, 0.0];
    }

    // Simple heuristic-based inference (replace with actual MLP)
    // Higher values = more distraction
    final distractionScore = (features[0] * 0.08 + // tap_rate
            features[1] * 0.08 + // keystroke_rate
            features[2] * 0.04 + // scroll_velocity
            features[3] * 0.18 + // idle_ratio (high idle = distracted)
            features[4] * 0.22 + // switch_rate (high switching = distracted)
            features[5] * 0.08 + // burstiness
            features[6] * 0.12 + // fragmentation
            features[7] * 0.04 + // notif_rate
            features[8] * 0.03 + // notif_open_rate
            features[9] * 0.05 + // notification_score
            (1.0 - features[10]) * 0.05 + // inverse of typing stability
            (1.0 - features[11]) * 0.03 // inverse of scroll stability
        )
        .clamp(0.0, 1.0);

    // Focus hint is inverse of distraction (with some smoothing)
    final focusHint = (1.0 - distractionScore * 0.8).clamp(0.0, 1.0);

    return [distractionScore, focusHint];
  }
}
