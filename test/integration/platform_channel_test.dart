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
              'session_id': methodCall.arguments['sessionId'],
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'type': 'typingCadence',
              'payload': {'cadence': 2.5, 'inter_key_latency': 100.0},
            });
          });
          return null;

        case 'endSession':
          final sessionId = methodCall.arguments['sessionId'] as String;
          return {
            'session_id': sessionId,
            'start_timestamp': DateTime.now().millisecondsSinceEpoch - 60000,
            'end_timestamp': DateTime.now().millisecondsSinceEpoch,
            'duration': 60000,
            'event_count': receivedEvents.length,
            'average_typing_cadence': 2.5,
            'average_scroll_velocity': 150.0,
            'app_switch_count': 1,
            'stability_index': 0.9,
            'fragmentation_index': 0.1,
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
      expect(summary.duration, 60000);
      expect(summary.stabilityIndex, 0.9);
    });

    test('getCurrentStats retrieves stats from platform', () async {
      final behavior = await SynheartBehavior.initialize();
      methodCalls.clear();

      final stats = await behavior.getCurrentStats();

      expect(methodCalls.any((call) => call.method == 'getCurrentStats'), true);
      expect(stats.typingCadence, 2.5);
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
        'session_id': 'test-session',
        'timestamp': 1000,
        'type': 'typingCadence',
        'payload': {'cadence': 2.5},
      });

      await _sendEvent(channel, {
        'session_id': 'test-session',
        'timestamp': 2000,
        'type': 'scrollVelocity',
        'payload': {'velocity': 150.0},
      });

      await Future.delayed(const Duration(milliseconds: 100));

      expect(events.length, 2);
      expect(events[0].type, BehaviorEventType.typingCadence);
      expect(events[1].type, BehaviorEventType.scrollVelocity);
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
      expect(summary.eventCount, receivedEvents.length);
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
