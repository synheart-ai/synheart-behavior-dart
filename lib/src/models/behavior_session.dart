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

/// Motion state information.
class MotionState {
  final List<String>
      state; // Array of states for each window, e.g., ["walking", "sitting", "standing", "sitting"]
  final String majorState; // Most common state, e.g., "sitting"
  final double majorStatePct; // Percentage of major state, e.g., 0.5
  final String mlModel; // e.g., "motion_state_svc_classifier_v0.1"
  final double confidence; // 0.0 to 1.0

  MotionState({
    required this.state,
    required this.majorState,
    required this.majorStatePct,
    required this.mlModel,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'state': state,
        'major_state': majorState,
        'major_state_pct': majorStatePct,
        'ml_model': mlModel,
        'confidence': confidence,
      };

  factory MotionState.fromJson(Map<String, dynamic> json) {
    return MotionState(
      state:
          json['state'] != null ? List<String>.from(json['state'] as List) : [],
      majorState: json['major_state'] as String? ?? 'unknown',
      majorStatePct: (json['major_state_pct'] as num?)?.toDouble() ?? 0.0,
      mlModel:
          json['ml_model'] as String? ?? 'motion_state_svc_classifier_v0.1',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Raw motion data point (accelerometer and gyroscope arrays per timestamp).
class MotionDataPoint {
  /// ISO 8601 timestamp for this data point (5-second window)
  final String timestamp;

  /// ML features extracted from raw sensor data (561 features)
  /// Feature names match the format from features.txt (e.g., "tBodyAcc-mean()-X")
  final Map<String, double> features;

  MotionDataPoint({
    required this.timestamp,
    required this.features,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'features': features,
      };

  factory MotionDataPoint.fromJson(Map<String, dynamic> json) {
    return MotionDataPoint(
      timestamp: json['timestamp'] as String,
      features: json['features'] != null
          ? Map<String, double>.from(
              (json['features'] as Map).map(
                (key, value) => MapEntry(
                  key.toString(),
                  (value as num).toDouble(),
                ),
              ),
            )
          : {},
    );
  }
}

/// Device context information.
class DeviceContext {
  final double
      avgScreenBrightness; // Average of start and end brightness (0.0 to 1.0)
  final String startOrientation; // "portrait" or "landscape"
  final int orientationChanges; // Number of orientation changes during session

  DeviceContext({
    required this.avgScreenBrightness,
    required this.startOrientation,
    required this.orientationChanges,
  });

  Map<String, dynamic> toJson() => {
        'avg_screen_brightness': avgScreenBrightness,
        'start_orientation': startOrientation,
        'orientation_changes': orientationChanges,
      };

  factory DeviceContext.fromJson(Map<String, dynamic> json) {
    return DeviceContext(
      avgScreenBrightness:
          (json['avg_screen_brightness'] as num?)?.toDouble() ?? 0.0,
      startOrientation: json['start_orientation'] as String? ?? 'portrait',
      orientationChanges: (json['orientation_changes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Activity summary for the session.
class ActivitySummary {
  final int totalEvents;
  final int appSwitchCount;

  ActivitySummary({
    required this.totalEvents,
    required this.appSwitchCount,
  });

  Map<String, dynamic> toJson() => {
        'total_events': totalEvents,
        'app_switch_count': appSwitchCount,
      };

  factory ActivitySummary.fromJson(Map<String, dynamic> json) {
    return ActivitySummary(
      totalEvents: (json['total_events'] as num?)?.toInt() ?? 0,
      appSwitchCount: (json['app_switch_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Deep focus block period.
class DeepFocusBlock {
  final String startAt; // ISO 8601 timestamp
  final String endAt; // ISO 8601 timestamp
  final int durationMs; // Duration in milliseconds

  DeepFocusBlock({
    required this.startAt,
    required this.endAt,
    required this.durationMs,
  });

  Map<String, dynamic> toJson() => {
        'start_at': startAt,
        'end_at': endAt,
        'duration_ms': durationMs,
      };

  factory DeepFocusBlock.fromJson(Map<String, dynamic> json) {
    return DeepFocusBlock(
      startAt: json['start_at'] as String? ?? '',
      endAt: json['end_at'] as String? ?? '',
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Behavioral metrics for the session.
class BehavioralMetrics {
  final double interactionIntensity;
  final double taskSwitchRate;
  final int taskSwitchCost; // in milliseconds
  final double idleTimeRatio;
  final double activeTimeRatio;
  final double notificationLoad;
  final double burstiness;
  final double behavioralDistractionScore;
  final double focusHint;
  final double fragmentedIdleRatio;
  final double scrollJitterRate;
  final List<DeepFocusBlock> deepFocusBlocks;

  BehavioralMetrics({
    required this.interactionIntensity,
    required this.taskSwitchRate,
    required this.taskSwitchCost,
    required this.idleTimeRatio,
    required this.activeTimeRatio,
    required this.notificationLoad,
    required this.burstiness,
    required this.behavioralDistractionScore,
    required this.focusHint,
    required this.fragmentedIdleRatio,
    required this.scrollJitterRate,
    required this.deepFocusBlocks,
  });

  Map<String, dynamic> toJson() => {
        'interaction_intensity': interactionIntensity,
        'task_switch_rate': taskSwitchRate,
        'task_switch_cost': taskSwitchCost,
        'idle_time_ratio': idleTimeRatio,
        'active_time_ratio': activeTimeRatio,
        'notification_load': notificationLoad,
        'burstiness': burstiness,
        'behavioral_distraction_score': behavioralDistractionScore,
        'focus_hint': focusHint,
        'fragmented_idle_ratio': fragmentedIdleRatio,
        'scroll_jitter_rate': scrollJitterRate,
        'deep_focus_blocks': deepFocusBlocks.map((b) => b.toJson()).toList(),
      };

  factory BehavioralMetrics.fromJson(Map<String, dynamic> json) {
    return BehavioralMetrics(
      interactionIntensity:
          (json['interaction_intensity'] as num?)?.toDouble() ?? 0.0,
      taskSwitchRate: (json['task_switch_rate'] as num?)?.toDouble() ?? 0.0,
      taskSwitchCost: (json['task_switch_cost'] as num?)?.toInt() ?? 0,
      idleTimeRatio: (json['idle_time_ratio'] as num?)?.toDouble() ?? 0.0,
      activeTimeRatio: (json['active_time_ratio'] as num?)?.toDouble() ?? 0.0,
      notificationLoad: (json['notification_load'] as num?)?.toDouble() ?? 0.0,
      burstiness: (json['burstiness'] as num?)?.toDouble() ?? 0.0,
      behavioralDistractionScore:
          (json['behavioral_distraction_score'] as num?)?.toDouble() ?? 0.0,
      focusHint: (json['focus_hint'] as num?)?.toDouble() ?? 0.0,
      fragmentedIdleRatio:
          (json['fragmented_idle_ratio'] as num?)?.toDouble() ?? 0.0,
      scrollJitterRate: (json['scroll_jitter_rate'] as num?)?.toDouble() ?? 0.0,
      deepFocusBlocks: (json['deep_focus_blocks'] as List<dynamic>?)
              ?.map((e) =>
                  DeepFocusBlock.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
    );
  }
}

/// Notification summary for the session.
class NotificationSummary {
  final int notificationCount;
  final int notificationIgnored;
  final double notificationIgnoreRate;
  final double notificationClusteringIndex;
  final int callCount;
  final int callIgnored;

  NotificationSummary({
    required this.notificationCount,
    required this.notificationIgnored,
    required this.notificationIgnoreRate,
    required this.notificationClusteringIndex,
    required this.callCount,
    required this.callIgnored,
  });

  Map<String, dynamic> toJson() => {
        'notification_count': notificationCount,
        'notification_ignored': notificationIgnored,
        'notification_ignore_rate': notificationIgnoreRate,
        'notification_clustering_index': notificationClusteringIndex,
        'call_count': callCount,
        'call_ignored': callIgnored,
      };

  factory NotificationSummary.fromJson(Map<String, dynamic> json) {
    return NotificationSummary(
      notificationCount: (json['notification_count'] as num?)?.toInt() ?? 0,
      notificationIgnored: (json['notification_ignored'] as num?)?.toInt() ?? 0,
      notificationIgnoreRate:
          (json['notification_ignore_rate'] as num?)?.toDouble() ?? 0.0,
      notificationClusteringIndex:
          (json['notification_clustering_index'] as num?)?.toDouble() ?? 0.0,
      callCount: (json['call_count'] as num?)?.toInt() ?? 0,
      callIgnored: (json['call_ignored'] as num?)?.toInt() ?? 0,
    );
  }
}

/// System state information.
class SystemState {
  final bool internetState;
  final bool doNotDisturb;
  final bool charging;

  SystemState({
    required this.internetState,
    required this.doNotDisturb,
    required this.charging,
  });

  Map<String, dynamic> toJson() => {
        'internet_state': internetState,
        'do_not_disturb': doNotDisturb,
        'charging': charging,
      };

  factory SystemState.fromJson(Map<String, dynamic> json) {
    return SystemState(
      internetState: json['internet_state'] as bool? ?? true,
      doNotDisturb: json['do_not_disturb'] as bool? ?? false,
      charging: json['charging'] as bool? ?? false,
    );
  }
}

/// Typing metrics for a single typing session (keyboard open to close).
class TypingMetrics {
  final String startAt; // ISO 8601 timestamp
  final String endAt; // ISO 8601 timestamp
  final int duration; // Duration in seconds
  final bool deepTyping; // Whether this is a deep typing session
  final int typingTapCount; // Total number of keyboard tap events
  final double typingSpeed; // Tap events per second
  final double meanInterTapIntervalMs; // Average time between taps
  final double typingCadenceVariability; // Variability in timing between taps
  final double
      typingCadenceStability; // Normalized rhythmic consistency (0.0-1.0)
  final int typingGapCount; // Number of pauses exceeding threshold
  final double typingGapRatio; // Proportion of intervals that are gaps
  final double typingBurstiness; // Dispersion of inter-tap intervals
  final double typingActivityRatio; // Fraction of window with active typing
  final double typingInteractionIntensity; // Composite engagement measure

  TypingMetrics({
    required this.startAt,
    required this.endAt,
    required this.duration,
    required this.deepTyping,
    required this.typingTapCount,
    required this.typingSpeed,
    required this.meanInterTapIntervalMs,
    required this.typingCadenceVariability,
    required this.typingCadenceStability,
    required this.typingGapCount,
    required this.typingGapRatio,
    required this.typingBurstiness,
    required this.typingActivityRatio,
    required this.typingInteractionIntensity,
  });

  Map<String, dynamic> toJson() => {
        'start_at': startAt,
        'end_at': endAt,
        'duration': duration,
        'deep_typing': deepTyping,
        'typing_tap_count': typingTapCount,
        'typing_speed': typingSpeed,
        'mean_inter_tap_interval_ms': meanInterTapIntervalMs,
        'typing_cadence_variability': typingCadenceVariability,
        'typing_cadence_stability': typingCadenceStability,
        'typing_gap_count': typingGapCount,
        'typing_gap_ratio': typingGapRatio,
        'typing_burstiness': typingBurstiness,
        'typing_activity_ratio': typingActivityRatio,
        'typing_interaction_intensity': typingInteractionIntensity,
      };

  factory TypingMetrics.fromJson(Map<String, dynamic> json) {
    return TypingMetrics(
      startAt: json['start_at'] as String? ?? '',
      endAt: json['end_at'] as String? ?? '',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      deepTyping: json['deep_typing'] as bool? ?? false,
      typingTapCount: (json['typing_tap_count'] as num?)?.toInt() ?? 0,
      typingSpeed: (json['typing_speed'] as num?)?.toDouble() ?? 0.0,
      meanInterTapIntervalMs:
          (json['mean_inter_tap_interval_ms'] as num?)?.toDouble() ?? 0.0,
      typingCadenceVariability:
          (json['typing_cadence_variability'] as num?)?.toDouble() ?? 0.0,
      typingCadenceStability:
          (json['typing_cadence_stability'] as num?)?.toDouble() ?? 0.0,
      typingGapCount: (json['typing_gap_count'] as num?)?.toInt() ?? 0,
      typingGapRatio: (json['typing_gap_ratio'] as num?)?.toDouble() ?? 0.0,
      typingBurstiness: (json['typing_burstiness'] as num?)?.toDouble() ?? 0.0,
      typingActivityRatio:
          (json['typing_activity_ratio'] as num?)?.toDouble() ?? 0.0,
      typingInteractionIntensity:
          (json['typing_interaction_intensity'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Typing session summary aggregated across all typing sessions in the app session.
class TypingSessionSummary {
  final int typingSessionCount; // Number of distinct typing sessions
  final double averageKeystrokesPerSession; // Average taps per typing session
  final double
      averageTypingSessionDuration; // Average duration per typing session (seconds)
  final double averageTypingSpeed; // Average typing speed across all sessions
  final double averageTypingGap; // Average gap duration between keystrokes
  final double
      averageInterTapInterval; // Average inter-tap interval across all sessions
  final double typingCadenceStability; // Overall cadence stability
  final double burstinessOfTyping; // Overall burstiness measure
  final int totalTypingDuration; // Total time spent typing (seconds)
  final double activeTypingRatio; // Ratio of typing time to total session time
  final double
      typingContributionToInteractionIntensity; // Typing's contribution to overall intensity
  final int deepTypingBlocks; // Number of deep typing blocks
  final double typingFragmentation; // Measure of typing fragmentation
  final List<TypingMetrics>
      individualTypingSessions; // List of individual typing sessions

  TypingSessionSummary({
    required this.typingSessionCount,
    required this.averageKeystrokesPerSession,
    required this.averageTypingSessionDuration,
    required this.averageTypingSpeed,
    required this.averageTypingGap,
    required this.averageInterTapInterval,
    required this.typingCadenceStability,
    required this.burstinessOfTyping,
    required this.totalTypingDuration,
    required this.activeTypingRatio,
    required this.typingContributionToInteractionIntensity,
    required this.deepTypingBlocks,
    required this.typingFragmentation,
    required this.individualTypingSessions,
  });

  Map<String, dynamic> toJson() => {
        'typing_session_count': typingSessionCount,
        'average_keystrokes_per_session': averageKeystrokesPerSession,
        'average_typing_session_duration': averageTypingSessionDuration,
        'average_typing_speed': averageTypingSpeed,
        'average_typing_gap': averageTypingGap,
        'average_inter_tap_interval': averageInterTapInterval,
        'typing_cadence_stability': typingCadenceStability,
        'burstiness_of_typing': burstinessOfTyping,
        'total_typing_duration': totalTypingDuration,
        'active_typing_ratio': activeTypingRatio,
        'typing_contribution_to_interaction_intensity':
            typingContributionToInteractionIntensity,
        'deep_typing_blocks': deepTypingBlocks,
        'typing_fragmentation': typingFragmentation,
        'typing_metrics':
            individualTypingSessions.map((m) => m.toJson()).toList(),
      };

  factory TypingSessionSummary.fromJson(Map<String, dynamic> json) {
    return TypingSessionSummary(
      typingSessionCount: (json['typing_session_count'] as num?)?.toInt() ?? 0,
      averageKeystrokesPerSession:
          (json['average_keystrokes_per_session'] as num?)?.toDouble() ?? 0.0,
      averageTypingSessionDuration:
          (json['average_typing_session_duration'] as num?)?.toDouble() ?? 0.0,
      averageTypingSpeed:
          (json['average_typing_speed'] as num?)?.toDouble() ?? 0.0,
      averageTypingGap: (json['average_typing_gap'] as num?)?.toDouble() ?? 0.0,
      averageInterTapInterval:
          (json['average_inter_tap_interval'] as num?)?.toDouble() ?? 0.0,
      typingCadenceStability:
          (json['typing_cadence_stability'] as num?)?.toDouble() ?? 0.0,
      burstinessOfTyping:
          (json['burstiness_of_typing'] as num?)?.toDouble() ?? 0.0,
      totalTypingDuration:
          (json['total_typing_duration'] as num?)?.toInt() ?? 0,
      activeTypingRatio:
          (json['active_typing_ratio'] as num?)?.toDouble() ?? 0.0,
      typingContributionToInteractionIntensity:
          (json['typing_contribution_to_interaction_intensity'] as num?)
                  ?.toDouble() ??
              0.0,
      deepTypingBlocks: (json['deep_typing_blocks'] as num?)?.toInt() ?? 0,
      typingFragmentation:
          (json['typing_fragmentation'] as num?)?.toDouble() ?? 0.0,
      individualTypingSessions: json['typing_metrics'] != null
          ? (json['typing_metrics'] as List<dynamic>)
              .map((e) =>
                  TypingMetrics.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList()
          : [],
    );
  }
}

/// Summary statistics for a completed behavioral session.
class BehaviorSessionSummary {
  /// Unique session ID.
  final String sessionId;

  /// Start timestamp in ISO 8601 format.
  final String startAt;

  /// End timestamp in ISO 8601 format.
  final String endAt;

  /// Whether this is a micro session (< 30 seconds).
  final bool microSession;

  /// OS version string (e.g., "Android 12.3", "iOS 17.0").
  final String os;

  /// App identifier.
  final String? appId;

  /// App name (display name).
  final String? appName;

  /// Session spacing in milliseconds (time since last app use).
  final int sessionSpacing;

  /// Motion state information.
  final MotionState? motionState;

  /// Device context information.
  final DeviceContext deviceContext;

  /// Activity summary.
  final ActivitySummary activitySummary;

  /// Behavioral metrics.
  final BehavioralMetrics behavioralMetrics;

  /// Notification summary.
  final NotificationSummary notificationSummary;

  /// System state.
  final SystemState systemState;

  /// Typing session summary.
  final TypingSessionSummary? typingSessionSummary;

  /// Raw motion data (accelerometer and gyroscope arrays per timestamp).
  final List<MotionDataPoint>? motionData;

  BehaviorSessionSummary({
    required this.sessionId,
    required this.startAt,
    required this.endAt,
    required this.microSession,
    required this.os,
    this.appId,
    this.appName,
    required this.sessionSpacing,
    this.motionState,
    required this.deviceContext,
    required this.activitySummary,
    required this.behavioralMetrics,
    required this.notificationSummary,
    required this.systemState,
    this.typingSessionSummary,
    this.motionData,
  });

  /// Convert to the new session behavior format.
  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'start_at': startAt,
        'end_at': endAt,
        'micro_session': microSession,
        'OS': os,
        if (appId != null) 'app_id': appId,
        if (appName != null) 'app_name': appName,
        'session_spacing': sessionSpacing,
        if (motionState != null) 'motion_state': motionState!.toJson(),
        'device_context': deviceContext.toJson(),
        'activity_summary': activitySummary.toJson(),
        'behavioral_metrics': behavioralMetrics.toJson(),
        'notification_summary': notificationSummary.toJson(),
        'system_state': systemState.toJson(),
        if (typingSessionSummary != null)
          'typing_session_summary': typingSessionSummary!.toJson(),
        if (motionData != null)
          'motion_data': motionData!.map((point) => point.toJson()).toList(),
      };

  factory BehaviorSessionSummary.fromJson(Map<String, dynamic> json) {
    return BehaviorSessionSummary(
      sessionId: json['session_id'] as String,
      startAt: json['start_at'] as String? ??
          DateTime.fromMillisecondsSinceEpoch(
                  json['start_timestamp'] as int? ?? 0)
              .toUtc()
              .toIso8601String(),
      endAt: json['end_at'] as String? ??
          DateTime.fromMillisecondsSinceEpoch(
                  json['end_timestamp'] as int? ?? 0)
              .toUtc()
              .toIso8601String(),
      microSession: json['micro_session'] as bool? ?? false,
      os: json['OS'] as String? ?? json['os'] as String? ?? 'Unknown',
      appId: json['app_id'] as String?,
      appName: json['app_name'] as String?,
      sessionSpacing: (json['session_spacing'] as num?)?.toInt() ?? 0,
      motionState: json['motion_state'] != null
          ? MotionState.fromJson(
              Map<String, dynamic>.from(json['motion_state'] as Map))
          : null,
      deviceContext: DeviceContext.fromJson(
          Map<String, dynamic>.from(json['device_context'] as Map? ?? {})),
      activitySummary: ActivitySummary.fromJson(
          Map<String, dynamic>.from(json['activity_summary'] as Map? ?? {})),
      behavioralMetrics: BehavioralMetrics.fromJson(
          Map<String, dynamic>.from(json['behavioral_metrics'] as Map? ?? {})),
      notificationSummary: NotificationSummary.fromJson(
          Map<String, dynamic>.from(
              json['notification_summary'] as Map? ?? {})),
      systemState: SystemState.fromJson(
          Map<String, dynamic>.from(json['system_state'] as Map? ?? {})),
      typingSessionSummary: json['typing_session_summary'] != null
          ? TypingSessionSummary.fromJson(
              Map<String, dynamic>.from(json['typing_session_summary'] as Map))
          : null,
      motionData: json['motion_data'] != null
          ? (json['motion_data'] as List<dynamic>)
              .map((e) =>
                  MotionDataPoint.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList()
          : null,
    );
  }

  /// Get session duration in milliseconds.
  int get durationMs {
    final start = DateTime.parse(startAt);
    final end = DateTime.parse(endAt);
    return end.difference(start).inMilliseconds;
  }
}
