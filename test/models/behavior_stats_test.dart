import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_behavior/synheart_behavior.dart';

void main() {
  group('BehaviorStats', () {
    test('creates with all fields', () {
      const stats = BehaviorStats(
        scrollVelocity: 150.0,
        scrollAcceleration: 20.0,
        scrollJitter: 5.0,
        tapRate: 1.5,
        appSwitchesPerMinute: 3,
        foregroundDuration: 60.0,
        idleGapSeconds: 2.0,
        stabilityIndex: 0.85,
        fragmentationIndex: 0.15,
        timestamp: 1000,
      );

      expect(stats.scrollVelocity, 150.0);
      expect(stats.scrollAcceleration, 20.0);
      expect(stats.scrollJitter, 5.0);
      expect(stats.tapRate, 1.5);
      expect(stats.appSwitchesPerMinute, 3);
      expect(stats.foregroundDuration, 60.0);
      expect(stats.idleGapSeconds, 2.0);
      expect(stats.stabilityIndex, 0.85);
      expect(stats.fragmentationIndex, 0.15);
      expect(stats.timestamp, 1000);
    });

    test('creates with null optional fields', () {
      const stats = BehaviorStats(
        timestamp: 1000,
      );

      expect(stats.scrollVelocity, isNull);
      expect(stats.appSwitchesPerMinute, 0);
      expect(stats.timestamp, 1000);
    });

    test('fromJson creates stats correctly', () {
      final json = {
        'scroll_velocity': 150.0,
        'scroll_acceleration': 20.0,
        'scroll_jitter': 5.0,
        'tap_rate': 1.5,
        'app_switches_per_minute': 3,
        'foreground_duration': 60.0,
        'idle_gap_seconds': 2.0,
        'stability_index': 0.85,
        'fragmentation_index': 0.15,
        'timestamp': 1000,
      };

      final stats = BehaviorStats.fromJson(json);

      expect(stats.scrollVelocity, 150.0);
      expect(stats.appSwitchesPerMinute, 3);
      expect(stats.stabilityIndex, 0.85);
      expect(stats.timestamp, 1000);
    });

    test('toJson converts correctly', () {
      const stats = BehaviorStats(
        scrollVelocity: 150.0,
        appSwitchesPerMinute: 3,
        timestamp: 1000,
      );

      final json = stats.toJson();

      expect(json['scroll_velocity'], 150.0);
      expect(json['app_switches_per_minute'], 3);
      expect(json['timestamp'], 1000);
    });

    test('handles null values in fromJson', () {
      final json = {
        'timestamp': 1000,
        'scroll_velocity': null,
      };

      final stats = BehaviorStats.fromJson(json);

      expect(stats.scrollVelocity, isNull);
      expect(stats.timestamp, 1000);
    });

    test('defaults app_switches_per_minute to 0', () {
      final json = {
        'timestamp': 1000,
      };

      final stats = BehaviorStats.fromJson(json);

      expect(stats.appSwitchesPerMinute, 0);
    });
  });
}
