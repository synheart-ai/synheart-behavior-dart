import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_behavior/synheart_behavior.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('ai.synheart.behavior');
  final List<MethodCall> methodCalls = <MethodCall>[];

  setUp(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      methodCalls.add(methodCall);
      switch (methodCall.method) {
        case 'initialize':
          return null;
        case 'startSession':
          return null;
        case 'endSession':
          final now = DateTime.now();
          final startTime = now.subtract(const Duration(seconds: 1));
          return {
            'session_id': 'test-session',
            'start_at': startTime.toUtc().toIso8601String(),
            'end_at': now.toUtc().toIso8601String(),
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
              'app_switch_count': 2,
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
        case 'getCurrentStats':
          return {
            'timestamp': 1000,
            'typing_cadence': 2.5,
            'inter_key_latency': 100.0,
            'burst_length': 5,
            'scroll_velocity': 150.0,
            'scroll_acceleration': 20.0,
            'scroll_jitter': 5.0,
            'tap_rate': 1.5,
            'app_switches_per_minute': 3,
            'foreground_duration': 60.0,
            'idle_gap_seconds': 2.0,
            'stability_index': 0.85,
            'fragmentation_index': 0.15,
          };
        case 'updateConfig':
          return null;
        case 'dispose':
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('SynheartBehavior Initialization', () {
    test('initialize with default config', () async {
      final behavior = await SynheartBehavior.initialize();

      expect(behavior.isInitialized, true);
      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'initialize');
    });

    test('initialize with custom config', () async {
      const config = BehaviorConfig(
        enableInputSignals: true,
        enableAttentionSignals: false,
        enableMotionLite: true,
        sessionIdPrefix: 'TEST',
        eventBatchSize: 20,
        maxIdleGapSeconds: 15.0,
      );

      final behavior = await SynheartBehavior.initialize(config: config);

      expect(behavior.isInitialized, true);
      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'initialize');

      final args = methodCalls[0].arguments as Map;
      expect(args['enableInputSignals'], true);
      expect(args['enableAttentionSignals'], false);
      expect(args['enableMotionLite'], true);
      expect(args['sessionIdPrefix'], 'TEST');
      expect(args['eventBatchSize'], 20);
      expect(args['maxIdleGapSeconds'], 15.0);
    });
  });

  group('Session Management', () {
    test('start session generates session ID', () async {
      final behavior = await SynheartBehavior.initialize();
      final session = await behavior.startSession();

      expect(session.sessionId, isNotEmpty);
      expect(session.sessionId, startsWith('SESS-'));
      expect(methodCalls.any((call) => call.method == 'startSession'), true);
    });

    test('start session with custom ID', () async {
      final behavior = await SynheartBehavior.initialize();
      final session =
          await behavior.startSession(sessionId: 'custom-session-id');

      expect(session.sessionId, 'custom-session-id');
    });

    test('end session returns summary', () async {
      final behavior = await SynheartBehavior.initialize();
      final session = await behavior.startSession(sessionId: 'test-session');

      final summary = await session.end();

      expect(summary.sessionId, 'test-session');
      expect(summary.durationMs, greaterThanOrEqualTo(900));
      expect(summary.activitySummary.totalEvents, 10);
      expect(summary.behavioralMetrics.interactionIntensity, 0.5);
      expect(summary.behavioralMetrics.fragmentedIdleRatio, 0.15);
      expect(methodCalls.any((call) => call.method == 'endSession'), true);
    });

    test('current session ID is tracked', () async {
      final behavior = await SynheartBehavior.initialize();

      expect(behavior.currentSessionId, isNull);

      final session = await behavior.startSession();
      expect(behavior.currentSessionId, session.sessionId);

      await session.end();
      expect(behavior.currentSessionId, isNull);
    });
  });

  group('Statistics', () {
    test('getCurrentStats returns behavior stats', () async {
      final behavior = await SynheartBehavior.initialize();
      final stats = await behavior.getCurrentStats();

      expect(stats.typingCadence, 2.5);
      expect(stats.scrollVelocity, 150.0);
      expect(stats.appSwitchesPerMinute, 3);
      expect(stats.stabilityIndex, 0.85);
      expect(methodCalls.any((call) => call.method == 'getCurrentStats'), true);
    });
  });

  group('Configuration', () {
    test('updateConfig sends new configuration', () async {
      final behavior = await SynheartBehavior.initialize();

      const newConfig = BehaviorConfig(
        enableInputSignals: false,
        enableAttentionSignals: true,
      );

      await behavior.updateConfig(newConfig);

      expect(methodCalls.any((call) => call.method == 'updateConfig'), true);
    });
  });

  group('Event Stream', () {
    test('onEvent stream receives events', () async {
      final behavior = await SynheartBehavior.initialize();

      final eventsFuture = behavior.onEvent.take(2).toList();

      // Simulate events from native platform
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          MethodCall('onEvent', {
            'event': {
              'event_id': 'evt_1',
              'session_id': 'test-session',
              'timestamp': DateTime.now().toUtc().toIso8601String(),
              'event_type': 'tap',
              'metrics': {
                'tap_duration_ms': 150,
                'long_press': false,
              },
            },
          }),
        ),
        (_) {},
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(
          MethodCall('onEvent', {
            'event': {
              'event_id': 'evt_2',
              'session_id': 'test-session',
              'timestamp': DateTime.now().toUtc().toIso8601String(),
              'event_type': 'scroll',
              'metrics': {
                'velocity': 150.0,
                'acceleration': 50.0,
                'direction': 'down',
                'direction_reversal': false,
              },
            },
          }),
        ),
        (_) {},
      );

      final events = await eventsFuture;

      expect(events.length, 2);
      expect(events[0].eventType, BehaviorEventType.tap);
      expect(events[1].eventType, BehaviorEventType.scroll);
    });
  });

  group('Disposal', () {
    test('dispose cleans up resources', () async {
      final behavior = await SynheartBehavior.initialize();
      final session = await behavior.startSession();

      await behavior.dispose();
      print(session);

      expect(behavior.isInitialized, false);
      expect(methodCalls.any((call) => call.method == 'dispose'), true);
    });
  });

  group('Error Handling', () {
    test('throws when starting session before initialization', () async {
      // Create uninitialized instance (we can't do this with current API)
      // This test validates initialization requirement
      final behavior = await SynheartBehavior.initialize();
      await behavior.dispose();

      expect(() async => await behavior.startSession(), throwsException);
    });
  });
}
