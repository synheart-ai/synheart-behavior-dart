import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'models/behavior_event.dart';

/// A widget that wraps the app to detect gestures for behavior tracking.
///
/// This is needed because Flutter widgets are not native Android/iOS views,
/// so native touch listeners won't capture Flutter widget interactions.
class BehaviorGestureDetector extends StatefulWidget {
  final Widget child;
  final Function(BehaviorEvent)? onEvent;

  const BehaviorGestureDetector({
    super.key,
    required this.child,
    this.onEvent,
  });

  @override
  State<BehaviorGestureDetector> createState() =>
      _BehaviorGestureDetectorState();
}

class _BehaviorGestureDetectorState extends State<BehaviorGestureDetector> {
  int _tapCount = 0;
  DateTime? _lastScrollTime;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (notification) {
        // Calculate scroll velocity from scroll notifications
        final now = DateTime.now();
        if (_lastScrollTime != null) {
          final timeDelta = now.difference(_lastScrollTime!).inMilliseconds;
          if (timeDelta > 0 && notification.scrollDelta != null) {
            // Velocity in pixels per second
            final velocity =
                (notification.scrollDelta!.abs() / timeDelta * 1000)
                    .clamp(0.0, 10000.0);
            if (velocity > 10.0) {
              // Only emit if significant movement
              _emitScrollEvent(velocity);
            }
          }
        }
        _lastScrollTime = now;
        return false; // Don't consume the notification
      },
      child: GestureDetector(
        onTapDown: (_) => _emitTapEvent(),
        onPanUpdate: (details) {
          // Also detect pan gestures as potential scrolls
          final velocity = (details.delta.dy.abs() * 60).clamp(0.0, 10000.0);
          if (velocity > 10.0) {
            _emitScrollEvent(velocity);
          }
        },
        child: Listener(
          onPointerDown: (_) => _emitTapEvent(),
          child: widget.child,
        ),
      ),
    );
  }

  void _emitTapEvent() {
    _tapCount++;
    widget.onEvent?.call(
      BehaviorEvent(
        sessionId: "current",
        timestamp: DateTime.now().millisecondsSinceEpoch,
        type: BehaviorEventType.tapRate,
        payload: {
          'tap_rate': 0.0,
          'taps_in_window': _tapCount,
          'window_seconds': 10,
        },
      ),
    );
  }

  void _emitScrollEvent(double velocity) {
    widget.onEvent?.call(
      BehaviorEvent(
        sessionId: "current",
        timestamp: DateTime.now().millisecondsSinceEpoch,
        type: BehaviorEventType.scrollVelocity,
        payload: {
          'velocity': velocity,
          'unit': 'pixels_per_second',
        },
      ),
    );
  }
}

/// A TextField wrapper that detects keystrokes for behavior tracking.
class BehaviorTextField extends StatefulWidget {
  final TextEditingController? controller;
  final InputDecoration? decoration;
  final int? maxLines;
  final Function(BehaviorEvent)? onEvent;

  const BehaviorTextField({
    super.key,
    this.controller,
    this.decoration,
    this.maxLines,
    this.onEvent,
  });

  @override
  State<BehaviorTextField> createState() => _BehaviorTextFieldState();
}

class _BehaviorTextFieldState extends State<BehaviorTextField> {
  DateTime? _lastKeystrokeTime;
  int _keystrokeCount = 0;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      decoration: widget.decoration,
      maxLines: widget.maxLines,
      onChanged: (_) => _emitKeystrokeEvent(),
    );
  }

  void _emitKeystrokeEvent() {
    final now = DateTime.now();
    _keystrokeCount++;

    // Calculate inter-key latency
    final latency = _lastKeystrokeTime != null
        ? now.difference(_lastKeystrokeTime!).inMilliseconds
        : 0;

    widget.onEvent?.call(
      BehaviorEvent(
        sessionId: "current",
        timestamp: now.millisecondsSinceEpoch,
        type: BehaviorEventType.typingCadence,
        payload: {
          'cadence': 0.0,
          'inter_key_latency': latency,
          'keys_in_window': _keystrokeCount,
        },
      ),
    );

    _lastKeystrokeTime = now;
  }
}
