import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_behavior/synheart_behavior.dart';

void main() {
  group('BehaviorEvent', () {
    test('creates event with required fields', () {
      final event = BehaviorEvent(
        sessionId: 'test-session',
        timestamp: 1000,
        type: BehaviorEventType.typingCadence,
        payload: {'cadence': 2.5},
      );

      expect(event.sessionId, 'test-session');
      expect(event.timestamp, 1000);
      expect(event.type, BehaviorEventType.typingCadence);
      expect(event.payload['cadence'], 2.5);
    });

    test('fromJson creates event correctly', () {
      final json = {
        'session_id': 'test-session',
        'timestamp': 1000,
        'type': 'typingCadence',
        'payload': {
          'cadence': 2.5,
          'inter_key_latency': 100.0,
        },
      };

      final event = BehaviorEvent.fromJson(json);

      expect(event.sessionId, 'test-session');
      expect(event.timestamp, 1000);
      expect(event.type, BehaviorEventType.typingCadence);
      expect(event.payload['cadence'], 2.5);
      expect(event.payload['inter_key_latency'], 100.0);
    });

    test('toJson converts correctly', () {
      final event = BehaviorEvent(
        sessionId: 'test-session',
        timestamp: 1000,
        type: BehaviorEventType.scrollVelocity,
        payload: {'velocity': 150.0},
      );

      final json = event.toJson();

      expect(json['session_id'], 'test-session');
      expect(json['timestamp'], 1000);
      expect(json['type'], 'scrollVelocity');
      expect(json['payload']['velocity'], 150.0);
    });

    test('toString provides readable output', () {
      final event = BehaviorEvent(
        sessionId: 'test-session',
        timestamp: 1000,
        type: BehaviorEventType.typingCadence,
        payload: {},
      );

      final str = event.toString();

      expect(str, contains('test-session'));
      expect(str, contains('typingCadence'));
      expect(str, contains('1000'));
    });

    group('BehaviorEventType', () {
      test('has all expected event types', () {
        expect(BehaviorEventType.values.length, greaterThanOrEqualTo(20));

        // Keystroke events
        expect(BehaviorEventType.values, contains(BehaviorEventType.typingCadence));
        expect(BehaviorEventType.values, contains(BehaviorEventType.typingBurst));

        // Scroll events
        expect(BehaviorEventType.values, contains(BehaviorEventType.scrollVelocity));
        expect(BehaviorEventType.values, contains(BehaviorEventType.scrollAcceleration));
        expect(BehaviorEventType.values, contains(BehaviorEventType.scrollJitter));
        expect(BehaviorEventType.values, contains(BehaviorEventType.scrollStop));

        // Gesture events
        expect(BehaviorEventType.values, contains(BehaviorEventType.tapRate));
        expect(BehaviorEventType.values, contains(BehaviorEventType.longPressRate));
        expect(BehaviorEventType.values, contains(BehaviorEventType.dragVelocity));

        // App switching events
        expect(BehaviorEventType.values, contains(BehaviorEventType.appSwitch));
        expect(BehaviorEventType.values, contains(BehaviorEventType.foregroundDuration));

        // Idle events
        expect(BehaviorEventType.values, contains(BehaviorEventType.idleGap));
        expect(BehaviorEventType.values, contains(BehaviorEventType.microIdle));
        expect(BehaviorEventType.values, contains(BehaviorEventType.midIdle));
        expect(BehaviorEventType.values, contains(BehaviorEventType.taskDropIdle));

        // Session events
        expect(BehaviorEventType.values, contains(BehaviorEventType.sessionStability));
        expect(BehaviorEventType.values, contains(BehaviorEventType.fragmentationIndex));
      });

      test('event type enum name matches string', () {
        expect(BehaviorEventType.typingCadence.name, 'typingCadence');
        expect(BehaviorEventType.scrollVelocity.name, 'scrollVelocity');
        expect(BehaviorEventType.appSwitch.name, 'appSwitch');
      });
    });
  });
}
