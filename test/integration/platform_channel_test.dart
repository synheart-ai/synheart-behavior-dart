import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_behavior/synheart_behavior.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('ai.synheart.behavior');
  final List<MethodCall> methodCalls = <MethodCall>[];
  final List<Map<String, dynamic>> receivedEvents = [];

  setUp(() {
    methodCalls.clear();
    receivedEvents.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      methodCalls.add(methodCall);

      switch (methodCall.method) {
        case 'initialize':
          return null;

        case 'startSession':
          // Simulate some events being emitted after session starts
          Future.delayed(const Duration(milliseconds: 10), () {
            _sendEvent(channel, {
              'event': {
                'event_id': 'evt_1',
                'session_id': methodCall.arguments['sessionId'],
                'timestamp': DateTime.now().toUtc().toIso8601String(),
                'event_type': 'tap',
                'metrics': {
                  'tap_duration_ms': 150,
                  'long_press': false,
                },
              },
            });
          });
          return null;

        case 'endSession':
          final sessionId = methodCall.arguments['sessionId'] as String;
          final now = DateTime.now();
          final startTime = now.subtract(const Duration(seconds: 60));
          return {
            'session_id': sessionId,
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
              'total_events': receivedEvents.length,
              'app_switch_count': 1,
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
              'fragmented_idle_ratio': 0.1,
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
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'typing_cadence': 2.5,
            'inter_key_latency': 100.0,
            'burst_length': 5,
            'scroll_velocity': 150.0,
            'scroll_acceleration': 20.0,
            'scroll_jitter': 5.0,
            'tap_rate': 1.5,
            'app_switches_per_minute': 2,
            'foreground_duration': 45.0,
            'idle_gap_seconds': 1.5,
            'stability_index': 0.9,
            'fragmentation_index': 0.1,
          };

        case 'updateConfig':
          return null;

        case 'dispose':
          return null;

        default:
          throw PlatformException(
            code: 'Unimplemented',
            details: 'Method ${methodCall.method} is not implemented',
          );
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('Platform Channel Integration', () {
    test('initialize sends correct parameters to platform', () async {
      const config = BehaviorConfig(
        enableInputSignals: true,
        enableAttentionSignals: false,
        enableMotionLite: true,
        sessionIdPrefix: 'TEST',
        eventBatchSize: 15,
        maxIdleGapSeconds: 20.0,
      );

      await SynheartBehavior.initialize(config: config);

      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'initialize');

      final args = methodCalls[0].arguments as Map;
      expect(args['enableInputSignals'], true);
      expect(args['enableAttentionSignals'], false);
      expect(args['enableMotionLite'], true);
      expect(args['sessionIdPrefix'], 'TEST');
      expect(args['eventBatchSize'], 15);
      expect(args['maxIdleGapSeconds'], 20.0);
    });

    test('startSession communicates session ID to platform', () async {
      final behavior = await SynheartBehavior.initialize();
      methodCalls.clear();

      await behavior.startSession(sessionId: 'custom-id');

      expect(methodCalls.any((call) => call.method == 'startSession'), true);
      final startCall =
          methodCalls.firstWhere((call) => call.method == 'startSession');
      expect(startCall.arguments['sessionId'], 'custom-id');
    });

    test('endSession receives summary from platform', () async {
      final behavior = await SynheartBehavior.initialize();
      final session = await behavior.startSession(sessionId: 'test-session');
      methodCalls.clear();

      final summary = await session.end();

      expect(methodCalls.any((call) => call.method == 'endSession'), true);
      expect(summary.sessionId, 'test-session');
      expect(summary.durationMs, greaterThanOrEqualTo(59000));
      expect(summary.behavioralMetrics.focusHint, 0.8);
    });

    test('getCurrentStats retrieves stats from platform', () async {
      final behavior = await SynheartBehavior.initialize();
      methodCalls.clear();

      final stats = await behavior.getCurrentStats();

      expect(methodCalls.any((call) => call.method == 'getCurrentStats'), true);
      // expect(stats.typingCadence, 2.5);
      expect(stats.scrollVelocity, 150.0);
      expect(stats.stabilityIndex, 0.9);
    });

    test('updateConfig sends new config to platform', () async {
      final behavior = await SynheartBehavior.initialize();
      methodCalls.clear();

      const newConfig = BehaviorConfig(
        enableInputSignals: false,
        eventBatchSize: 25,
      );

      await behavior.updateConfig(newConfig);

      expect(methodCalls.any((call) => call.method == 'updateConfig'), true);
      final updateCall =
          methodCalls.firstWhere((call) => call.method == 'updateConfig');
      expect(updateCall.arguments['enableInputSignals'], false);
      expect(updateCall.arguments['eventBatchSize'], 25);
    });

    test('dispose cleans up platform resources', () async {
      final behavior = await SynheartBehavior.initialize();
      methodCalls.clear();

      await behavior.dispose();

      expect(methodCalls.any((call) => call.method == 'dispose'), true);
    });

    test('event stream receives events from platform', () async {
      final behavior = await SynheartBehavior.initialize();
      final events = <BehaviorEvent>[];

      behavior.onEvent.listen(events.add);

      // Simulate events from platform
      await _sendEvent(channel, {
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
      });

      await _sendEvent(channel, {
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
      });

      await Future.delayed(const Duration(milliseconds: 100));

      expect(events.length, 2);
      expect(events[0].eventType, BehaviorEventType.tap);
      expect(events[1].eventType, BehaviorEventType.scroll);
    });

    test('handles platform exceptions gracefully', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        throw PlatformException(
          code: 'ERROR',
          message: 'Test error',
        );
      });

      expect(
        () => SynheartBehavior.initialize(),
        throwsA(isA<Exception>()),
      );
    });

    test('session lifecycle end-to-end', () async {
      final behavior = await SynheartBehavior.initialize();
      final events = <BehaviorEvent>[];

      behavior.onEvent.listen((event) {
        events.add(event);
        receivedEvents.add(event.toJson());
      });

      // Start session
      final session = await behavior.startSession(sessionId: 'e2e-session');
      expect(behavior.currentSessionId, 'e2e-session');

      // Wait for some events
      await Future.delayed(const Duration(milliseconds: 50));

      // Get stats during session
      final stats = await behavior.getCurrentStats();
      expect(stats.timestamp, greaterThan(0));

      // End session
      final summary = await session.end();
      expect(summary.sessionId, 'e2e-session');
      expect(summary.activitySummary.totalEvents, receivedEvents.length);
      expect(behavior.currentSessionId, isNull);
    });

    test('multiple sessions tracked separately', () async {
      final behavior = await SynheartBehavior.initialize();

      final session1 = await behavior.startSession(sessionId: 'session-1');
      expect(behavior.currentSessionId, 'session-1');

      final summary1 = await session1.end();
      expect(summary1.sessionId, 'session-1');
      expect(behavior.currentSessionId, isNull);

      final session2 = await behavior.startSession(sessionId: 'session-2');
      expect(behavior.currentSessionId, 'session-2');

      final summary2 = await session2.end();
      expect(summary2.sessionId, 'session-2');
      expect(behavior.currentSessionId, isNull);
    });
  });
}

Future<void> _sendEvent(
    MethodChannel channel, Map<String, dynamic> event) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    channel.name,
    channel.codec.encodeMethodCall(
      MethodCall('onEvent', event),
    ),
    (_) {},
  );
}
