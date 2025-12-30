import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_behavior/synheart_behavior.dart';

void main() {
  group('BehaviorSession', () {
    test('creates with required fields', () {
      Future<BehaviorSessionSummary> mockCallback(String sessionId) async {
        return BehaviorSessionSummary(
          sessionId: sessionId,
          startAt: '2025-01-01T10:00:00.000Z',
          endAt: '2025-01-01T10:00:01.000Z',
          microSession: false,
          os: 'Android 12',
          sessionSpacing: 0,
          deviceContext: DeviceContext(
            avgScreenBrightness: 0.5,
            startOrientation: 'portrait',
            orientationChanges: 0,
          ),
          activitySummary: ActivitySummary(
            totalEvents: 0,
            appSwitchCount: 0,
          ),
          behavioralMetrics: BehavioralMetrics(
            interactionIntensity: 0.0,
            taskSwitchRate: 0.0,
            taskSwitchCost: 0,
            idleTimeRatio: 0.0,
            activeTimeRatio: 0.0,
            notificationLoad: 0.0,
            burstiness: 0.0,
            behavioralDistractionScore: 0.0,
            focusHint: 0.0,
            fragmentedIdleRatio: 0.0,
            scrollJitterRate: 0.0,
            deepFocusBlocks: [],
          ),
          notificationSummary: NotificationSummary(
            notificationCount: 0,
            notificationIgnored: 0,
            notificationIgnoreRate: 0.0,
            notificationClusteringIndex: 0.0,
            callCount: 0,
            callIgnored: 0,
          ),
          systemState: SystemState(
            internetState: true,
            doNotDisturb: false,
            charging: false,
          ),
        );
      }

      final session = BehaviorSession(
        sessionId: 'test-session',
        startTimestamp: 1000,
        endCallback: mockCallback,
      );

      expect(session.sessionId, 'test-session');
      expect(session.startTimestamp, 1000);
    });

    test('currentDuration calculates correctly', () async {
      Future<BehaviorSessionSummary> mockCallback(String sessionId) async {
        return BehaviorSessionSummary(
          sessionId: sessionId,
          startAt: '2025-01-01T10:00:00.000Z',
          endAt: '2025-01-01T10:00:01.000Z',
          microSession: false,
          os: 'Android 12',
          sessionSpacing: 0,
          deviceContext: DeviceContext(
            avgScreenBrightness: 0.5,
            startOrientation: 'portrait',
            orientationChanges: 0,
          ),
          activitySummary: ActivitySummary(
            totalEvents: 0,
            appSwitchCount: 0,
          ),
          behavioralMetrics: BehavioralMetrics(
            interactionIntensity: 0.0,
            taskSwitchRate: 0.0,
            taskSwitchCost: 0,
            idleTimeRatio: 0.0,
            activeTimeRatio: 0.0,
            notificationLoad: 0.0,
            burstiness: 0.0,
            behavioralDistractionScore: 0.0,
            focusHint: 0.0,
            fragmentedIdleRatio: 0.0,
            scrollJitterRate: 0.0,
            deepFocusBlocks: [],
          ),
          notificationSummary: NotificationSummary(
            notificationCount: 0,
            notificationIgnored: 0,
            notificationIgnoreRate: 0.0,
            notificationClusteringIndex: 0.0,
            callCount: 0,
            callIgnored: 0,
          ),
          systemState: SystemState(
            internetState: true,
            doNotDisturb: false,
            charging: false,
          ),
        );
      }

      final startTime = DateTime.now().millisecondsSinceEpoch;
      final session = BehaviorSession(
        sessionId: 'test-session',
        startTimestamp: startTime,
        endCallback: mockCallback,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      final duration = session.currentDuration;
      expect(duration, greaterThanOrEqualTo(100));
    });

    test('end() calls callback and returns summary', () async {
      BehaviorSessionSummary? capturedSummary;

      Future<BehaviorSessionSummary> mockCallback(String sessionId) async {
        capturedSummary = BehaviorSessionSummary(
          sessionId: sessionId,
          startAt: '2025-01-01T10:00:00.000Z',
          endAt: '2025-01-01T10:00:01.000Z',
          microSession: false,
          os: 'Android 12',
          sessionSpacing: 0,
          deviceContext: DeviceContext(
            avgScreenBrightness: 0.5,
            startOrientation: 'portrait',
            orientationChanges: 0,
          ),
          activitySummary: ActivitySummary(
            totalEvents: 10,
            appSwitchCount: 2,
          ),
          behavioralMetrics: BehavioralMetrics(
            interactionIntensity: 0.5,
            taskSwitchRate: 0.2,
            taskSwitchCost: 100,
            idleTimeRatio: 0.1,
            activeTimeRatio: 0.9,
            notificationLoad: 0.0,
            burstiness: 0.3,
            behavioralDistractionScore: 0.2,
            focusHint: 0.8,
            fragmentedIdleRatio: 0.1,
            scrollJitterRate: 0.05,
            deepFocusBlocks: [],
          ),
          notificationSummary: NotificationSummary(
            notificationCount: 0,
            notificationIgnored: 0,
            notificationIgnoreRate: 0.0,
            notificationClusteringIndex: 0.0,
            callCount: 0,
            callIgnored: 0,
          ),
          systemState: SystemState(
            internetState: true,
            doNotDisturb: false,
            charging: false,
          ),
        );
        return capturedSummary!;
      }

      final session = BehaviorSession(
        sessionId: 'test-session',
        startTimestamp: 1000,
        endCallback: mockCallback,
      );

      final summary = await session.end();

      expect(summary, isNotNull);
      expect(summary.sessionId, 'test-session');
      expect(summary.durationMs, 1000);
      expect(summary.activitySummary.totalEvents, 10);
    });
  });

  group('BehaviorSessionSummary', () {
    test('creates with required fields', () {
      final summary = BehaviorSessionSummary(
        sessionId: 'test-session',
        startAt: '2025-01-01T10:00:00.000Z',
        endAt: '2025-01-01T10:00:01.000Z',
        microSession: false,
        os: 'Android 12',
        sessionSpacing: 0,
        deviceContext: DeviceContext(
          avgScreenBrightness: 0.5,
          startOrientation: 'portrait',
          orientationChanges: 0,
        ),
        activitySummary: ActivitySummary(
          totalEvents: 0,
          appSwitchCount: 0,
        ),
        behavioralMetrics: BehavioralMetrics(
          interactionIntensity: 0.0,
          taskSwitchRate: 0.0,
          taskSwitchCost: 0,
          idleTimeRatio: 0.0,
          activeTimeRatio: 0.0,
          notificationLoad: 0.0,
          burstiness: 0.0,
          behavioralDistractionScore: 0.0,
          focusHint: 0.0,
          fragmentedIdleRatio: 0.0,
          scrollJitterRate: 0.0,
          deepFocusBlocks: [],
        ),
        notificationSummary: NotificationSummary(
          notificationCount: 0,
          notificationIgnored: 0,
          notificationIgnoreRate: 0.0,
          notificationClusteringIndex: 0.0,
          callCount: 0,
          callIgnored: 0,
        ),
        systemState: SystemState(
          internetState: true,
          doNotDisturb: false,
          charging: false,
        ),
      );

      expect(summary.sessionId, 'test-session');
      expect(summary.startAt, '2025-01-01T10:00:00.000Z');
      expect(summary.endAt, '2025-01-01T10:00:01.000Z');
      expect(summary.durationMs, 1000);
      expect(summary.activitySummary.totalEvents, 0);
      expect(summary.activitySummary.appSwitchCount, 0);
    });

    test('creates with all fields', () {
      final summary = BehaviorSessionSummary(
        sessionId: 'test-session',
        startAt: '2025-01-01T10:00:00.000Z',
        endAt: '2025-01-01T10:00:01.000Z',
        microSession: false,
        os: 'Android 12',
        sessionSpacing: 0,
        deviceContext: DeviceContext(
          avgScreenBrightness: 0.5,
          startOrientation: 'portrait',
          orientationChanges: 0,
        ),
        activitySummary: ActivitySummary(
          totalEvents: 10,
          appSwitchCount: 3,
        ),
        behavioralMetrics: BehavioralMetrics(
          interactionIntensity: 0.5,
          taskSwitchRate: 0.2,
          taskSwitchCost: 100,
          idleTimeRatio: 0.1,
          activeTimeRatio: 0.9,
          notificationLoad: 0.0,
          burstiness: 0.3,
          behavioralDistractionScore: 0.2,
          focusHint: 0.8,
          fragmentedIdleRatio: 0.15,
          scrollJitterRate: 0.05,
          deepFocusBlocks: [],
        ),
        notificationSummary: NotificationSummary(
          notificationCount: 0,
          notificationIgnored: 0,
          notificationIgnoreRate: 0.0,
          notificationClusteringIndex: 0.0,
          callCount: 0,
          callIgnored: 0,
        ),
        systemState: SystemState(
          internetState: true,
          doNotDisturb: false,
          charging: false,
        ),
      );

      expect(summary.activitySummary.totalEvents, 10);
      expect(summary.activitySummary.appSwitchCount, 3);
      expect(summary.behavioralMetrics.interactionIntensity, 0.5);
      expect(summary.behavioralMetrics.fragmentedIdleRatio, 0.15);
    });

    test('fromJson creates summary correctly', () {
      final json = {
        'session_id': 'test-session',
        'start_at': '2025-01-01T10:00:00.000Z',
        'end_at': '2025-01-01T10:00:01.000Z',
        'micro_session': false,
        'OS': 'Android 12',
        'session_spacing': 0,
        'device_context': {
          'avg_screen_brightness': 0.5,
          'start_orientation': 'portrait',
          'orientation_changes': 0,
        },
        'activity_summary': {
          'total_events': 10,
          'app_switch_count': 3,
        },
        'behavioral_metrics': {
          'interaction_intensity': 0.5,
          'task_switch_rate': 0.2,
          'task_switch_cost': 100,
          'idle_time_ratio': 0.1,
          'active_time_ratio': 0.9,
          'notification_load': 0.0,
          'burstiness': 0.3,
          'behavioral_distraction_score': 0.2,
          'focus_hint': 0.8,
          'fragmented_idle_ratio': 0.15,
          'scroll_jitter_rate': 0.05,
          'deep_focus_blocks': [],
        },
        'notification_summary': {
          'notification_count': 0,
          'notification_ignored': 0,
          'notification_ignore_rate': 0.0,
          'notification_clustering_index': 0.0,
          'call_count': 0,
          'call_ignored': 0,
        },
        'system_state': {
          'internet_state': true,
          'do_not_disturb': false,
          'charging': false,
        },
      };

      final summary = BehaviorSessionSummary.fromJson(json);

      expect(summary.sessionId, 'test-session');
      expect(summary.durationMs, 1000);
      expect(summary.activitySummary.totalEvents, 10);
      expect(summary.behavioralMetrics.interactionIntensity, 0.5);
    });

    test('toJson converts correctly', () {
      final summary = BehaviorSessionSummary(
        sessionId: 'test-session',
        startAt: '2025-01-01T10:00:00.000Z',
        endAt: '2025-01-01T10:00:01.000Z',
        microSession: false,
        os: 'Android 12',
        sessionSpacing: 0,
        deviceContext: DeviceContext(
          avgScreenBrightness: 0.5,
          startOrientation: 'portrait',
          orientationChanges: 0,
        ),
        activitySummary: ActivitySummary(
          totalEvents: 10,
          appSwitchCount: 3,
        ),
        behavioralMetrics: BehavioralMetrics(
          interactionIntensity: 0.5,
          taskSwitchRate: 0.2,
          taskSwitchCost: 100,
          idleTimeRatio: 0.1,
          activeTimeRatio: 0.9,
          notificationLoad: 0.0,
          burstiness: 0.3,
          behavioralDistractionScore: 0.2,
          focusHint: 0.8,
          fragmentedIdleRatio: 0.15,
          scrollJitterRate: 0.05,
          deepFocusBlocks: [],
        ),
        notificationSummary: NotificationSummary(
          notificationCount: 0,
          notificationIgnored: 0,
          notificationIgnoreRate: 0.0,
          notificationClusteringIndex: 0.0,
          callCount: 0,
          callIgnored: 0,
        ),
        systemState: SystemState(
          internetState: true,
          doNotDisturb: false,
          charging: false,
        ),
      );

      final json = summary.toJson();

      expect(json['session_id'], 'test-session');
      expect(json['start_at'], '2025-01-01T10:00:00.000Z');
      expect(json['end_at'], '2025-01-01T10:00:01.000Z');
      expect(json['activity_summary']['total_events'], 10);
      expect(json['behavioral_metrics']['interaction_intensity'], 0.5);
    });

    test('durationMs getter calculates correctly', () {
      final summary = BehaviorSessionSummary(
        sessionId: 'test-session',
        startAt: '2025-01-01T10:00:00.000Z',
        endAt: '2025-01-01T10:00:05.000Z',
        microSession: false,
        os: 'Android 12',
        sessionSpacing: 0,
        deviceContext: DeviceContext(
          avgScreenBrightness: 0.5,
          startOrientation: 'portrait',
          orientationChanges: 0,
        ),
        activitySummary: ActivitySummary(
          totalEvents: 0,
          appSwitchCount: 0,
        ),
        behavioralMetrics: BehavioralMetrics(
          interactionIntensity: 0.0,
          taskSwitchRate: 0.0,
          taskSwitchCost: 0,
          idleTimeRatio: 0.0,
          activeTimeRatio: 0.0,
          notificationLoad: 0.0,
          burstiness: 0.0,
          behavioralDistractionScore: 0.0,
          focusHint: 0.0,
          fragmentedIdleRatio: 0.0,
          scrollJitterRate: 0.0,
          deepFocusBlocks: [],
        ),
        notificationSummary: NotificationSummary(
          notificationCount: 0,
          notificationIgnored: 0,
          notificationIgnoreRate: 0.0,
          notificationClusteringIndex: 0.0,
          callCount: 0,
          callIgnored: 0,
        ),
        systemState: SystemState(
          internetState: true,
          doNotDisturb: false,
          charging: false,
        ),
      );

      expect(summary.durationMs, 5000);
    });
  });
}
