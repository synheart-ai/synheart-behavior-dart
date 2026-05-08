import 'package:flutter_test/flutter_test.dart';
import 'package:synheart_behavior/synheart_behavior.dart';

void main() {
  group('BehaviorConfig', () {
    test('creates with default values', () {
      const config = BehaviorConfig();

      expect(config.enableInputSignals, true);
      expect(config.enableAttentionSignals, true);
      expect(config.enableMotionLite, false);
      expect(config.sessionIdPrefix, isNull);
      expect(config.eventBatchSize, 10);
      expect(config.maxIdleGapSeconds, 10.0);
    });

    test('creates with custom values', () {
      const config = BehaviorConfig(
        enableInputSignals: false,
        enableAttentionSignals: false,
        enableMotionLite: true,
        sessionIdPrefix: 'CUSTOM',
        eventBatchSize: 20,
        maxIdleGapSeconds: 15.0,
      );

      expect(config.enableInputSignals, false);
      expect(config.enableAttentionSignals, false);
      expect(config.enableMotionLite, true);
      expect(config.sessionIdPrefix, 'CUSTOM');
      expect(config.eventBatchSize, 20);
      expect(config.maxIdleGapSeconds, 15.0);
    });

    test('toJson converts correctly', () {
      const config = BehaviorConfig(
        enableInputSignals: true,
        enableAttentionSignals: false,
        sessionIdPrefix: 'TEST',
        eventBatchSize: 15,
      );

      final json = config.toJson();

      expect(json['enableInputSignals'], true);
      expect(json['enableAttentionSignals'], false);
      expect(json['enableMotionLite'], false);
      expect(json['sessionIdPrefix'], 'TEST');
      expect(json['eventBatchSize'], 15);
      expect(json['maxIdleGapSeconds'], 10.0);
    });

    test('handles null sessionIdPrefix', () {
      const config = BehaviorConfig();
      final json = config.toJson();

      expect(json['sessionIdPrefix'], isNull);
    });
  });
}
