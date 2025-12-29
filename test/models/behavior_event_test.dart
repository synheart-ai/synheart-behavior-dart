import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_behavior/synheart_behavior.dart';

void main() {
  group('BehaviorEvent', () {
    test('creates event with required fields', () {
      final event = BehaviorEvent(
        sessionId: 'test-session',
        eventType: BehaviorEventType.tap,
        metrics: {'tap_duration_ms': 150, 'long_press': false},
      );

      expect(event.sessionId, 'test-session');
      expect(event.eventType, BehaviorEventType.tap);
      expect(event.metrics['tap_duration_ms'], 150);
      expect(event.metrics['long_press'], false);
    });

    test('fromJson creates event correctly', () {
      final json = {
        'event': {
          'event_id': 'evt_123',
          'session_id': 'test-session',
          'timestamp': '2025-01-01T10:00:00.000Z',
          'event_type': 'tap',
          'metrics': {
            'tap_duration_ms': 150,
            'long_press': false,
          },
        },
      };

      final event = BehaviorEvent.fromJson(json);

      expect(event.sessionId, 'test-session');
      expect(event.eventType, BehaviorEventType.tap);
      expect(event.metrics['tap_duration_ms'], 150);
      expect(event.metrics['long_press'], false);
    });

    test('toJson converts correctly', () {
      final event = BehaviorEvent.scroll(
        sessionId: 'test-session',
        velocity: 150.0,
        acceleration: 50.0,
        direction: ScrollDirection.down,
        directionReversal: false,
      );

      final json = event.toJson();

      expect(json['event']['session_id'], 'test-session');
      expect(json['event']['event_type'], 'scroll');
      expect(json['event']['metrics']['velocity'], 150.0);
    });

    test('toString provides readable output', () {
      final event = BehaviorEvent.tap(
        sessionId: 'test-session',
        tapDurationMs: 150,
        longPress: false,
      );

      final str = event.toString();

      expect(str, contains('test-session'));
      expect(str, contains('tap'));
    });

    group('BehaviorEventType', () {
      test('has all expected event types', () {
        expect(BehaviorEventType.values.length, 6);

        expect(BehaviorEventType.values, contains(BehaviorEventType.scroll));
        expect(BehaviorEventType.values, contains(BehaviorEventType.tap));
        expect(BehaviorEventType.values, contains(BehaviorEventType.swipe));
        expect(
            BehaviorEventType.values, contains(BehaviorEventType.notification));
        expect(BehaviorEventType.values, contains(BehaviorEventType.call));
        expect(BehaviorEventType.values, contains(BehaviorEventType.typing));
      });

      test('event type enum name matches string', () {
        expect(BehaviorEventType.tap.name, 'tap');
        expect(BehaviorEventType.scroll.name, 'scroll');
        expect(BehaviorEventType.notification.name, 'notification');
      });
    });

    group('Factory methods', () {
      test('BehaviorEvent.tap creates tap event', () {
        final event = BehaviorEvent.tap(
          sessionId: 'test-session',
          tapDurationMs: 200,
          longPress: true,
        );

        expect(event.eventType, BehaviorEventType.tap);
        expect(event.metrics['tap_duration_ms'], 200);
        expect(event.metrics['long_press'], true);
      });

      test('BehaviorEvent.scroll creates scroll event', () {
        final event = BehaviorEvent.scroll(
          sessionId: 'test-session',
          velocity: 500.0,
          acceleration: 50.0,
          direction: ScrollDirection.up,
          directionReversal: true,
        );

        expect(event.eventType, BehaviorEventType.scroll);
        expect(event.metrics['velocity'], 500.0);
        expect(event.metrics['direction'], 'up');
        expect(event.metrics['direction_reversal'], true);
      });

      test('BehaviorEvent.swipe creates swipe event', () {
        final event = BehaviorEvent.swipe(
          sessionId: 'test-session',
          direction: SwipeDirection.left,
          distancePx: 200.0,
          durationMs: 300,
          velocity: 600.0,
          acceleration: 50.0,
        );

        expect(event.eventType, BehaviorEventType.swipe);
        expect(event.metrics['direction'], 'left');
        expect(event.metrics['distance_px'], 200.0);
      });

      test('BehaviorEvent.notification creates notification event', () {
        final event = BehaviorEvent.notification(
          sessionId: 'test-session',
          action: InterruptionAction.ignored,
        );

        expect(event.eventType, BehaviorEventType.notification);
        expect(event.metrics['action'], 'ignored');
      });

      test('BehaviorEvent.call creates call event', () {
        final event = BehaviorEvent.call(
          sessionId: 'test-session',
          action: InterruptionAction.answered,
        );

        expect(event.eventType, BehaviorEventType.call);
        expect(event.metrics['action'], 'answered');
      });
    });
  });
}
