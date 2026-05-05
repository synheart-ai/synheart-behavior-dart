/// Raw 3-axis accelerometer sample produced by the native motion collector.
///
/// Emitted by [SynheartBehavior.onMotionSample] in batches (typically ~50
/// samples per 1-second window at 50 Hz) so the upstream runtime can run its
/// own feature extraction and `MotionStateHead` per the motion-state spec.
///
/// The behavior SDK does not interpret these samples — they are passed through
/// for the runtime to consume.
class MotionSample {
  /// UTC epoch milliseconds.
  final int tsMs;

  /// X-axis acceleration in m/s² (gravity included).
  final double ax;

  /// Y-axis acceleration in m/s² (gravity included).
  final double ay;

  /// Z-axis acceleration in m/s² (gravity included).
  final double az;

  const MotionSample({
    required this.tsMs,
    required this.ax,
    required this.ay,
    required this.az,
  });

  /// Parse a single sample from the native MethodChannel payload.
  ///
  /// Expected shape: `{ "ts_ms": int, "ax": double, "ay": double, "az": double }`.
  factory MotionSample.fromMap(Map<dynamic, dynamic> map) {
    return MotionSample(
      tsMs: (map['ts_ms'] as num).toInt(),
      ax: (map['ax'] as num).toDouble(),
      ay: (map['ay'] as num).toDouble(),
      az: (map['az'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'ts_ms': tsMs,
        'ax': ax,
        'ay': ay,
        'az': az,
      };

  @override
  String toString() => 'MotionSample(tsMs=$tsMs, ax=$ax, ay=$ay, az=$az)';
}
