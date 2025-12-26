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
  final String state; // e.g., "walking", "stationary", "running"
  final String mlModel; // e.g., "motion_state_predictor_v0.1"
  final double confidence; // 0.0 to 1.0

  MotionState({
    required this.state,
    required this.mlModel,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'state': state,
        'ml_model': mlModel,
        'confidence': confidence,
      };

  factory MotionState.fromJson(Map<String, dynamic> json) {
    return MotionState(
      state: json['state'] as String? ?? 'unknown',
      mlModel: json['ml_model'] as String? ?? 'unknown',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
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
    );
  }

  /// Get session duration in milliseconds.
  int get durationMs {
    final start = DateTime.parse(startAt);
    final end = DateTime.parse(endAt);
    return end.difference(start).inMilliseconds;
  }
}
