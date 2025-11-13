import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_behavior/synheart_behavior.dart';

void main() {
  group('BehaviorSession', () {
    test('creates with required fields', () {
      Future<BehaviorSessionSummary> mockCallback(String sessionId) async {
        return BehaviorSessionSummary(
          sessionId: sessionId,
          startTimestamp: 1000,
          endTimestamp: 2000,
          duration: 1000,
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
          startTimestamp: 1000,
          endTimestamp: 2000,
          duration: 1000,
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
          startTimestamp: 1000,
          endTimestamp: 2000,
          duration: 1000,
          eventCount: 10,
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
      expect(summary.duration, 1000);
      expect(summary.eventCount, 10);
    });
  });

  group('BehaviorSessionSummary', () {
    test('creates with required fields', () {
      final summary = BehaviorSessionSummary(
        sessionId: 'test-session',
        startTimestamp: 1000,
        endTimestamp: 2000,
        duration: 1000,
      );

      expect(summary.sessionId, 'test-session');
      expect(summary.startTimestamp, 1000);
      expect(summary.endTimestamp, 2000);
      expect(summary.duration, 1000);
      expect(summary.eventCount, 0);
      expect(summary.appSwitchCount, 0);
    });

    test('creates with all fields', () {
      final summary = BehaviorSessionSummary(
        sessionId: 'test-session',
        startTimestamp: 1000,
        endTimestamp: 2000,
        duration: 1000,
        eventCount: 10,
        averageTypingCadence: 2.5,
        averageScrollVelocity: 150.0,
        appSwitchCount: 3,
        stabilityIndex: 0.85,
        fragmentationIndex: 0.15,
      );

      expect(summary.eventCount, 10);
      expect(summary.averageTypingCadence, 2.5);
      expect(summary.averageScrollVelocity, 150.0);
      expect(summary.appSwitchCount, 3);
      expect(summary.stabilityIndex, 0.85);
      expect(summary.fragmentationIndex, 0.15);
    });

    test('fromJson creates summary correctly', () {
      final json = {
        'session_id': 'test-session',
        'start_timestamp': 1000,
        'end_timestamp': 2000,
        'duration': 1000,
        'event_count': 10,
        'average_typing_cadence': 2.5,
        'average_scroll_velocity': 150.0,
        'app_switch_count': 3,
        'stability_index': 0.85,
        'fragmentation_index': 0.15,
      };

      final summary = BehaviorSessionSummary.fromJson(json);

      expect(summary.sessionId, 'test-session');
      expect(summary.duration, 1000);
      expect(summary.eventCount, 10);
      expect(summary.averageTypingCadence, 2.5);
      expect(summary.stabilityIndex, 0.85);
    });

    test('toJson converts correctly', () {
      final summary = BehaviorSessionSummary(
        sessionId: 'test-session',
        startTimestamp: 1000,
        endTimestamp: 2000,
        duration: 1000,
        eventCount: 10,
        averageTypingCadence: 2.5,
        stabilityIndex: 0.85,
      );

      final json = summary.toJson();

      expect(json['session_id'], 'test-session');
      expect(json['start_timestamp'], 1000);
      expect(json['end_timestamp'], 2000);
      expect(json['duration'], 1000);
      expect(json['event_count'], 10);
      expect(json['average_typing_cadence'], 2.5);
      expect(json['stability_index'], 0.85);
    });

    test('handles null optional fields', () {
      final summary = BehaviorSessionSummary(
        sessionId: 'test-session',
        startTimestamp: 1000,
        endTimestamp: 2000,
        duration: 1000,
      );

      expect(summary.averageTypingCadence, isNull);
      expect(summary.averageScrollVelocity, isNull);
      expect(summary.stabilityIndex, isNull);
      expect(summary.fragmentationIndex, isNull);
    });

    test('defaults counts to 0', () {
      final json = {
        'session_id': 'test-session',
        'start_timestamp': 1000,
        'end_timestamp': 2000,
        'duration': 1000,
      };

      final summary = BehaviorSessionSummary.fromJson(json);

      expect(summary.eventCount, 0);
      expect(summary.appSwitchCount, 0);
    });
  });
}
